"""Invariant tests for the GPU-resident Window simulator."""

import unittest

import torch

from window_rl.contract import ACTION_SIZE, FEATURE_SIZE
from window_rl.cuda_environment import BatchedWindowEnv


REWARD = {"correct_guess": 1.0, "wrong_drink": -1.0, "pass": 0.0, "complete_game": 25.0}


class BatchedWindowEnvTest(unittest.TestCase):
    def test_cuda_rollout_keeps_valid_card_decks(self) -> None:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        env = BatchedWindowEnv(REWARD, num_envs=32, max_steps=100, device=device, seed=7)
        for _ in range(80):
            observation, mask = env.observation(), env.action_mask()
            self.assertEqual(observation.shape, (32, FEATURE_SIZE))
            self.assertEqual(mask.shape, (32, ACTION_SIZE))
            self.assertTrue(mask.any(dim=1).all())
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
