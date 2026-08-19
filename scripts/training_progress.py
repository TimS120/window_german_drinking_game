"""Game metrics and local CSV/PNG progress reporting for RL training."""

from __future__ import annotations

import csv
import math
import os

from ray.rllib.callbacks.callbacks import RLlibCallback


class WindowGameMetricsCallback(RLlibCallback):
    """Aggregate step-level and completed-episode game metrics."""

    @staticmethod
    def _sub_environment(env, env_index):
        sub_env = env.envs[env_index] if hasattr(env, "envs") else env
        return sub_env.unwrapped

    def on_episode_step(
        self,
        *,
        metrics_logger=None,
        env=None,
        env_index: int,
        **kwargs,
    ):
        if metrics_logger is None or env is None:
            return
        sub_env = self._sub_environment(env, env_index)
        if not hasattr(sub_env, "get_step_metrics"):
            return

        for name, value in sub_env.get_step_metrics().items():
            metrics_logger.log_value(
                key=f"game_step/{name}",
                value=float(value),
                reduce="mean",
                window=1000,
            )

    def on_episode_end(
        self,
        *,
        env_runner=None,
        metrics_logger=None,
        env=None,
        env_index: int,
        **kwargs,
    ):
        if metrics_logger is None or env is None:
            return
        sub_env = self._sub_environment(env, env_index)
        if not hasattr(sub_env, "get_episode_metrics"):
            return

        for name, value in sub_env.get_episode_metrics().items():
            metrics_logger.log_value(
                key=f"game/{name}",
                value=float(value),
                reduce="mean",
                window=100,
            )


def _nested_get(data, *keys):
    current = data
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def _find_metric(data, key):
    if isinstance(data, dict):
        if key in data:
            return data[key]
        for value in data.values():
            found = _find_metric(value, key)
            if found is not None:
                return found
    return None


