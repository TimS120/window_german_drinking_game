"""History report integrity and preflight limits; no desktop launches."""
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('history', Path(__file__).resolve().parents[1] / 'tools/compare_statistics_history.py')
history = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(history)


class HistoryComparisonTests(unittest.TestCase):
    def test_invalid_lengths_and_oversized_runs_stop_before_launch(self):
        for args in [['--lengths', '-1', '16'], ['--lengths', '16', '33'],
                     ['--deals', '11'], ['--lengths', '0', '4'], ['--workers', '0']]:
            with self.subTest(args=args), mock.patch.object(history.subprocess, 'Popen') as launch, \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                history.main(args)
            launch.assert_not_called()

    def test_summary_uses_matched_deals_and_card_weighted_scores(self):
        games = []
        for length, drinks in [(0, [14, 26]), (16, [10, 20]), (32, [9, 18])]:
            for seed, value in enumerate(drinks):
                games.append({'players': 2, 'historyLength': length, 'seed': seed,
                    'drinks': value, 'decisions': 2, 'micros': 4000,
                    'beliefMicros': 2000, 'fallbacks': int(length == 32)})
        probes = [dict(historyLength=0, cards=1, brierSum=1, logLossSum=2,
                       fallback=False, beliefMicros=1000),
                  dict(historyLength=0, cards=3, brierSum=0, logLossSum=0,
                       fallback=False, beliefMicros=3000)]
        result = history.summarize(games, probes, [0, 16, 32])
        self.assertEqual(result['prediction'][0]['brier'], .25)
        self.assertEqual(result['prediction'][0]['logLoss'], .5)
        rows = {r['historyLength']: r for r in result['gameplay']}
        self.assertEqual(rows[16]['differenceFrom16'], 0)
        self.assertEqual(rows[16]['difference95'], [0, 0])
        self.assertEqual(rows[0]['differenceFrom16'], 5)
        self.assertEqual(rows[32]['differenceFrom16'], -1.5)
        self.assertEqual(rows[32]['fallbackRate'], .5)
        self.assertEqual(rows[32]['decisionMs'], 2)
        self.assertEqual(rows[32]['beliefMs'], 1)

    def test_cached_snapshot_manifest_includes_library_parts(self):
        import re
        for name in history.CORE:
            source = (history.ROOT / 'app/lib' / name).read_text()
            for part in re.findall(r"part '([^']+)';", source):
                self.assertIn(part, history.CORE)


if __name__ == '__main__':
    unittest.main()
