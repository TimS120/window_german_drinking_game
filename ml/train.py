"""Train the Flutter-compatible policy/value network with masked PPO."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import random
import time

import numpy as np
import torch
from torch import nn

from window_rl.contract import CHECKPOINT_FORMAT
from window_rl.environment import WindowTrainingEnv
from window_rl.model import WindowPolicyValueNet

ROOT = Path(__file__).resolve().parent


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def masked_distribution(
    logits: torch.Tensor, masks: torch.Tensor
) -> torch.distributions.Categorical:
    return torch.distributions.Categorical(
        logits=logits.masked_fill(~masks.bool(), -1e9)
    )


@torch.no_grad()
def evaluate(
    model: WindowPolicyValueNet, config: dict, episodes: int, seed: int
) -> dict:
    model.eval()
    rewards, drinks, completions = [], [], 0
    for episode in range(episodes):
        env = WindowTrainingEnv(
            config["reward"], config["environment"]["max_steps"], seed + episode
        )
        observation, total_reward, done = env.reset(), 0.0, False
        while not done:
            logits, _ = model(torch.from_numpy(observation).unsqueeze(0))
            mask = torch.from_numpy(env.action_mask()).unsqueeze(0)
            action = int(masked_distribution(logits, mask).probs.argmax(1).item())
            observation, reward, done, info = env.step(action)
            total_reward += reward
        rewards.append(total_reward)
        drinks.append(env.drinks)
        completions += int(info.completed)
    model.train()
    return {
        "eval_reward": float(np.mean(rewards)),
        "eval_drinks": float(np.mean(drinks)),
        "completion_rate": completions / episodes,
    }


def save_checkpoint(
    path: Path, model: WindowPolicyValueNet, config: dict, timesteps: int
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(
        {
            "format": CHECKPOINT_FORMAT,
            "hidden_size": config["algorithm"]["hidden_size"],
            "model_state_dict": model.state_dict(),
            "training": {
                "status": "trained",
                "timesteps": timesteps,
                "algorithm": "MaskedPPO",
                "parallel_environments": config["environment"][
                    "parallel_environments"
                ],
            },
        },
        path,
    )


def calculate_gae(
    transitions: list[tuple], bootstrap_value: float, gamma: float, gae_lambda: float
) -> tuple[list[float], list[float]]:
    """Calculate advantages separately for one environment's trajectory."""
    advantages, returns, advantage, next_value = [], [], 0.0, bootstrap_value
    for _, _, _, _, value, reward, done in reversed(transitions):
        delta = reward + gamma * next_value * (1.0 - float(done)) - value
        advantage = delta + gamma * gae_lambda * (1.0 - float(done)) * advantage
        advantages.append(advantage)
        returns.append(advantage + value)
        next_value = value
    return list(reversed(advantages)), list(reversed(returns))