def _number(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


class LocalProgressWriter:
    """Append metrics to CSV and redraw a local PNG dashboard."""

    FIELDNAMES = [
        "iteration",
        "timesteps",
        "elapsed_seconds",
        "steps_per_second",
        "episodes_lifetime",
        "train_return",
        "eval_return",
        "train_accuracy",
        "eval_accuracy",
        "train_completion_rate",
        "eval_completion_rate",
        "train_truncation_rate",
        "eval_truncation_rate",
        "train_face_up_fraction",
        "eval_face_up_fraction",
        "train_max_face_up_fraction",
        "eval_max_face_up_fraction",
        "train_mean_wrong_penalty",
        "eval_mean_wrong_penalty",
        "train_episode_steps",
        "eval_episode_steps",
        "train_step_reward",
        "train_step_accuracy",
        "train_step_face_up_fraction",
        "policy_loss",
        "value_loss",
        "entropy",
        "explained_variance",
        "total_loss",
        "learning_rate",
    ]

    def __init__(self, run_dir, smoothing_window=10, plot_every_iterations=1):
        self.progress_dir = os.path.join(run_dir, "progress")
        os.makedirs(self.progress_dir, exist_ok=True)
        self.csv_path = os.path.join(self.progress_dir, "metrics.csv")
        self.plot_path = os.path.join(self.progress_dir, "training_progress.png")
        self.smoothing_window = max(1, int(smoothing_window))
        self.plot_every_iterations = max(1, int(plot_every_iterations))
        self.rows = []
        self._last_steps = 0
        self._last_elapsed = 0.0

        with open(self.csv_path, "w", newline="", encoding="utf-8") as csv_file:
            csv.DictWriter(csv_file, fieldnames=self.FIELDNAMES).writeheader()

    @staticmethod
    def _game_metric(section, name):
        return _number(_find_metric(section, f"game/{name}"))

    def record(
        self,
        result,
        iteration,
        timesteps,
        elapsed_seconds,
        evaluation_is_fresh=True,
    ):
        env_results = result.get("env_runners", {})
        evaluation = result.get("evaluation", {}) if evaluation_is_fresh else {}
        learner = _nested_get(result, "learners", "default_policy") or {}
        elapsed_delta = elapsed_seconds - self._last_elapsed
        steps_delta = timesteps - self._last_steps

        row = {
            "iteration": int(iteration),
            "timesteps": int(timesteps),
            "elapsed_seconds": float(elapsed_seconds),
            "steps_per_second": steps_delta / elapsed_delta if elapsed_delta > 0 else None,
            "episodes_lifetime": _number(env_results.get("num_episodes_lifetime")),
            "train_return": _number(env_results.get("episode_return_mean")),
            "eval_return": _number(_find_metric(evaluation, "episode_return_mean")),
            "train_accuracy": self._game_metric(env_results, "accuracy"),
            "eval_accuracy": self._game_metric(evaluation, "accuracy"),
            "train_completion_rate": self._game_metric(env_results, "completion_rate"),
            "eval_completion_rate": self._game_metric(evaluation, "completion_rate"),
            "train_truncation_rate": self._game_metric(env_results, "truncation_rate"),
            "eval_truncation_rate": self._game_metric(evaluation, "truncation_rate"),
            "train_face_up_fraction": self._game_metric(env_results, "face_up_fraction"),
            "eval_face_up_fraction": self._game_metric(evaluation, "face_up_fraction"),
            "train_max_face_up_fraction": self._game_metric(
                env_results, "max_face_up_fraction"
            ),
            "eval_max_face_up_fraction": self._game_metric(
                evaluation, "max_face_up_fraction"
            ),
            "train_mean_wrong_penalty": self._game_metric(
                env_results, "mean_wrong_penalty"
            ),
            "eval_mean_wrong_penalty": self._game_metric(
                evaluation, "mean_wrong_penalty"
            ),
            "train_episode_steps": self._game_metric(env_results, "episode_steps"),
            "eval_episode_steps": self._game_metric(evaluation, "episode_steps"),
            "train_step_reward": _number(
                _find_metric(env_results, "game_step/reward")
            ),
            "train_step_accuracy": _number(
                _find_metric(env_results, "game_step/accuracy")
            ),
            "train_step_face_up_fraction": _number(
                _find_metric(env_results, "game_step/face_up_fraction")
            ),
            "policy_loss": _number(learner.get("policy_loss")),
            "value_loss": _number(learner.get("vf_loss")),
            "entropy": _number(learner.get("entropy")),
            "explained_variance": _number(learner.get("vf_explained_var")),
            "total_loss": _number(learner.get("total_loss")),
            "learning_rate": _number(learner.get("default_optimizer_learning_rate")),
        }
        self.rows.append(row)
        self._last_steps = timesteps
        self._last_elapsed = elapsed_seconds

        with open(self.csv_path, "a", newline="", encoding="utf-8") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=self.FIELDNAMES)
            writer.writerow({key: "" if value is None else value for key, value in row.items()})

        if iteration % self.plot_every_iterations == 0:
            self._draw_dashboard()
        return row

    def _series(self, name):
        return [row[name] for row in self.rows]

    def _smoothed(self, name):
        values = self._series(name)
        smoothed = []
        for index in range(len(values)):
            window = [
                value
                for value in values[max(0, index - self.smoothing_window + 1) : index + 1]
                if value is not None
            ]
            smoothed.append(sum(window) / len(window) if window else None)
        return smoothed

    @staticmethod
    def _plot_if_present(axis, x_values, y_values, label, **kwargs):
        points = [(x, y) for x, y in zip(x_values, y_values) if y is not None]
        if points:
            x, y = zip(*points)
            axis.plot(x, y, label=label, **kwargs)

    def _draw_dashboard(self):
        # Import plotting only in the driver. Ray workers also import this
        # callback module and should not pay Matplotlib's startup cost.
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        steps = self._series("timesteps")
        fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)

        performance = axes[0, 0]
        self._plot_if_present(
            performance, steps, self._smoothed("train_return"), "Training return"
        )
        self._plot_if_present(
            performance, steps, self._series("eval_return"), "Evaluation return", marker="o"
        )
        performance.set_title("Episode return (higher is better)")
        performance.set_ylabel("Return")

        quality = axes[0, 1]
        for metric, label in (
            ("train_step_accuracy", "Recent guess accuracy"),
            ("train_completion_rate", "Completion rate"),
            ("train_truncation_rate", "Truncation rate"),
            ("train_step_face_up_fraction", "Recent face-up fraction"),
        ):
            self._plot_if_present(quality, steps, self._smoothed(metric), label)
        self._plot_if_present(
            quality,
            steps,
            self._series("eval_accuracy"),
            "Evaluation accuracy",
            marker="o",
        )
        self._plot_if_present(
            quality,
            steps,
            self._series("eval_completion_rate"),
            "Evaluation completion",
            marker="o",
        )
        quality.set_ylim(0.0, 1.05)
        quality.set_title("Game quality (rolling mean)")
        quality.set_ylabel("Fraction")

        cost = axes[1, 0]
        self._plot_if_present(
            cost,
            steps,
            self._smoothed("train_mean_wrong_penalty"),
            "Mean wrong penalty",
        )
        self._plot_if_present(
            cost,
            steps,
            self._series("eval_mean_wrong_penalty"),
            "Evaluation wrong penalty",
            marker="o",
        )
        cost.set_title("Cost of mistakes (lower is better)")
        cost.set_ylabel("Cards/drinks per wrong guess")

        learning = axes[1, 1]
        for metric, label in (
            ("policy_loss", "Policy loss"),
            ("value_loss", "Value loss"),
            ("entropy", "Entropy"),
            ("explained_variance", "Value explained variance"),
        ):
            self._plot_if_present(learning, steps, self._smoothed(metric), label)
        learning.set_title("PPO diagnostics")

        for axis in axes.flat:
            axis.set_xlabel("Environment timesteps")
            axis.grid(alpha=0.25)
            if axis.lines:
                axis.legend(loc="best")
        fig.suptitle(f"Window RL training progress — {steps[-1]:,} timesteps")
        fig.savefig(self.plot_path, dpi=150)
        plt.close(fig)
