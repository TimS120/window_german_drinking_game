"""Headless scheduler and error handling; fixtures launch no desktop applications."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('compare_advisers', Path(__file__).with_name('compare_advisers.py'))
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)

WORKER = '''#!/usr/bin/env python3
import json, sys
print(json.dumps({'type':'ready','runtime':{'fixture':True}}),flush=True)
for line in sys.stdin:
 job=json.loads(line)
 if job['scenario']=='error':
  print(json.dumps({'type':'error','error':'fixture failure','context':'fixture context'}),flush=True)
  sys.exit(1)
 game={'scenario':job['scenario'],'deal':job['deal'],'seat':0,'method':'rl','actions':1,'completed':True}
 print(json.dumps({'type':'game','game':game}),flush=True)
 print(json.dumps({'type':'done','job':job}),flush=True)
'''


class LauncherTests(unittest.TestCase):
    def test_default_plan_is_240_games_and_oversized_plan_is_rejected(self):
        plan = [{'gamesPerDeal': 2} for _ in range(4)]
        self.assertEqual(launcher.checked_game_count(plan, 30), 240)
        self.assertEqual(launcher.checked_game_count(plan, 31), 248)
        with self.assertRaisesRegex(ValueError, 'maximum is 250'):
            launcher.checked_game_count(plan, 32)


    def config(self):
        return {'workers': 2, 'decisionTimeoutSeconds': 5, 'deals': 3}

    def fixture(self, directory):
        path = Path(directory) / 'worker'
        path.write_text(WORKER)
        path.chmod(0o755)
        return path

    def test_missing_cli_prerequisite_is_a_failed_report_without_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'result'
            with mock.patch.object(launcher.shutil, 'which', return_value=None), \
                    mock.patch.object(launcher.subprocess, 'Popen') as launch, \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = launcher.main(['--output', str(output)])
            self.assertEqual(code, 1)
            launch.assert_not_called()
            self.assertEqual(json.loads((output / 'summary.json').read_text())['status'], 'failed')
            self.assertIn('No winner', (output / 'report.md').read_text())

    def test_parallel_scheduler_completes_each_deal_once(self):
        with tempfile.TemporaryDirectory() as directory:
            jobs = [{'scenario': 'fixture', 'deal': d} for d in range(3)]
            records, log = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()):
                count, runtime = launcher.run_parallel(self.fixture(directory), Path(directory) / 'config.json',
                                                      jobs, self.config(), log, records)
            self.assertEqual(count, 3)
            self.assertEqual(runtime, {'fixture': True})
            games = [json.loads(line) for line in records.getvalue().splitlines()]
            self.assertEqual(sorted(g['deal'] for g in games), [0, 1, 2])

    def test_worker_failure_stops_whole_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, 'fixture failure'), \
                    contextlib.redirect_stdout(io.StringIO()):
                launcher.run_parallel(self.fixture(directory), Path(directory) / 'config.json',
                                      [{'scenario': 'error', 'deal': 0}], self.config(),
                                      io.StringIO(), io.StringIO())

    def test_interruption_terminates_worker_process_groups(self):
        with tempfile.TemporaryDirectory() as directory:
            processes = []
            actual_start = launcher.subprocess.Popen
            def start(*args, **kwargs):
                self.assertTrue(kwargs['start_new_session'])
                self.assertNotIn('xvfb-run', args[0])
                process = actual_start(*args, **kwargs)
                processes.append(process)
                return process
            with mock.patch.object(launcher.subprocess, 'Popen', side_effect=start), \
                    mock.patch.object(launcher.selectors.BaseSelector, 'select', side_effect=KeyboardInterrupt):
                # Concrete selector subclasses override BaseSelector.select.
                with mock.patch('selectors.EpollSelector.select', side_effect=KeyboardInterrupt), \
                        self.assertRaises(KeyboardInterrupt):
                    launcher.run_parallel(self.fixture(directory), Path(directory) / 'config.json',
                                          [{'scenario': 'fixture', 'deal': 0}], self.config(),
                                          io.StringIO(), io.StringIO())
            self.assertTrue(processes)
            self.assertTrue(all(p.poll() is not None for p in processes))

    def test_keyboard_interrupt_has_a_nonempty_failure_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            launcher.fail_report(output, KeyboardInterrupt(), {})
            self.assertEqual(json.loads((output / 'summary.json').read_text())['error'], 'KeyboardInterrupt')


if __name__ == '__main__':
    unittest.main()
