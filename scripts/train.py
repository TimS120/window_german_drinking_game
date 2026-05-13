"""Train MaskablePPO on WindowGameEnv using split training/simulation config files."""

import json
import os
from datetime import datetime

import torch.nn as nn
from sb3_contrib import MaskablePPO
from sb3_contrib.common.maskable.callbacks import MaskableEvalCallback
from stable_baselines3.common.callbacks import CallbackList, CheckpointCallback
from stable_baselines3.common.env_util import make_vec_env
from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv

from simulation_env import WindowGameEnv


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_TRAINING_CONFIG_PATH = os.path.join(REPO_ROOT, "configs", "training_config.json")
DEFAULT_SIMULATION_CONFIG_PATH = os.path.join(REPO_ROOT, "configs", "simulation_config.json")


def _load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def _activation_fn(name: str):
    mapping = {
        "ReLU": nn.ReLU,
        "Tanh": nn.Tanh,
        "ELU": nn.ELU,
        "LeakyReLU": nn.LeakyReLU,
    }
    if name not in mapping:
        raise ValueError(f"Unsupported activation_fn '{name}'. Supported: {sorted(mapping)}")
    return mapping[name]


def _env_factory(sim_cfg: dict, reward_cfg: dict):
    def _make_env():
        return WindowGameEnv(
            players=sim_cfg["players"],
            observer=sim_cfg["observer"],
            max_steps=sim_cfg["max_steps"],
            reward_config=reward_cfg,
        )

    return _make_env


def _make_run_dir(base_dir: str) -> str:
    run_name = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    run_dir = os.path.join(base_dir, run_name)
    os.makedirs(run_dir, exist_ok=False)
    return run_dir


def main(
    training_config_path: str = DEFAULT_TRAINING_CONFIG_PATH,
    simulation_config_path: str = DEFAULT_SIMULATION_CONFIG_PATH,
):
    train_cfg = _load_json(training_config_path)
    sim_cfg = _load_json(simulation_config_path)

    algo_cfg = train_cfg["algorithm"]
    reward_cfg = train_cfg["reward"]
    eval_cfg = train_cfg["evaluation"]
    ckpt_cfg = train_cfg["checkpoint"]

    if algo_cfg["name"] != "MaskablePPO":
        raise ValueError("Only 'MaskablePPO' is currently supported in this training script.")

    output_base_dir = os.path.join(REPO_ROOT, train_cfg["output"]["base_dir"])
    run_dir = _make_run_dir(output_base_dir)
    checkpoints_dir = os.path.join(run_dir, "checkpoints")
    tensorboard_dir = os.path.join(run_dir, "tensorboard")
    best_model_dir = os.path.join(run_dir, "best_model")

    os.makedirs(checkpoints_dir, exist_ok=True)
    os.makedirs(tensorboard_dir, exist_ok=True)
    os.makedirs(best_model_dir, exist_ok=True)

    with open(os.path.join(run_dir, "training_config.json"), "w", encoding="utf-8") as f:
        f.write(json.dumps(train_cfg, indent=2))
    with open(os.path.join(run_dir, "simulation_config.json"), "w", encoding="utf-8") as f:
        f.write(json.dumps(sim_cfg, indent=2))

    vec_env_cls = SubprocVecEnv if sim_cfg.get("vec_env", "subproc") == "subproc" else DummyVecEnv

    train_env = make_vec_env(
        _env_factory(sim_cfg, reward_cfg),
        n_envs=sim_cfg["n_envs"],
        seed=train_cfg["seed"],
        vec_env_cls=vec_env_cls,
    )

    eval_env = make_vec_env(
        _env_factory(sim_cfg, reward_cfg),
        n_envs=1,
        seed=train_cfg["seed"] + 1,
        vec_env_cls=DummyVecEnv,
    )

    hidden_layers = algo_cfg["hidden_layers"]
    policy_kwargs = {
        "activation_fn": _activation_fn(algo_cfg.get("activation_fn", "ReLU")),
        "net_arch": {
            "pi": hidden_layers,
            "vf": hidden_layers,
        },
    }

    model = MaskablePPO(
        policy=algo_cfg["policy"],
        env=train_env,
        learning_rate=algo_cfg["learning_rate"],
        n_steps=algo_cfg["n_steps"],
        batch_size=algo_cfg["batch_size"],
        n_epochs=algo_cfg["n_epochs"],
        gamma=algo_cfg["gamma"],
        gae_lambda=algo_cfg["gae_lambda"],
        clip_range=algo_cfg["clip_range"],
        ent_coef=algo_cfg["ent_coef"],
        vf_coef=algo_cfg["vf_coef"],
        max_grad_norm=algo_cfg["max_grad_norm"],
        target_kl=algo_cfg.get("target_kl"),
        tensorboard_log=tensorboard_dir,
        policy_kwargs=policy_kwargs,
        seed=train_cfg["seed"],
        verbose=1,
        device=algo_cfg.get("device", "auto"),
    )

    callbacks = [
        CheckpointCallback(
            save_freq=max(1, ckpt_cfg["save_freq"] // sim_cfg["n_envs"]),
            save_path=checkpoints_dir,
            name_prefix="checkpoint",
        )
    ]

    if eval_cfg.get("enabled", True):
        callbacks.append(
            MaskableEvalCallback(
                eval_env,
                best_model_save_path=best_model_dir,
                log_path=run_dir,
                eval_freq=max(1, eval_cfg["eval_freq"] // sim_cfg["n_envs"]),
                n_eval_episodes=eval_cfg["n_eval_episodes"],
                deterministic=eval_cfg["deterministic"],
                warn=False,
            )
        )

    model.learn(
        total_timesteps=algo_cfg["total_timesteps"],
        callback=CallbackList(callbacks),
        tb_log_name="training",
        use_masking=True,
        progress_bar=True,
    )

    latest_model_path = os.path.join(run_dir, "latest_model.zip")
    model.save(latest_model_path)

    print(f"Training complete. Output directory: {run_dir}")
    print(f"Latest model: {latest_model_path}")
    print(f"Best model directory: {best_model_dir}")

    train_env.close()
    eval_env.close()


if __name__ == "__main__":
    main()