def main(training_path: Path) -> None:
    config = load_json(training_path)
    algo, environment, seed = (
        config["algorithm"],
        config["environment"],
        int(config["seed"]),
    )
    if algo["name"] != "MaskedPPO":
        raise ValueError("Only MaskedPPO is supported.")
    parallel = int(environment["parallel_environments"])
    if parallel < 1:
        raise ValueError("environment.parallel_environments must be at least 1.")
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)

    run_dir = ROOT / config["output"]["base_dir"] / time.strftime("%Y-%m-%d_%H-%M-%S")
    checkpoints = run_dir / "checkpoints"
    checkpoints.mkdir(parents=True)
    (run_dir / "training_config.json").write_text(
        json.dumps(config, indent=2), encoding="utf-8"
    )

    model = WindowPolicyValueNet(hidden_size=algo["hidden_size"])
    optimizer = torch.optim.Adam(model.parameters(), lr=algo["learning_rate"])
    envs = [
        WindowTrainingEnv(config["reward"], environment["max_steps"], seed + index)
        for index in range(parallel)
    ]
    observations = [env.reset() for env in envs]
    timesteps = 0
    next_save = int(config["checkpoint"]["save_every_timesteps"])
    metrics_path = run_dir / "metrics.csv"

    with metrics_path.open("w", newline="", encoding="utf-8") as metrics_file:
        fields = (
            "timesteps",
            "mean_reward",
            "mean_drinks",
            "policy_loss",
            "value_loss",
            "entropy",
            "eval_reward",
            "eval_drinks",
            "completion_rate",
        )
        writer = csv.DictWriter(metrics_file, fieldnames=fields)
        writer.writeheader()
        while timesteps < algo["total_timesteps"]:
            trajectories: list[list[tuple]] = [[] for _ in envs]
            target_steps = min(algo["rollout_steps"], algo["total_timesteps"] - timesteps)
            while sum(len(trajectory) for trajectory in trajectories) < target_steps:
                remaining = target_steps - sum(len(trajectory) for trajectory in trajectories)
                active = min(parallel, remaining)
                batch_observations = np.asarray(observations[:active], dtype=np.float32)
                batch_masks = np.asarray(
                    [env.action_mask() for env in envs[:active]], dtype=np.bool_
                )
                with torch.no_grad():
                    logits, values = model(torch.from_numpy(batch_observations))
                    distribution = masked_distribution(logits, torch.from_numpy(batch_masks))
                    actions = distribution.sample()
                    log_probs = distribution.log_prob(actions)
                for index in range(active):
                    next_observation, reward, done, _ = envs[index].step(
                        int(actions[index].item())
                    )
                    trajectories[index].append(
                        (
                            observations[index],
                            batch_masks[index],
                            int(actions[index].item()),
                            float(log_probs[index].item()),
                            float(values[index].item()),
                            reward,
                            done,
                        )
                    )
                    observations[index] = envs[index].reset() if done else next_observation
                    timesteps += 1

            with torch.no_grad():
                _, bootstrap_values = model(
                    torch.from_numpy(np.asarray(observations, dtype=np.float32))
                )
            rollout, advantages, returns = [], [], []
            for index, trajectory in enumerate(trajectories):
                trajectory_advantages, trajectory_returns = calculate_gae(
                    trajectory,
                    float(bootstrap_values[index].item()),
                    algo["gamma"],
                    algo["gae_lambda"],
                )
                rollout.extend(trajectory)
                advantages.extend(trajectory_advantages)
                returns.extend(trajectory_returns)
            advantages_array = np.asarray(advantages, dtype=np.float32)
            advantages_array = (advantages_array - advantages_array.mean()) / (
                advantages_array.std() + 1e-8
            )
            observations_tensor = torch.tensor(
                np.asarray([item[0] for item in rollout]), dtype=torch.float32
            )
            masks_tensor = torch.tensor(
                np.asarray([item[1] for item in rollout]), dtype=torch.bool
            )
            actions_tensor = torch.tensor([item[2] for item in rollout])
            old_log_probs = torch.tensor([item[3] for item in rollout])
            returns_tensor = torch.tensor(np.asarray(returns, dtype=np.float32))
            advantages_tensor = torch.tensor(advantages_array)
            losses: list[tuple[float, float, float]] = []
            for _ in range(algo["update_epochs"]):
                indices = torch.randperm(len(rollout))
                for start in range(0, len(rollout), algo["minibatch_size"]):
                    index = indices[start : start + algo["minibatch_size"]]
                    logits, values = model(observations_tensor[index])
                    distribution = masked_distribution(logits, masks_tensor[index])
                    ratio = (distribution.log_prob(actions_tensor[index]) - old_log_probs[index]).exp()
                    clipped = ratio.clamp(1 - algo["clip_range"], 1 + algo["clip_range"])
                    policy_loss = -torch.minimum(
                        ratio * advantages_tensor[index],
                        clipped * advantages_tensor[index],
                    ).mean()
                    value_loss = nn.functional.mse_loss(values.squeeze(1), returns_tensor[index])
                    entropy = distribution.entropy().mean()
                    loss = (
                        policy_loss
                        + algo["value_coefficient"] * value_loss
                        - algo["entropy_coefficient"] * entropy
                    )
                    optimizer.zero_grad()
                    loss.backward()
                    nn.utils.clip_grad_norm_(model.parameters(), algo["max_grad_norm"])
                    optimizer.step()
                    losses.append(
                        (float(policy_loss.item()), float(value_loss.item()), float(entropy.item()))
                    )
            evaluation = evaluate(
                model, config, int(config["evaluation"]["episodes"]), seed + timesteps
            )
            row = {
                "timesteps": timesteps,
                "mean_reward": float(np.mean([item[5] for item in rollout])),
                "mean_drinks": float(np.mean([env.drinks for env in envs])),
                "policy_loss": float(np.mean([item[0] for item in losses])),
                "value_loss": float(np.mean([item[1] for item in losses])),
                "entropy": float(np.mean([item[2] for item in losses])),
                **evaluation,
            }
            writer.writerow(row)
            metrics_file.flush()
            print(
                "steps={timesteps} eval_reward={eval_reward:.2f} "
                "eval_drinks={eval_drinks:.2f} completion={completion_rate:.0%}".format(
                    **row
                )
            )
            if timesteps >= next_save:
                save_checkpoint(
                    checkpoints / f"window_policy_{timesteps:09d}.pt",
                    model,
                    config,
                    timesteps,
                )
                next_save += int(config["checkpoint"]["save_every_timesteps"])
    final = run_dir / "window_policy.pt"
    save_checkpoint(final, model, config, timesteps)
    print(f"Training complete: {final}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--training-config",
        type=Path,
        default=ROOT / "configs" / "training_config.json",
    )
    arguments = parser.parse_args()
    main(arguments.training_config)
