"""Create a self-contained SVG learning curve from a training ``metrics.csv``.

The trainer calls this after every rollout.  Keeping the renderer in the
standard library avoids a plotting dependency in the CUDA training workflow
and makes the resulting chart easy to inspect in a browser or IDE preview.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from xml.sax.saxutils import escape


WIDTH = 1280
HEIGHT = 1170
LEFT = 90
RIGHT = 40
PANEL_HEIGHT = 170
PANEL_GAP = 30


def _number(value: str | None) -> float | None:
    try:
        result = float(value or "")
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def read_metrics(path: Path) -> list[dict[str, float | None]]:
    """Read numeric CSV fields while preserving missing evaluation points."""
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as file:
        return [
            {key: _number(value) for key, value in row.items()}
            for row in csv.DictReader(file)
        ]


def _moving_average(points: list[tuple[float, float]], window: int = 12) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    values: list[float] = []
    for x, value in points:
        values.append(value)
        if len(values) > window:
            values.pop(0)
        result.append((x, sum(values) / len(values)))
    return result


def _format(value: float) -> str:
    if abs(value) >= 100:
        return f"{value:.0f}"
    if abs(value) >= 10:
        return f"{value:.1f}"
    return f"{value:.2f}"


def _polyline(points: list[tuple[float, float]], color: str, width: float, opacity: float = 1.0) -> str:
    if not points:
        return ""
    encoded = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
    return f'<polyline fill="none" stroke="{color}" stroke-width="{width}" stroke-opacity="{opacity}" points="{encoded}" />'


def _panel(
    top: int,
    title: str,
    series: list[tuple[str, str, list[tuple[float, float]], float]],
    x_max: float,
    fixed_range: tuple[float, float] | None = None,
) -> str:
    plot_left, plot_right = LEFT, WIDTH - RIGHT
    plot_top, plot_bottom = top + 35, top + PANEL_HEIGHT
    all_values = [value for _, _, points, _ in series for _, value in points]
    if fixed_range is not None:
        y_min, y_max = fixed_range
    elif not all_values:
        y_min, y_max = 0.0, 1.0
    else:
        y_min, y_max = min(all_values), max(all_values)
        if y_min == y_max:
            margin = max(abs(y_min) * 0.1, 1.0)
        else:
            margin = (y_max - y_min) * 0.08
        y_min -= margin
        y_max += margin

    def x_position(value: float) -> float:
        return plot_left + (plot_right - plot_left) * value / max(x_max, 1.0)

    def y_position(value: float) -> float:
        return plot_bottom - (plot_bottom - plot_top) * (value - y_min) / (y_max - y_min)

    fragments = [
        f'<text x="{plot_left}" y="{top + 18}" class="title">{escape(title)}</text>',
        f'<rect x="{plot_left}" y="{plot_top}" width="{plot_right - plot_left}" height="{plot_bottom - plot_top}" class="plot" />',
    ]
    for step in range(5):
        ratio = step / 4
        y = plot_bottom - ratio * (plot_bottom - plot_top)
        value = y_min + ratio * (y_max - y_min)
        fragments.append(f'<line x1="{plot_left}" y1="{y:.2f}" x2="{plot_right}" y2="{y:.2f}" class="grid" />')
        fragments.append(f'<text x="{plot_left - 10}" y="{y + 4:.2f}" text-anchor="end" class="axis">{_format(value)}</text>')
    for step in range(5):
        ratio = step / 4
        x = plot_left + ratio * (plot_right - plot_left)
        value = ratio * x_max
        fragments.append(f'<text x="{x:.2f}" y="{plot_bottom + 20}" text-anchor="middle" class="axis">{value:.1f}M</text>')
    for index, (label, color, points, width) in enumerate(series):
        screen_points = [(x_position(x), y_position(y)) for x, y in points]
        fragments.append(_polyline(screen_points, color, width, 0.28 if width < 2 else 1.0))
        legend_x = plot_right - 220 + index * 110
        fragments.append(f'<line x1="{legend_x}" y1="{top + 14}" x2="{legend_x + 18}" y2="{top + 14}" stroke="{color}" stroke-width="3" />')
        fragments.append(f'<text x="{legend_x + 24}" y="{top + 18}" class="legend">{escape(label)}</text>')
    return "\n".join(fragments)


def write_learning_curve(metrics_path: Path, output_path: Path, elapsed_seconds: float | None = None) -> None:
    """Write a chart atomically enough for repeated live updates."""
    rows = read_metrics(metrics_path)
    x_values = [row["timesteps"] / 1_000_000 for row in rows if row.get("timesteps") is not None]
    x_max = max(x_values, default=1.0)

    def points(field: str, scale: float = 1.0) -> list[tuple[float, float]]:
        return [
            (float(row["timesteps"]) / 1_000_000, float(row[field]) * scale)
            for row in rows
            if row.get("timesteps") is not None and row.get(field) is not None
        ]

    training_drinks = points("mean_drinks")
    evaluation_drinks = points("eval_drinks")
    completion = points("completion_rate", 100.0)
    entropy = points("entropy")
    approximate_kl = points("approx_kl")
    elapsed = "still running" if elapsed_seconds is None else f"elapsed {elapsed_seconds / 60:.1f} min"
    body = [
        _panel(
            100,
            "Rollout drinks per action — lower is better",
            [
                ("raw", "#93c5fd", training_drinks, 1.0),
                ("12-rollout mean", "#1d4ed8", _moving_average(training_drinks), 3.0),
            ],
            x_max,
        ),
        _panel(
            100 + PANEL_HEIGHT + PANEL_GAP,
            "Held-out evaluation drinks per game — lower is better",
            [("evaluation", "#dc2626", evaluation_drinks, 3.0)],
            x_max,
        ),
        _panel(
            100 + 2 * (PANEL_HEIGHT + PANEL_GAP),
            "Held-out completion rate — higher is better",
            [("completion", "#059669", completion, 3.0)],
            x_max,
            fixed_range=(0.0, 100.0),
        ),
        _panel(
            100 + 3 * (PANEL_HEIGHT + PANEL_GAP),
            "Policy entropy — exploration diagnostic",
            [("entropy", "#d97706", entropy, 3.0)],
            x_max,
        ),
        _panel(
            100 + 4 * (PANEL_HEIGHT + PANEL_GAP),
            "PPO approximate KL — update stability diagnostic",
            [("KL", "#7c3aed", approximate_kl, 3.0)],
            x_max,
        ),
    ]
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
<style>
  .background {{ fill: #ffffff; }} .plot {{ fill: #f8fafc; stroke: #cbd5e1; }}
  .grid {{ stroke: #e2e8f0; stroke-width: 1; }} .title {{ font: 600 15px sans-serif; fill: #0f172a; }}
  .axis {{ font: 12px sans-serif; fill: #475569; }} .legend {{ font: 12px sans-serif; fill: #334155; }}
</style>
<rect width="100%" height="100%" class="background" />
<text x="{LEFT}" y="38" style="font: 700 25px sans-serif; fill: #0f172a">Window RL learning curve</text>
<text x="{LEFT}" y="63" style="font: 14px sans-serif; fill: #475569">{len(rows)} rollout metrics · {escape(elapsed)} · horizontal axis: environment transitions (millions)</text>
{''.join(body)}
</svg>'''
    temporary = output_path.with_suffix(".svg.tmp")
    temporary.write_text(svg, encoding="utf-8")
    temporary.replace(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metrics", type=Path)
    parser.add_argument("--output", type=Path, default=Path("learning_curve.svg"))
    arguments = parser.parse_args()
    write_learning_curve(arguments.metrics, arguments.output)


if __name__ == "__main__":
    main()
