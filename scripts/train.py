"""Train recurrent PPO with hard action masking on WindowGameEnv."""

from __future__ import annotations

import json
import math
import os
import sys
import time
from datetime import datetime

# Use package-qualified module names before Ray serializes environment/module
# classes for worker processes. This also supports `python scripts/train.py`.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
python_path_entries = os.environ.get("PYTHONPATH", "").split(os.pathsep)
if REPO_ROOT not in python_path_entries:
    os.environ["PYTHONPATH"] = os.pathsep.join(
        [REPO_ROOT, *[entry for entry in python_path_entries if entry]]
    )

import ray
from ray.rllib.algorithms.ppo import PPOConfig
from ray.rllib.core.rl_module.default_model_config import DefaultModelConfig
from ray.rllib.core.rl_module.rl_module import RLModuleSpec
from ray.rllib.utils.metrics import NUM_ENV_STEPS_SAMPLED_LIFETIME

from scripts.recurrent_masked_module import RecurrentActionMaskingTorchRLModule
from scripts.simulation_env import WindowGameEnv
from scripts.training_progress import LocalProgressWriter, WindowGameMetricsCallback


DEFAULT_TRAINING_CONFIG_PATH = os.path.join(REPO_ROOT, "configs", "training_config.json")
DEFAULT_SIMULATION_CONFIG_PATH = os.path.join(REPO_ROOT, "configs", "simulation_config.json")


def _load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8-sig") as config_file:
        return json.load(config_file)


def _make_run_dir(base_dir: str) -> str:
    run_name = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    run_dir = os.path.join(base_dir, run_name)
    os.makedirs(run_dir, exist_ok=False)
    return run_dir


def build_ppo_config(train_cfg: dict, sim_cfg: dict) -> PPOConfig:
    """Construct the RLlib config without starting Ray or training."""
    algo_cfg = train_cfg["algorithm"]
    if algo_cfg["name"] != "RecurrentMaskedPPO":
        raise ValueError("Only 'RecurrentMaskedPPO' is supported.")
    if algo_cfg["minibatch_size"] < algo_cfg["max_seq_len"]:
        raise ValueError("minibatch_size must be at least max_seq_len for recurrent PPO.")

    env_config = {
        "players": sim_cfg["players"],
        "observer": sim_cfg.get("observer", False),
        "max_steps": sim_cfg["max_steps"],
        "reward_config": train_cfg["reward"],
    }
    model_config = DefaultModelConfig(
        fcnet_hiddens=algo_cfg["encoder_hidden_layers"],
        fcnet_activation=algo_cfg.get("activation_fn", "relu").lower(),
        head_fcnet_hiddens=algo_cfg["head_hidden_layers"],
        head_fcnet_activation=algo_cfg.get("activation_fn", "relu").lower(),
        use_lstm=True,
        max_seq_len=algo_cfg["max_seq_len"],
        lstm_cell_size=algo_cfg["lstm_cell_size"],
        lstm_use_prev_action=False,
        lstm_use_prev_reward=False,
        vf_share_layers=True,
    )

    config = (
        PPOConfig()
        .framework("torch")
        .environment(WindowGameEnv, env_config=env_config)
        .env_runners(
            num_env_runners=sim_cfg.get("num_env_runners", 0),
            num_envs_per_env_runner=sim_cfg.get("num_envs_per_env_runner", 1),
            rollout_fragment_length=algo_cfg["rollout_fragment_length"],
            batch_mode="truncate_episodes",
        )
        .learners(
            num_learners=0,
            num_gpus_per_learner=algo_cfg.get("num_gpus", 0),
        )
        .training(
            lr=algo_cfg["learning_rate"],
            gamma=algo_cfg["gamma"],
            lambda_=algo_cfg["gae_lambda"],
            clip_param=algo_cfg["clip_range"],
            entropy_coeff=algo_cfg["ent_coeff"],
            vf_loss_coeff=algo_cfg["vf_coeff"],
            grad_clip=algo_cfg["max_grad_norm"],
            use_kl_loss=False,
            kl_coeff=algo_cfg.get("kl_coeff", 0.0),
            train_batch_size_per_learner=algo_cfg["train_batch_size"],
            minibatch_size=algo_cfg["minibatch_size"],
            num_epochs=algo_cfg["num_epochs"],
        )
        .rl_module(
            rl_module_spec=RLModuleSpec(
                module_class=RecurrentActionMaskingTorchRLModule,
                model_config=model_config,
            )
        )
        .callbacks(WindowGameMetricsCallback)
        .debugging(seed=train_cfg["seed"])
    )

    eval_cfg = train_cfg["evaluation"]
    if eval_cfg.get("enabled", True):
        evaluation_interval = max(
            1,
            math.ceil(eval_cfg["eval_freq"] / float(algo_cfg["train_batch_size"])),
        )
        config = config.evaluation(
            evaluation_interval=evaluation_interval,
            evaluation_duration=eval_cfg["n_eval_episodes"],
            evaluation_duration_unit="episodes",
            evaluation_num_env_runners=eval_cfg.get("num_env_runners", 0),
            evaluation_config={"explore": not eval_cfg["deterministic"]},
        )

    return config


def _find_metric(data, key):
    if isinstance(data, dict):
        if key in data:
            return data[key]
        for value in data.values():
            found = _find_metric(value, key)
            if found is not None:
                return found
    return None


def _format_metric(value):
    """Format absent and non-finite RLlib metrics without printing `nan`."""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return "N/A"
    return f"{number:.4f}" if math.isfinite(number) else "N/A"


