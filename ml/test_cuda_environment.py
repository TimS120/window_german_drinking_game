"""Invariant tests for the GPU-resident Window simulator."""

import unittest

import torch

from window_rl.contract import ACTION_SIZE, ACTION_FEATURE_SIZE, BOARD_FEATURE_SIZE, FEATURE_SIZE, HISTORY_FEATURE_SIZE, HISTORY_LENGTH, OUTCOME_FEATURE_SIZE, PASS_ACTION_INDEX
from window_rl.cuda_environment import BatchedWindowEnv
from train import calculate_competitive_gae, physical_seat_values, relative_seat_values


REWARD = {"correct_guess": 1.0, "wrong_drink": -1.0, "pass": 0.0, "complete_game": 25.0}


class BatchedWindowEnvTest(unittest.TestCase):
    def test_configurable_history_window_remains_on_device(self) -> None:
        env = BatchedWindowEnv(
            REWARD,
            num_envs=2,
            max_steps=100,
            device=torch.device("cuda" if torch.cuda.is_available() else "cpu"),
            seed=13,
            history_length=32,
        )
        self.assertEqual(env.history_observation().shape, (2, 32, HISTORY_FEATURE_SIZE))
        self.assertEqual(env.history_observation().device.type, env.device.type)

    def test_competitive_gae_rotates_values_across_a_pass(self) -> None:
        # At t=1, player one receives a drink caused by player zero's action.
        # The pass means head three at t=1 is player zero's physical critic.
        player_rewards = torch.tensor([
            [[0.0, 0.0, 0.0, 0.0]],
            [[0.0, -1.0, 0.0, 0.0]],
        ])
        current_players = torch.tensor([[0], [1]])
        dones = torch.tensor([[False], [True]])
        relative_values = torch.tensor([
            [[10.0, 11.0, 12.0, 13.0]],
            [[20.0, 21.0, 22.0, 23.0]],
        ])
        physical_values = physical_seat_values(relative_values, current_players)
        self.assertEqual(physical_values.tolist(), [[[10.0, 11.0, 12.0, 13.0]], [[23.0, 20.0, 21.0, 22.0]]])
        self.assertTrue(torch.equal(relative_seat_values(physical_values, current_players), relative_values))
        advantages, returns = calculate_competitive_gae(
            player_rewards,
            dones,
            torch.zeros_like(relative_values),
            torch.zeros((1, 4)),
            current_players,
            torch.tensor([1]),
            gamma=1.0,
            gae_lambda=1.0,
        )
        self.assertEqual(advantages[:, 0].tolist(), [[0.0, -1.0, 0.0, 0.0], [0.0, -1.0, 0.0, 0.0]])
        self.assertTrue(torch.equal(returns, advantages))

    def test_pass_is_recorded_in_history_and_rotates_the_shared_policy_seat(self) -> None:
        env = BatchedWindowEnv(REWARD, num_envs=2, max_steps=100, device=torch.device("cpu"), seed=11)
        env.turn_can_end[:] = True

        env.step(torch.full((2,), PASS_ACTION_INDEX, dtype=torch.long))

        event = env.history_observation()[:, -2]
        self.assertTrue(torch.equal(env.current_player, torch.ones(2, dtype=torch.long)))
        self.assertTrue(torch.equal(env.last_actors, torch.zeros(2, dtype=torch.long)))
        self.assertTrue((event[:, BOARD_FEATURE_SIZE] == 1).all())
        self.assertTrue((event[:, BOARD_FEATURE_SIZE + 1 : BOARD_FEATURE_SIZE + ACTION_FEATURE_SIZE] == 0).all())
        outcome_start = BOARD_FEATURE_SIZE + ACTION_FEATURE_SIZE
        self.assertTrue((event[:, outcome_start + 2] == 1).all())
        self.assertTrue((event[:, outcome_start : outcome_start + OUTCOME_FEATURE_SIZE - 1] == 0).all())

    def test_cuda_rollout_keeps_valid_card_decks(self) -> None:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        env = BatchedWindowEnv(REWARD, num_envs=32, max_steps=100, device=device, seed=7)
        for _ in range(80):
            observation, mask = env.observation(), env.action_mask()
            self.assertEqual(observation.shape, (32, FEATURE_SIZE))
            self.assertEqual(
                env.history_observation().shape,
                (32, HISTORY_LENGTH, HISTORY_FEATURE_SIZE),
            )
            self.assertEqual(mask.shape, (32, ACTION_SIZE))
            self.assertTrue(mask.any(dim=1).all())
            self.assertTrue((env.player_drinks >= 0).all())
            # A uniformly selected legal action avoids coupling this simulator
            # test to policy-network initialization.
            actions = torch.multinomial(mask.float(), 1).squeeze(1)
            _, _, done, _, _ = env.step(actions)
            env.reset(done.nonzero(as_tuple=False).squeeze(1))
            for index in range(env.num_envs):
                cards = env.cards[index][env.cards[index] >= 0]
                deck = env.deck[index, : env.deck_size[index]]
                self.assertTrue(torch.equal(torch.sort(torch.cat((cards, deck))).values, torch.arange(36, device=device)))


if __name__ == "__main__":
    unittest.main()
