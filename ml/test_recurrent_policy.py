"""Regression tests for causal recurrent PPO inputs and deployment encoding."""
import unittest
import tempfile
from pathlib import Path
import json

import numpy as np
import torch

from train import masked_distribution, calculate_competitive_gae, physical_seat_values, save_checkpoint
from export_onnx import load_checkpoint
from window_rl.contract import (ACTION_SIZE, BOARD_FEATURE_SIZE, ACTION_FEATURE_SIZE,
                                OUTCOME_FEATURE_SIZE, REMOVED_FEATURE_SIZE, PASS_ACTION_INDEX)
from window_rl.cuda_environment import BatchedWindowEnv
from window_rl.environment import WindowTrainingEnv, LAYOUT
from window_rl.model import WindowPolicyValueNet
from window_rl.diagnostics import obviously_impossible_guesses

REWARD = {"correct_guess": 0., "wrong_drink": -1., "pass": 0., "complete_game": 0.}


class RecurrentPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def env(self, **kwargs):
        return BatchedWindowEnv(REWARD, 8, 100, torch.device('cpu'), 17, **kwargs)

    def test_stored_inputs_and_ppo_ratios_survive_steps_and_resets(self):
        torch.manual_seed(4)
        env = self.env()
        model = WindowPolicyValueNet(32)
        stored = []
        with torch.no_grad():
            for step in range(5):
                observation, mask = env.history_observation(), env.action_mask()
                before = observation.clone()
                distribution = masked_distribution(model(observation)[0], mask)
                action = distribution.sample()
                stored.append((observation, before, mask, action, distribution.log_prob(action)))
                env.step(action)
                env.reset(torch.tensor([step % env.num_envs]))
            for observation, before, mask, action, old_log_prob in stored:
                self.assertTrue(torch.equal(observation, before))
                new_log_prob = masked_distribution(model(observation)[0], mask).log_prob(action)
                torch.testing.assert_close((new_log_prob - old_log_prob).exp(), torch.ones(8))

    def test_current_record_matches_flutter_empty_removal_encoding(self):
        env = self.env()
        start = BOARD_FEATURE_SIZE + ACTION_FEATURE_SIZE + OUTCOME_FEATURE_SIZE
        expected = torch.tensor([-1. if slot else -2. for row in LAYOUT for slot in row for _ in range(2)])
        for _ in range(3):
            history = env.history_observation()
            torch.testing.assert_close(history[:, -1, start:start + REMOVED_FEATURE_SIZE], expected.expand(8, -1))
            self.assertTrue((history[:, -1, BOARD_FEATURE_SIZE:start] == 0).all())
            env.step(torch.multinomial(env.action_mask().float(), 1).squeeze(1))

    def test_hidden_cards_and_deck_do_not_change_observation_or_mask(self):
        env = self.env()
        history, mask = env.history_observation(), env.action_mask()
        env.cards[~env.face_up & env.layout] = 35
        env.deck[:] = 0
        env.deck_size[:] = 1
        env._append_current_record()
        self.assertTrue(torch.equal(history, env.history_observation()))
        self.assertTrue(torch.equal(mask, env.action_mask()))

    def test_masks_and_visible_ranks_match_reference_over_rollout(self):
        env = self.env()
        reference = WindowTrainingEnv(REWARD)
        for _ in range(20):
            for i in range(8):
                reference.cards = env.cards[i].tolist()
                reference.face_up = env.face_up[i].tolist()
                reference.must_select_adjacent_to_handle = bool(env.must_select_adjacent[i])
                reference.turn_can_end = bool(env.turn_can_end[i])
                np.testing.assert_array_equal(reference.action_mask(), env.action_mask()[i].numpy())
                np.testing.assert_array_equal(reference.observation(), env.observation()[i].numpy())
            env.step(torch.multinomial(env.action_mask().float(), 1).squeeze(1))

    def test_mask_blocks_illegal_logits_and_gradients(self):
        logits = torch.zeros(2, ACTION_SIZE, requires_grad=True)
        mask = torch.zeros_like(logits, dtype=torch.bool)
        mask[:, [3, 7]] = True
        distribution = masked_distribution(logits, mask)
        self.assertTrue((distribution.probs[~mask] == 0).all())
        distribution.log_prob(torch.tensor([3, 7])).sum().backward()
        self.assertTrue((logits.grad[~mask] == 0).all())

    def test_lstm_uses_ordered_past_and_backpropagates_into_it(self):
        torch.manual_seed(9)
        env = self.env()
        for _ in range(3):
            env.step(torch.multinomial(env.action_mask().float(), 1).squeeze(1))
        history = env.history_observation().requires_grad_()
        model = WindowPolicyValueNet(32)
        logits, value = model(history)
        (logits.square().mean() + value.square().mean()).backward()
        self.assertGreater(float(history.grad[:, -2].abs().sum()), 0.)
        swapped = history.detach().clone()
        swapped[:, [-2, -3]] = swapped[:, [-3, -2]]
        self.assertFalse(torch.allclose(logits, model(swapped)[0]))

    def test_local_action_head_shares_only_public_neighbor_features(self):
        env = self.env()
        model = WindowPolicyValueNet(32, local_action_head=True)
        history = env.history_observation()
        # Identical oriented public neighbors at two different locations must
        # receive identical local scores, irrespective of hidden card identity.
        history[:, -1, 0:2] = history[:, -1, 48:50]
        history[:, -1, 4:6] = history[:, -1, 52:54]
        scores = model.local_action_logits(history)
        torch.testing.assert_close(scores[:, 10:15], scores[:, 250:255])
        self.assertTrue((scores[:, PASS_ACTION_INDEX] == 0).all())
        changed = history.clone()
        changed[:, :-1] = torch.randn_like(changed[:, :-1])
        torch.testing.assert_close(scores, model.local_action_logits(changed))
        self.assertFalse(torch.allclose(model(history)[0], model(changed)[0]))
        scores.sum().backward()
        self.assertGreater(float(model.local_policy[0].weight.grad.abs().sum()), 0.)

    def test_local_and_legacy_checkpoints_round_trip(self):
        config = json.loads((Path(__file__).parent / 'configs/recurrent_local_validation.json').read_text())
        config['algorithm']['hidden_size'] = 32
        for enabled in (False, True):
            config['algorithm']['local_action_head'] = enabled
            model = WindowPolicyValueNet(32, local_action_head=enabled).eval()
            history = self.env().history_observation()
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'policy.pt'
                save_checkpoint(path, model, config, 123, torch.device('cpu'))
                restored, _ = load_checkpoint(path)
                torch.testing.assert_close(model(history), restored(history))

    def test_rank_diagnostic_uses_only_public_comparisons(self):
        history = self.env().history_observation()
        history[:, -1, 34] = 1.  # handle rank maximum
        self.assertTrue(obviously_impossible_guesses(history, torch.full((8,), 160)).all())
        self.assertFalse(obviously_impossible_guesses(history, torch.full((8,), 162)).any())
        history[:, -1, 34] = 0.
        self.assertTrue(obviously_impossible_guesses(history, torch.full((8,), 162)).all())
        history[:, -1, 0] = 0.
        history[:, -1, 4] = 1.
        self.assertTrue(obviously_impossible_guesses(history, torch.full((8,), 14)).all())
        self.assertFalse(obviously_impossible_guesses(history, torch.full((8,), 13)).any())
        self.assertFalse(obviously_impossible_guesses(history, torch.full((8,), 300)).any())

    def test_time_limit_bootstraps_final_state_without_crossing_reset(self):
        env = BatchedWindowEnv(REWARD, 1, 1, torch.device('cpu'), 17, player_count=1)
        env.turn_can_end[:] = True
        _, _, done, _, completed = env.step(torch.tensor([PASS_ACTION_INDEX]))
        self.assertTrue(bool(done[0]))
        self.assertFalse(bool(completed[0]))
        rewards = env.last_player_rewards.clone()
        final_values = torch.tensor([[-7., 0., 0., 0.]])
        rewards += physical_seat_values(final_values, env.current_player)
        env.reset()
        _, returns = calculate_competitive_gae(
            rewards.unsqueeze(0), done.unsqueeze(0), torch.zeros(1, 1, 4),
            torch.full((1, 4), 999.), torch.zeros(1, 1, dtype=torch.long),
            env.current_player, gamma=1., gae_lambda=1.,
        )
        self.assertEqual(float(returns[0, 0, 0]), -7.)

    def test_single_player_pass_keeps_seat_and_rewards_are_only_own_drinks(self):
        env = self.env(player_count=1)
        env.turn_can_end[:] = True
        env.step(torch.full((8,), PASS_ACTION_INDEX))
        self.assertTrue((env.current_player == 0).all())
        for _ in range(10):
            _, reward, _, drinks, _ = env.step(torch.multinomial(env.action_mask().float(), 1).squeeze(1))
            torch.testing.assert_close(reward, -drinks.float())
            torch.testing.assert_close(env.last_player_rewards[:, 0], reward)
            self.assertTrue((env.last_player_rewards[:, 1:] == 0).all())


if __name__ == '__main__':
    unittest.main()
