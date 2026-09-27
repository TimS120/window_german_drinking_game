"""Train the Flutter-compatible policy/value network with GPU-native PPO."""

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
from window_rl.cuda_environment import BatchedWindowEnv
from window_rl.model import WindowPolicyValueNet

ROOT = Path(__file__).resolve().parent


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def masked_distribution(logits: torch.Tensor, masks: torch.Tensor) -> torch.distributions.Categorical:
    return torch.distributions.Categorical(logits=logits.masked_fill(~masks, -1e9))


def scalar(value: torch.Tensor) -> float:
    """Synchronize only at reporting time, never in the rollout hot path."""
    return float(value.detach().cpu())


@torch.no_grad()
def evaluate(model: WindowPolicyValueNet, config: dict, episodes: int, seed: int, device: torch.device) -> dict:
    model.eval()
    env = BatchedWindowEnv(config["reward"], episodes, config["environment"]["max_steps"], device, seed)
    rewards = torch.zeros(episodes, device=device)
    drinks = torch.zeros(episodes, device=device)
    completed = torch.zeros(episodes, dtype=torch.bool, device=device)
    finished = torch.zeros(episodes, dtype=torch.bool, device=device)
    while not bool(finished.all()):
        logits, _ = model(env.observation())
        actions = masked_distribution(logits, env.action_mask()).probs.argmax(dim=1)
        _, reward, done, step_drinks, did_complete = env.step(actions)
        active = ~finished
        rewards += reward * active
        drinks += step_drinks * active
        completed |= did_complete & active
        finished |= done
        # A terminal game can legitimately have no follow-up legal action.
        # Reset it immediately so subsequent batched model calls always see a
        # valid state; ``active`` above ensures its replacement is not counted.
        env.reset(done.nonzero(as_tuple=False).squeeze(1))
    model.train()
    return {"eval_reward": scalar(rewards.mean()), "eval_drinks": scalar(drinks.mean()), "completion_rate": scalar(completed.float().mean())}


def save_checkpoint(path: Path, model: WindowPolicyValueNet, config: dict, timesteps: int, device: torch.device) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # OptimizedModule prefixes state keys with ``_orig_mod.``; export must
    # receive the original deployment model's names.
    deployment_model = getattr(model, "_orig_mod", model)
    state = {name: tensor.detach().cpu() for name, tensor in deployment_model.state_dict().items()}
    torch.save({"format": CHECKPOINT_FORMAT, "hidden_size": config["algorithm"]["hidden_size"], "model_state_dict": state, "training": {"status": "trained", "timesteps": timesteps, "algorithm": "MaskedPPO", "parallel_environments": config["environment"]["parallel_environments"], "device": str(device)}}, path)


def calculate_gae(rewards: torch.Tensor, dones: torch.Tensor, values: torch.Tensor, bootstrap: torch.Tensor, gamma: float, gae_lambda: float) -> tuple[torch.Tensor, torch.Tensor]:
    advantages = torch.empty_like(rewards)
    advantage, next_value = torch.zeros_like(bootstrap), bootstrap
    for index in range(rewards.shape[0] - 1, -1, -1):
        not_done = (~dones[index]).float()
        delta = rewards[index] + gamma * next_value * not_done - values[index]
        advantage = delta + gamma * gae_lambda * not_done * advantage
        advantages[index] = advantage
        next_value = values[index]
    return advantages, advantages + values


def select_device(requested: str) -> torch.device:
    if requested == "auto":
        requested = "cuda" if torch.cuda.is_available() else "cpu"
    device = torch.device(requested)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but no CUDA-enabled PyTorch device is available.")
    return device


