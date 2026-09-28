"""Tests for the dependency-free live learning-curve renderer."""

import tempfile
import unittest
from pathlib import Path

from plot_training import read_metrics, write_learning_curve


class LearningCurveTest(unittest.TestCase):
    def test_writes_svg_with_missing_evaluation_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metrics = root / "metrics.csv"
            metrics.write_text(
                "timesteps,mean_drinks,entropy,eval_drinks,completion_rate\n"
                "65536,1.5,2.4,,\n"
                "131072,1.2,2.1,700,0.5\n",
                encoding="utf-8",
            )
            output = root / "learning_curve.svg"

            write_learning_curve(metrics, output, elapsed_seconds=123)

            self.assertEqual(len(read_metrics(metrics)), 2)
            chart = output.read_text(encoding="utf-8")
            self.assertIn("Window RL learning curve", chart)
            self.assertIn("Held-out completion rate", chart)
            self.assertIn("elapsed 2.0 min", chart)


if __name__ == "__main__":
    unittest.main()
