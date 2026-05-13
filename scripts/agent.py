"""Inference agent for the trained MaskablePPO Window model."""

import os

from sb3_contrib import MaskablePPO

from simulation_env import WindowGameEnv, decode_action_index


class RLAgent:
    def __init__(self, model_path=None):
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        default_model = os.path.join(os.path.dirname(__file__), "models", "maskable_ppo_window.zip")

        if model_path:
            resolved_model = model_path
        elif os.path.exists(default_model):
            resolved_model = default_model
        else:
            outputs_dir = os.path.join(repo_root, "outputs")
            run_dirs = (
                sorted(
                    [
                        os.path.join(outputs_dir, name)
                        for name in os.listdir(outputs_dir)
                        if os.path.isdir(os.path.join(outputs_dir, name))
                    ]
                )
                if os.path.exists(outputs_dir)
                else []
            )
            if not run_dirs:
                raise FileNotFoundError("No model found. Provide model_path or run training first.")
            latest_run = run_dirs[-1]
            resolved_model = os.path.join(latest_run, "latest_model.zip")
            if not os.path.exists(resolved_model):
                raise FileNotFoundError(f"Expected model at {resolved_model}, but it does not exist.")

        self.model_path = resolved_model
        self.model = MaskablePPO.load(self.model_path, device="auto")

    def predict_action(self, env: WindowGameEnv):
        obs = env._build_observation(env._get_state())
        action_masks = env.action_masks()
        action, _ = self.model.predict(obs, action_masks=action_masks, deterministic=True)
        action_index = int(action)
        action_dict = decode_action_index(action_index)
        return action_index, action_dict


if __name__ == "__main__":
    env = WindowGameEnv(observer=False)
    agent = RLAgent()

    obs, _ = env.reset()
    done = False
    while not done:
        action_index, action_dict = agent.predict_action(env)
        _, reward, terminated, truncated, info = env.step(action_index)
        done = terminated or truncated
        print(f"Action={action_index} {action_dict} Reward={reward} Debug={info.get('debug', '')}")

    env.close()
