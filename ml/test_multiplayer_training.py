"""Competitive accounting and end-to-end public-history training regressions."""
import contextlib
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import torch
from export_onnx import load_checkpoint
from train import evaluate_held_out, initialize_model, linear_schedule, save_checkpoint, evaluate, main, physical_seat_values, relative_seat_values, calculate_competitive_gae, active_value_loss, training_player_counts
from window_rl.contract import HISTORY_FEATURE_SIZE, PASS_ACTION_INDEX
from window_rl.cuda_environment import BatchedWindowEnv
from window_rl.model import WindowPolicyValueNet

REWARD = dict(correct_guess=0, wrong_drink=-1, complete_game=0, **{'pass': 0})

class MultiplayerTrainingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def test_public_player_context_padding_and_turn_wrap(self):
        for count in range(1, 5):
            env = BatchedWindowEnv(REWARD, 2, 100, torch.device('cpu'), 42, 33, count)
            original = env.history_observation()
            self.assertFalse(original[:, :-1].any())
            self.assertEqual(original[0, -1, 130:].tolist(), [float(i == count) for i in range(1, 5)])
            env.turn_can_end[:] = True
            if count == 1:
                self.assertFalse(env.action_mask()[:, PASS_ACTION_INDEX].any())
                with self.assertRaisesRegex(ValueError, "Illegal action"):
                    env.step(torch.full((2,), PASS_ACTION_INDEX))
            else:
                env.step(torch.full((2,), PASS_ACTION_INDEX))
                self.assertTrue((env.current_player == 1).all())
            torch.testing.assert_close(original[:, -1, 130:], env.history_observation()[:, -1, 130:])
            self.assertFalse(original[:, :-1].any())

    def test_critic_rotations_and_gradients_for_all_table_sizes(self):
        for count in range(1, 5):
            for actor in range(count):
                relative = torch.tensor([[10., 20., 30., 40.]])
                physical = physical_seat_values(relative, torch.tensor([actor]), count)
                expected = [relative[0, (seat - actor) % count].item() if seat < count else 0 for seat in range(4)]
                self.assertEqual(physical[0].tolist(), expected)
                restored = relative_seat_values(physical, torch.tensor([actor]), count)
                torch.testing.assert_close(restored[:, :count], relative[:, :count])
                self.assertFalse(restored[:, count:].any())
            values = torch.ones(1, 4, requires_grad=True)
            active_value_loss(values, torch.zeros_like(values), count).backward()
            self.assertTrue((values.grad[:, :count] != 0).all())
            self.assertFalse(values.grad[:, count:].any())

    def test_gae_assigns_future_drinks_to_owner_across_wraparound_pass(self):
        for count in range(1, 5):
            rewards = torch.zeros(2, 1, 4)
            rewards[1, 0, count - 1] = -7
            _, returns = calculate_competitive_gae(rewards, torch.tensor([[False], [True]]),
                torch.zeros(2, 1, 4), torch.full((1, 4), 999.), torch.tensor([[count - 1], [0]]), torch.tensor([0]), 1., 1., count)
            self.assertEqual(returns[0, 0, count - 1].item(), -7)
            self.assertEqual(returns[0].sum().item(), -7)

    def test_same_charges_only_existing_opponents(self):
        for count in range(1, 5):
            env = BatchedWindowEnv(REWARD, 1, 100, torch.device('cpu'), 42, 5, count)
            wanted = (int(env.cards[0, 2, 5]) // 4) * 4
            if wanted == int(env.cards[0, 2, 5]):
                wanted += 1
            old = env.cards[0, 2, 4].clone()
            positions = (env.cards[0] == wanted).nonzero()
            if positions.numel():
                r, c = positions[0]
                env.cards[0, r, c] = old
            else:
                env.deck[0, :env.deck_size[0]][env.deck[0, :env.deck_size[0]] == wanted] = old
            env.cards[0, 2, 4] = wanted
            env._append_current_record()
            env.step(torch.tensor([161]))
            self.assertEqual(env.player_drinks[0].tolist(), [0] + [1] * (count - 1) + [0] * (4 - count))
            self.assertEqual(env.last_player_rewards[0].tolist(), [0] + [-1] * (count - 1) + [0] * (4 - count))

    def test_attention_reaches_older_records_and_private_cards_cannot_change_output(self):
        torch.manual_seed(42)
        env = BatchedWindowEnv(REWARD, 2, 100, torch.device('cpu'), 42, 33, 3)
        for _ in range(35):
            env.step(env.action_mask().long().argmax(1))
        history = env.history_observation().requires_grad_()
        model = WindowPolicyValueNet(32, True, history_attention=True)
        model(history)[0].square().sum().backward()
        self.assertGreater(history.grad[:, 0].abs().sum().item(), 0)
        env.cards[~env.face_up & env.layout] = 35
        env.deck[:] = 0
        env._append_current_record()
        torch.testing.assert_close(model(history)[0], model(env.history_observation())[0])

    def test_invalid_player_groups_are_rejected(self):
        for counts in ([], [0], [5], [1, 1], [True], [1.5]):
            with self.assertRaises(ValueError):
                training_player_counts({'environment': {'player_counts': counts}})

    def test_evaluation_counts_personal_receipts_instead_of_table_penalties(self):
        class ChargesEnvironment:
            def __init__(self, *args):
                self.player_drinks = torch.zeros(2, 4)
                self.last_player_rewards = torch.zeros(2, 4)
            def history_observation(self):
                return torch.zeros(2, 1, HISTORY_FEATURE_SIZE)
            def action_mask(self):
                mask = torch.zeros(2, 301, dtype=torch.bool)
                mask[:, 300] = True
                return mask
            def step(self, actions):
                self.player_drinks[:, 0] += 3
                self.player_drinks[:, 1] += 7
                self.last_player_rewards[:, 0] = -3
                return None, torch.full((2,), -7.), torch.ones(2, dtype=torch.bool), torch.full((2,), 7), torch.ones(2, dtype=torch.bool)
            def reset(self, indices):
                pass
        config = {'reward': REWARD, 'environment': {'max_steps': 1, 'player_count': 2}}
        with patch('train.BatchedWindowEnv', ChargesEnvironment):
            result = evaluate(WindowPolicyValueNet(16), config, 2, 42, torch.device('cpu'))
        self.assertEqual(result['eval_drinks'], 3.)
        self.assertEqual(result['eval_reward'], -3.)
        self.assertEqual(result['completion_rate'], 1.)

    def test_small_training_cycle_and_attention_checkpoint_round_trip(self):
        config = json.loads((Path(__file__).parent / 'configs/training_config.json').read_text())
        config['algorithm'].update(total_timesteps=64, rollout_steps=16, hidden_size=16, minibatch_size=8, update_epochs=1)
        config['initialization_checkpoint'] = 'deliberately-missing-checkpoint.pt'
        config['environment'].update(parallel_environments=4, max_steps=3)
        config['evaluation'].update(episodes_per_seed=2, seeds=[42], every_timesteps=64, max_steps=3)
        config['checkpoint']['save_every_timesteps'] = 64
        with tempfile.TemporaryDirectory() as directory:
            config['output']['base_dir'] = directory
            path = Path(directory) / 'config.json'
            path.write_text(json.dumps(config))
            with contextlib.redirect_stdout(io.StringIO()):
                main(path, 'cpu', False, from_scratch=True)
            checkpoint = next(Path(directory).glob('*/best_window_policy.pt'))
            model, payload = load_checkpoint(checkpoint)
            self.assertIsNotNone(model.history_attention)
            self.assertEqual(payload['training']['player_counts'], [1, 2, 3, 4])
            self.assertEqual(model.history_encoder.input_size, HISTORY_FEATURE_SIZE)
            with checkpoint.with_name('metrics.csv').open() as source:
                rows = list(csv.DictReader(source))
            self.assertEqual([int(r['training_player_count']) for r in rows], [1, 2, 3, 4])
            for count in range(1, 5):
                self.assertTrue(float(rows[-1][f'players_{count}_eval_drinks']) >= 0)

    def test_refinement_loads_weights_and_rejects_incompatible_reward_or_memory(self):
        config = json.loads((Path(__file__).parent / 'configs/training_config.json').read_text())
        config['algorithm']['hidden_size'] = 16
        config['initialization_checkpoint'] = None
        model = WindowPolicyValueNet(16, True, history_attention=True)
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / 'source.pt'
            save_checkpoint(checkpoint, model, config, 123, torch.device('cpu'))
            config['initialization_checkpoint'] = str(checkpoint)
            restored = initialize_model(config, torch.device('cpu'))
            self.assertTrue(restored.training)
            for key, value in model.state_dict().items():
                torch.testing.assert_close(value, restored.state_dict()[key])
            self.assertEqual(config['initialization']['cumulative_timesteps'], 123)
            self.assertFalse(config['initialization']['optimizer_restored'])
            self.assertEqual(len(config['initialization']['sha256']), 64)
            config['environment']['history_length'] = 17
            with self.assertRaisesRegex(ValueError, 'must match'):
                initialize_model(config, torch.device('cpu'))
            config['environment']['history_length'] = 33
            config['algorithm']['reward_scale'] = 1.
            with self.assertRaisesRegex(ValueError, 'must match'):
                initialize_model(config, torch.device('cpu'))

    def test_annealing_reaches_both_endpoints_and_supports_constant_profiles(self):
        self.assertEqual(linear_schedule(.005, .001, 0), .005)
        self.assertAlmostEqual(linear_schedule(.005, .001, 1), .001)
        self.assertAlmostEqual(linear_schedule(.005, .001, .5), .003)
        self.assertEqual(linear_schedule(.01, .01, .5), .01)

    def test_warm_start_baseline_is_preserved_when_updates_are_worse(self):
        config = json.loads((Path(__file__).parent / 'configs/training_config.json').read_text())
        config['algorithm'].update(total_timesteps=64, rollout_steps=16, hidden_size=16, minibatch_size=8, update_epochs=1)
        config['environment'].update(parallel_environments=4, max_steps=3)
        config['evaluation'].update(episodes_per_seed=2, seeds=[42], every_timesteps=64, max_steps=3)
        config['checkpoint']['save_every_timesteps'] = 64
        model = WindowPolicyValueNet(16, True, history_attention=True)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.pt'
            save_checkpoint(source, model, config, 123, torch.device('cpu'))
            config['initialization_checkpoint'] = str(source)
            config['output']['base_dir'] = directory
            path = Path(directory) / 'config.json'
            path.write_text(json.dumps(config))
            # Baseline is deliberately better than subsequent evaluations.
            baseline = {'minimum_completion_rate': 1., 'completion_rate': 1., 'eval_drinks': 1.}
            worse = {'minimum_completion_rate': 1., 'completion_rate': 1., 'eval_drinks': 9., 'eval_reward': -9.}
            with contextlib.redirect_stdout(io.StringIO()), patch('train.evaluate_held_out', side_effect=[baseline, worse]):
                main(path, 'cpu', False)
            best = next(Path(directory).glob('*/best_window_policy.pt'))
            restored, payload = load_checkpoint(best)
            self.assertEqual(payload['training']['timesteps'], 0)
            self.assertEqual(payload['training']['cumulative_timesteps'], 123)
            for key, value in model.state_dict().items():
                torch.testing.assert_close(value, restored.state_dict()[key])
            _, final = load_checkpoint(best.with_name('window_policy.pt'))
            self.assertEqual(final['training']['cumulative_timesteps'], 187)
            self.assertTrue(best.with_name('initial_evaluation.json').is_file())

    def test_training_evaluation_has_a_separate_action_cap(self):
        model = WindowPolicyValueNet(16)
        config = {'seed': 42, 'reward': REWARD,
                  'environment': {'max_steps': 1, 'player_count': 1, 'history_length': 1},
                  'evaluation': {'max_steps': 3, 'episodes_per_seed': 2, 'seeds': [42]}}
        result = evaluate_held_out(model, config, torch.device('cpu'))
        self.assertEqual(result['eval_steps'], 3.)
        self.assertEqual(config['environment']['max_steps'], 1)