def main(training_path: Path, requested_device: str, compile_model: bool) -> None:
    config = load_json(training_path)
    algo, environment, seed = config["algorithm"], config["environment"], int(config["seed"])
    parallel, rollout_steps = int(environment["parallel_environments"]), int(algo["rollout_steps"])
    if algo["name"] != "MaskedPPO":
        raise ValueError("Only MaskedPPO is supported.")
    if parallel < 1 or rollout_steps < parallel or rollout_steps % parallel:
        raise ValueError("rollout_steps must be a positive multiple of environment.parallel_environments.")
    if int(algo["total_timesteps"]) % parallel:
        raise ValueError("total_timesteps must be a multiple of environment.parallel_environments.")
    device = select_device(requested_device)
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(seed)
        torch.set_float32_matmul_precision("high")

    run_dir = ROOT / config["output"]["base_dir"] / time.strftime("%Y-%m-%d_%H-%M-%S")
    checkpoints = run_dir / "checkpoints"
    checkpoints.mkdir(parents=True)
    (run_dir / "training_config.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
    model: WindowPolicyValueNet = WindowPolicyValueNet(hidden_size=algo["hidden_size"]).to(device)
    if compile_model:
        model = torch.compile(model)  # type: ignore[assignment]
    optimizer = torch.optim.Adam(model.parameters(), lr=algo["learning_rate"])
    env = BatchedWindowEnv(config["reward"], parallel, environment["max_steps"], device, seed)
    timesteps, next_save = 0, int(config["checkpoint"]["save_every_timesteps"])
    iterations_per_rollout = rollout_steps // parallel
    metrics_path = run_dir / "metrics.csv"

    with metrics_path.open("w", newline="", encoding="utf-8") as metrics_file:
        fields = ("timesteps", "mean_reward", "mean_drinks", "policy_loss", "value_loss", "entropy", "eval_reward", "eval_drinks", "completion_rate")
        writer = csv.DictWriter(metrics_file, fieldnames=fields)
        writer.writeheader()
        while timesteps < algo["total_timesteps"]:
            observations, masks, actions, log_probs, values, rewards, dones, drink_counts = ([] for _ in range(8))
            for _ in range(iterations_per_rollout):
                observation, mask = env.observation(), env.action_mask()
                with torch.no_grad():
                    logits, value = model(observation)
                    distribution = masked_distribution(logits, mask)
                    action, log_prob = distribution.sample(), None
                    log_prob = distribution.log_prob(action)
                _, reward, done, drinks, _ = env.step(action)
                observations.append(observation)
                masks.append(mask)
                actions.append(action)
                log_probs.append(log_prob)
                values.append(value.squeeze(1))
                rewards.append(reward)
                dones.append(done)
                drink_counts.append(drinks)
                env.reset(done.nonzero(as_tuple=False).squeeze(1))
            with torch.no_grad():
                _, bootstrap = model(env.observation())
            advantages, returns = calculate_gae(torch.stack(rewards), torch.stack(dones), torch.stack(values), bootstrap.squeeze(1), algo["gamma"], algo["gae_lambda"])
            advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)
            observations_tensor, masks_tensor = torch.stack(observations).flatten(0, 1), torch.stack(masks).flatten(0, 1)
            actions_tensor, old_log_probs = torch.stack(actions).flatten(), torch.stack(log_probs).flatten()
            returns_tensor, advantages_tensor = returns.flatten(), advantages.flatten()
            losses: list[tuple[torch.Tensor, torch.Tensor, torch.Tensor]] = []
            for _ in range(algo["update_epochs"]):
                indices = torch.randperm(rollout_steps, device=device)
                for start in range(0, rollout_steps, algo["minibatch_size"]):
                    index = indices[start : start + algo["minibatch_size"]]
                    logits, value = model(observations_tensor[index])
                    distribution = masked_distribution(logits, masks_tensor[index])
                    ratio = (distribution.log_prob(actions_tensor[index]) - old_log_probs[index]).exp()
                    clipped = ratio.clamp(1 - algo["clip_range"], 1 + algo["clip_range"])
                    policy_loss = -torch.minimum(ratio * advantages_tensor[index], clipped * advantages_tensor[index]).mean()
                    value_loss, entropy = nn.functional.mse_loss(value.squeeze(1), returns_tensor[index]), distribution.entropy().mean()
                    loss = policy_loss + algo["value_coefficient"] * value_loss - algo["entropy_coefficient"] * entropy
                    optimizer.zero_grad(set_to_none=True)
                    loss.backward()
                    nn.utils.clip_grad_norm_(model.parameters(), algo["max_grad_norm"])
                    optimizer.step()
                    losses.append((policy_loss.detach(), value_loss.detach(), entropy.detach()))
            timesteps += rollout_steps
            evaluation = evaluate(model, config, int(config["evaluation"]["episodes"]), seed + timesteps, device)
            loss_values = torch.stack([torch.stack(item) for item in losses]).mean(dim=0)
            row = {"timesteps": timesteps, "mean_reward": scalar(torch.stack(rewards).mean()), "mean_drinks": scalar(torch.stack(drink_counts).float().mean()), "policy_loss": scalar(loss_values[0]), "value_loss": scalar(loss_values[1]), "entropy": scalar(loss_values[2]), **evaluation}
            writer.writerow(row)
            metrics_file.flush()
            print("steps={timesteps} device={device} eval_reward={eval_reward:.2f} eval_drinks={eval_drinks:.2f} completion={completion_rate:.0%}".format(device=device, **row))
            if timesteps >= next_save:
                save_checkpoint(checkpoints / f"window_policy_{timesteps:09d}.pt", model, config, timesteps, device)
                next_save += int(config["checkpoint"]["save_every_timesteps"])
    final = run_dir / "window_policy.pt"
    save_checkpoint(final, model, config, timesteps, device)
    print(f"Training complete: {final}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training-config", type=Path, default=ROOT / "configs" / "training_config.json")
    parser.add_argument("--device", default="cuda", choices=("auto", "cpu", "cuda"), help="Training device; CUDA is the default.")
    parser.add_argument("--compile", action="store_true", help="Enable torch.compile after validating a normal run.")
    arguments = parser.parse_args()
    main(arguments.training_config, arguments.device, arguments.compile)
