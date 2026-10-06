"""Active-seat critic and numerical reward-unit regressions."""
import unittest

import torch
from torch import nn

from export_onnx import DeploymentPolicy
from train import active_value_loss, calculate_competitive_gae, critic_explained_variance, evaluate
from window_rl.model import WindowPolicyValueNet


class TrainingScaleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def test_solo_value_loss_ignores_unused_heads_and_their_gradients(self):
        values = torch.tensor([[2., 999., -999., 999.]], requires_grad=True)
        targets = torch.tensor([[0., -999., 999., -999.]])
        loss = active_value_loss(values, targets, 1)
        torch.testing.assert_close(loss, nn.functional.smooth_l1_loss(values[:, :1], targets[:, :1]))
        loss.backward()
        self.assertNotEqual(float(values.grad[0, 0]), 0.)
        self.assertEqual(values.grad[0, 1:].tolist(), [0., 0., 0.])

    def test_multiplayer_still_trains_every_seat(self):
        values = torch.ones(3, 4, requires_grad=True)
        targets = torch.zeros_like(values)
        loss = active_value_loss(values, targets, 4)
        torch.testing.assert_close(loss, nn.functional.smooth_l1_loss(values, targets))
        loss.backward()
        self.assertTrue((values.grad > 0).all())

    def test_positive_reward_scaling_preserves_gae_and_normalized_advantages(self):
        generator = torch.Generator().manual_seed(26)
        rewards = torch.randn(4, 2, 4, generator=generator)
        values = torch.randn(4, 2, 4, generator=generator)
        bootstrap = torch.randn(2, 4, generator=generator)
        actors = torch.tensor([[0, 0], [0, 1], [1, 1], [1, 2]])
        dones = torch.tensor([[False, False], [False, True], [False, False], [True, False]])
        next_actors = torch.tensor([0, 2])
        a, r = calculate_competitive_gae(rewards, dones, values, bootstrap, actors, next_actors, .999, .95)
        scaled_a, scaled_r = calculate_competitive_gae(rewards * .01, dones, values * .01, bootstrap * .01, actors, next_actors, .999, .95)
        torch.testing.assert_close(scaled_a, a * .01)
        torch.testing.assert_close(scaled_r, r * .01)
        torch.testing.assert_close((a-a.mean())/a.std(), (scaled_a-scaled_a.mean())/scaled_a.std())

    def test_export_restores_value_units_without_changing_policy(self):
        model = WindowPolicyValueNet(32, local_action_head=True).eval()
        history = torch.randn(2, 16, 130)
        logits, values = model(history)
        exported_logits, exported_value = DeploymentPolicy(model, .01)(history)
        torch.testing.assert_close(exported_logits, logits)
        torch.testing.assert_close(exported_value, values[:, :1] * 100)
        torch.testing.assert_close(DeploymentPolicy(model)(history)[1], values[:, :1])

    def test_explained_variance_handles_perfect_constant_and_poor_predictions(self):
        targets = torch.tensor([1., 2., 3.])
        self.assertEqual(float(critic_explained_variance(targets, targets)), 1.)
        self.assertEqual(float(critic_explained_variance(torch.zeros(3), targets)), 0.)
        self.assertLess(float(critic_explained_variance(-targets, targets)), 0.)
        self.assertTrue(torch.isnan(critic_explained_variance(torch.zeros(3), torch.ones(3))))

    def test_evaluation_preserves_original_model_mode(self):
        model = WindowPolicyValueNet(32)
        config = {'reward': {'correct_guess': 0, 'wrong_drink': -1, 'pass': 0, 'complete_game': 0},
                  'environment': {'max_steps': 1, 'history_length': 16, 'player_count': 1}}
        for training in (True, False):
            model.train(training)
            result = evaluate(model, config, 2, 42, torch.device('cpu'))
            self.assertEqual(model.training, training)
            self.assertIn('eval_drinks', result)
            self.assertEqual(result['eval_steps'], 1.)
            self.assertEqual(result['eval_pass_rate'], 0.)


if __name__ == '__main__':
    unittest.main()
