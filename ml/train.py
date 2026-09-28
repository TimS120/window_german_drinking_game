"""Train the Flutter-compatible policy/value network with GPU-native PPO."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import time

import numpy as np
import torch
from torch import nn

from plot_training import write_learning_curve
from window_rl.contract import CHECKPOINT_FORMAT, HISTORY_LENGTH, MAX_HISTORY_LENGTH, PLAYER_COUNT
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


def human_duration(seconds: float) -> str:
    total_seconds = max(0, round(seconds))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def write_training_summary(
    path: Path,
    *,
    status: str,
    started_at: str,
    elapsed_seconds: float,
    timesteps: int,
    total_timesteps: int,
    device: torch.device,
    compiled: bool,
) -> None:
    """Persist current status and an easily readable elapsed duration."""
    payload = {
        "status": status,
        "started_at": started_at,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "elapsed_seconds": round(elapsed_seconds, 3),
        "elapsed_human": human_duration(elapsed_seconds),
        "timesteps_completed": timesteps,
        "total_timesteps": total_timesteps,
        "progress": timesteps / total_timesteps if total_timesteps else 0.0,
        "device": str(device),
        "torch_compile": compiled,
        "learning_curve": "learning_curve.svg",
    }
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


@torch.no_grad()
def evaluate(model: WindowPolicyValueNet, config: dict, episodes: int, seed: int, device: torch.device) -> dict:
    model.eval()
    env = BatchedWindowEnv(config["reward"], episodes, config["environment"]["max_steps"], device, seed, int(config["environment"].get("history_length", HISTORY_LENGTH)), int(config["environment"].get("player_count", 4)))
    rewards = torch.zeros(episodes, device=device)
    drinks = torch.zeros(episodes, device=device)
    completed = torch.zeros(episodes, dtype=torch.bool, device=device)
    finished = torch.zeros(episodes, dtype=torch.bool, device=device)
    while not bool(finished.all()):
        logits, _ = model(env.history_observation())
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
    torch.save({"format": CHECKPOINT_FORMAT, "hidden_size": config["algorithm"]["hidden_size"], "model_state_dict": state, "training": {"status": "trained", "timesteps": timesteps, "algorithm": "RecurrentMaskedPPO", "parallel_environments": config["environment"]["parallel_environments"], "player_count": config["environment"].get("player_count", 4), "history_length": config["environment"].get("history_length", HISTORY_LENGTH), "device": str(device)}}, path)


def physical_seat_values(relative_values: torch.Tensor, current_players: torch.Tensor) -> torch.Tensor:
    """Convert relative critic heads to stable physical-seat order.

    The critic's heads are ``current, next, ...`` at every state.  A pass
    changes who is current, so its bootstrap must be rotated before temporal
    differences are calculated for each actual player.
    """
    seats = torch.arange(PLAYER_COUNT, device=relative_values.device)
    relative_indices = (seats - current_players.unsqueeze(-1)) % PLAYER_COUNT
    return relative_values.gather(-1, relative_indices)


def relative_seat_values(physical_values: torch.Tensor, current_players: torch.Tensor) -> torch.Tensor:
    """Express physical-seat targets as ``current, next, ...`` critic heads."""
    relative_seats = torch.arange(PLAYER_COUNT, device=physical_values.device)
    physical_indices = (current_players.unsqueeze(-1) + relative_seats) % PLAYER_COUNT
    return physical_values.gather(-1, physical_indices)


def calculate_competitive_gae(
    player_rewards: torch.Tensor,
    dones: torch.Tensor,
    relative_values: torch.Tensor,
    bootstrap_relative_values: torch.Tensor,
    current_players: torch.Tensor,
    bootstrap_current_players: torch.Tensor,
    gamma: float,
    gae_lambda: float,
) -> tuple[torch.Tensor, torch.Tensor]:
    """GAE for every physical player, including rollouts crossing a pass.

    Rollouts contain only sixteen transitions per environment.  Plain
    Monte-Carlo returns therefore discarded almost all delayed outcomes,
    including completion rewards.  The vector critic supplies a correct
    per-seat bootstrap at the rollout boundary without exposing hidden cards.
    """
    values = physical_seat_values(relative_values, current_players)
    next_values = physical_seat_values(
        bootstrap_relative_values,
        bootstrap_current_players,
    )
    advantages = torch.empty_like(player_rewards)
    advantage = torch.zeros_like(next_values)
    for index in range(player_rewards.shape[0] - 1, -1, -1):
        not_done = (~dones[index]).to(torch.float32).unsqueeze(-1)
        delta = player_rewards[index] + gamma * not_done * next_values - values[index]
        advantage = delta + gamma * gae_lambda * not_done * advantage
        advantages[index] = advantage
        next_values = values[index]
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
    if algo["name"] != "RecurrentMaskedPPO":
        raise ValueError("Only RecurrentMaskedPPO is supported.")
    if parallel < 1 or rollout_steps < parallel or rollout_steps % parallel:
        raise ValueError("rollout_steps must be a positive multiple of environment.parallel_environments.")
    if int(algo["total_timesteps"]) % rollout_steps:
        raise ValueError("total_timesteps must be a multiple of algorithm.rollout_steps.")
    if int(environment.get("player_count", PLAYER_COUNT)) != PLAYER_COUNT:
        raise ValueError(f"environment.player_count is fixed to {PLAYER_COUNT} for this trainer.")
    if not 1 <= int(environment.get("history_length", HISTORY_LENGTH)) <= MAX_HISTORY_LENGTH:
        raise ValueError(f"environment.history_length must be between 1 and {MAX_HISTORY_LENGTH}.")
    evaluation_interval = int(config["evaluation"].get("every_timesteps", rollout_steps))
    checkpoint_interval = int(config["checkpoint"]["save_every_timesteps"])
    if evaluation_interval < rollout_steps or evaluation_interval % rollout_steps:
        raise ValueError("evaluation.every_timesteps must be a multiple of algorithm.rollout_steps.")
    if checkpoint_interval < rollout_steps or checkpoint_interval % rollout_steps:
        raise ValueError("checkpoint.save_every_timesteps must be a multiple of algorithm.rollout_steps.")
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
    initial_learning_rate = float(algo["learning_rate"])
    final_learning_rate = float(algo.get("final_learning_rate", initial_learning_rate))
    optimizer = torch.optim.Adam(model.parameters(), lr=initial_learning_rate)
    env = BatchedWindowEnv(config["reward"], parallel, environment["max_steps"], device, seed, int(environment.get("history_length", HISTORY_LENGTH)), int(environment.get("player_count", 4)))
    timesteps, next_save = 0, checkpoint_interval
    iterations_per_rollout = rollout_steps // parallel
    metrics_path = run_dir / "metrics.csv"
    learning_curve_path = run_dir / "learning_curve.svg"
    summary_path = run_dir / "training_summary.json"
    best_selection = (-1.0, float("-inf"))
    started_at = datetime.now(timezone.utc).isoformat()
    started_clock = time.perf_counter()
    total_timesteps = int(algo["total_timesteps"])
    write_training_summary(
        summary_path,
        status="running",
        started_at=started_at,
        elapsed_seconds=0,
        timesteps=0,
        total_timesteps=total_timesteps,
        device=device,
        compiled=compile_model,
    )

    with metrics_path.open("w", newline="", encoding="utf-8") as metrics_file:
        fields = ("timesteps", "learning_rate", "mean_reward", "mean_drinks", "policy_loss", "value_loss", "entropy", "eval_reward", "eval_drinks", "completion_rate")
        writer = csv.DictWriter(metrics_file, fieldnames=fields)
        writer.writeheader()
        write_learning_curve(metrics_path, learning_curve_path, 0)
        while timesteps < algo["total_timesteps"]:
            progress = timesteps / int(algo["total_timesteps"])
            learning_rate = initial_learning_rate + (final_learning_rate - initial_learning_rate) * progress
            for parameter_group in optimizer.param_groups:
                parameter_group["lr"] = learning_rate
            observations, masks, actions, log_probs, values, rewards, dones, drink_counts, player_rewards, actors = ([] for _ in range(10))
            for _ in range(iterations_per_rollout):
                observation, mask = env.history_observation(), env.action_mask()
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
                values.append(value)
                rewards.append(reward)
                dones.append(done)
                drink_counts.append(drinks)
                player_rewards.append(env.last_player_rewards.clone())
                actors.append(env.last_actors.clone())
                env.reset(done.nonzero(as_tuple=False).squeeze(1))
            with torch.no_grad():
                _, bootstrap_values = model(env.history_observation())
            advantages_by_player, returns_by_player = calculate_competitive_gae(
                torch.stack(player_rewards),
                torch.stack(dones),
                torch.stack(values),
                bootstrap_values,
                torch.stack(actors),
                env.current_player,
                algo["gamma"],
                algo["gae_lambda"],
            )
            batch = torch.arange(parallel, device=device)
            actors_tensor = torch.stack(actors)
            advantages = advantages_by_player[
                torch.arange(iterations_per_rollout, device=device)[:, None],
                batch[None, :],
                actors_tensor,
            ]
            returns = returns_by_player[
                torch.arange(iterations_per_rollout, device=device)[:, None],
                batch[None, :],
                actors_tensor,
            ]
            relative_returns = relative_seat_values(
                returns_by_player,
                actors_tensor,
            )
            advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)
            observations_tensor, masks_tensor = torch.stack(observations).flatten(0, 1), torch.stack(masks).flatten(0, 1)
            actions_tensor, old_log_probs = torch.stack(actions).flatten(), torch.stack(log_probs).flatten()
            returns_tensor, advantages_tensor = returns.flatten(), advantages.flatten()
            relative_returns_tensor = relative_returns.flatten(0, 1)
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
                    value_loss = nn.functional.smooth_l1_loss(
                        value,
                        relative_returns_tensor[index],
                    )
                    entropy = distribution.entropy().mean()
                    loss = policy_loss + algo["value_coefficient"] * value_loss - algo["entropy_coefficient"] * entropy
                    optimizer.zero_grad(set_to_none=True)
                    loss.backward()
                    nn.utils.clip_grad_norm_(model.parameters(), algo["max_grad_norm"])
                    optimizer.step()
                    losses.append((policy_loss.detach(), value_loss.detach(), entropy.detach()))
            timesteps += rollout_steps
            evaluation = {}
            if timesteps % evaluation_interval == 0 or timesteps == int(algo["total_timesteps"]):
                evaluation = evaluate(model, config, int(config["evaluation"]["episodes"]), seed + timesteps, device)
            loss_values = torch.stack([torch.stack(item) for item in losses]).mean(dim=0)
            row = {"timesteps": timesteps, "learning_rate": learning_rate, "mean_reward": scalar(torch.stack(rewards).mean()), "mean_drinks": scalar(torch.stack(drink_counts).float().mean()), "policy_loss": scalar(loss_values[0]), "value_loss": scalar(loss_values[1]), "entropy": scalar(loss_values[2]), **evaluation}
            writer.writerow(row)
            metrics_file.flush()
            elapsed_seconds = time.perf_counter() - started_clock
            write_learning_curve(metrics_path, learning_curve_path, elapsed_seconds)
            write_training_summary(
                summary_path,
                status="running",
                started_at=started_at,
                elapsed_seconds=elapsed_seconds,
                timesteps=timesteps,
                total_timesteps=total_timesteps,
                device=device,
                compiled=compile_model,
            )
            progress = "steps={timesteps} device={device} elapsed={elapsed}".format(
                device=device,
                elapsed=human_duration(elapsed_seconds),
                **row,
            )
            if evaluation:
                progress += " eval_reward={eval_reward:.2f} eval_drinks={eval_drinks:.2f} completion={completion_rate:.0%}".format(**evaluation)
            print(progress)
            if timesteps >= next_save:
                save_checkpoint(checkpoints / f"window_policy_{timesteps:09d}.pt", model, config, timesteps, device)
                next_save += int(config["checkpoint"]["save_every_timesteps"])
            if evaluation:
                # Completion is the first quality gate; among policies that
                # complete equally often, prefer fewer total drinks.
                selection = (evaluation["completion_rate"], -evaluation["eval_drinks"])
                if selection > best_selection:
                    best_selection = selection
                    save_checkpoint(run_dir / "best_window_policy.pt", model, config, timesteps, device)
    final = run_dir / "window_policy.pt"
    save_checkpoint(final, model, config, timesteps, device)
    elapsed_seconds = time.perf_counter() - started_clock
    write_learning_curve(metrics_path, learning_curve_path, elapsed_seconds)
    write_training_summary(
        summary_path,
        status="completed",
        started_at=started_at,
        elapsed_seconds=elapsed_seconds,
        timesteps=timesteps,
        total_timesteps=total_timesteps,
        device=device,
        compiled=compile_model,
    )
    print(f"Training complete: {final} ({human_duration(elapsed_seconds)})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training-config", type=Path, default=ROOT / "configs" / "training_config.json")
    parser.add_argument("--device", default="cuda", choices=("auto", "cpu", "cuda"), help="Training device; CUDA is the default.")
    parser.add_argument("--compile", action="store_true", help="Enable torch.compile after validating a normal run.")
    arguments = parser.parse_args()
    main(arguments.training_config, arguments.device, arguments.compile)