def main(
    training_config_path: str = DEFAULT_TRAINING_CONFIG_PATH,
    simulation_config_path: str = DEFAULT_SIMULATION_CONFIG_PATH,
):
    train_cfg = _load_json(training_config_path)
    sim_cfg = _load_json(simulation_config_path)
    algo_cfg = train_cfg["algorithm"]
    checkpoint_cfg = train_cfg["checkpoint"]
    progress_cfg = train_cfg.get("progress", {})

    output_base_dir = os.path.join(REPO_ROOT, train_cfg["output"]["base_dir"])
    os.makedirs(output_base_dir, exist_ok=True)
    run_dir = _make_run_dir(output_base_dir)
    checkpoints_dir = os.path.join(run_dir, "checkpoints")
    best_modules_dir = os.path.join(run_dir, "best_modules")
    os.makedirs(checkpoints_dir, exist_ok=True)
    os.makedirs(best_modules_dir, exist_ok=True)

    for filename, contents in (
        ("training_config.json", train_cfg),
        ("simulation_config.json", sim_cfg),
    ):
        with open(os.path.join(run_dir, filename), "w", encoding="utf-8") as output:
            json.dump(contents, output, indent=2)

    ray.init(
        include_dashboard=False,
        ignore_reinit_error=True,
        num_cpus=sim_cfg.get("ray_num_cpus"),
    )
    algorithm = None
    progress_writer = None
    sampled_steps = 0
    next_checkpoint = checkpoint_cfg["save_freq"]
    best_evaluation_return = -math.inf
    total_timesteps = algo_cfg["total_timesteps"]
    eval_cfg = train_cfg["evaluation"]
    evaluation_interval = None
    if eval_cfg.get("enabled", True):
        evaluation_interval = max(
            1,
            math.ceil(eval_cfg["eval_freq"] / float(algo_cfg["train_batch_size"])),
        )
    if total_timesteps < algo_cfg["train_batch_size"]:
        print(
            "Note: total_timesteps is smaller than train_batch_size; RLlib will "
            f"still collect one full batch of {algo_cfg['train_batch_size']} steps."
        )

    try:
        algorithm = build_ppo_config(train_cfg, sim_cfg).build_algo()
        if progress_cfg.get("enabled", True):
            progress_writer = LocalProgressWriter(
                run_dir,
                smoothing_window=progress_cfg.get("smoothing_window", 10),
                plot_every_iterations=progress_cfg.get("plot_every_iterations", 1),
            )
            print(f"Progress CSV: {progress_writer.csv_path}")
            print(f"Progress plot: {progress_writer.plot_path}")

        started_at = time.perf_counter()
        iteration = 0
        while sampled_steps < total_timesteps:
            iteration += 1
            result = algorithm.train()
            sampled_steps = int(
                result.get(
                    NUM_ENV_STEPS_SAMPLED_LIFETIME,
                    sampled_steps + algo_cfg["train_batch_size"],
                )
            )
            evaluation_is_fresh = bool(
                evaluation_interval is not None
                and iteration % evaluation_interval == 0
            )
            progress_row = None
            if progress_writer is not None:
                progress_row = progress_writer.record(
                    result=result,
                    iteration=iteration,
                    timesteps=sampled_steps,
                    elapsed_seconds=time.perf_counter() - started_at,
                    evaluation_is_fresh=evaluation_is_fresh,
                )
            train_return = (
                progress_row["train_return"]
                if progress_row is not None
                else _find_metric(result.get("env_runners", {}), "episode_return_mean")
            )
            print(
                f"Iteration {iteration} | steps {sampled_steps}/{total_timesteps} | "
                f"return {_format_metric(train_return)} | "
                f"recent accuracy "
                f"{_format_metric(progress_row['train_step_accuracy'] if progress_row else None)} | "
                f"recent face-up "
                f"{_format_metric(progress_row['train_step_face_up_fraction'] if progress_row else None)}"
            )

            evaluation = result.get("evaluation") if evaluation_is_fresh else None
            if evaluation:
                evaluation_return = _find_metric(evaluation, "episode_return_mean")
                if evaluation_return is not None and evaluation_return > best_evaluation_return:
                    best_evaluation_return = float(evaluation_return)
                    best_path = os.path.join(
                        best_modules_dir, f"module_{sampled_steps:09d}"
                    )
                    algorithm.get_module().save_to_path(best_path)

            if sampled_steps >= next_checkpoint:
                checkpoint_path = os.path.join(
                    checkpoints_dir, f"checkpoint_{sampled_steps:09d}"
                )
                algorithm.save_to_path(checkpoint_path)
                while next_checkpoint <= sampled_steps:
                    next_checkpoint += checkpoint_cfg["save_freq"]

        final_checkpoint = algorithm.save_to_path(
            os.path.join(run_dir, "checkpoint_final")
        )
        final_module = algorithm.get_module().save_to_path(
            os.path.join(run_dir, "module_final")
        )
        print(f"Training complete. Output directory: {run_dir}")
        print(f"Resume checkpoint: {final_checkpoint}")
        print(f"Inference module: {final_module}")
    except KeyboardInterrupt:
        print("Training interrupted; saving the latest available state...")
        if algorithm is not None:
            interrupted_checkpoint = algorithm.save_to_path(
                os.path.join(
                    checkpoints_dir,
                    f"checkpoint_interrupted_{sampled_steps:09d}",
                )
            )
            interrupted_module = algorithm.get_module().save_to_path(
                os.path.join(
                    run_dir,
                    f"module_interrupted_{sampled_steps:09d}",
                )
            )
            print(f"Resume checkpoint: {interrupted_checkpoint}")
            print(f"Inference module: {interrupted_module}")
    finally:
        if algorithm is not None:
            algorithm.stop()
        ray.shutdown()


if __name__ == "__main__":
    main()
