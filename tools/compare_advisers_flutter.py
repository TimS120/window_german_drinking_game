#!/usr/bin/env python3
"""Build current advisers and compare them in an isolated native Flutter process."""
import argparse
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ('solo', 'head-to-head', 'focal-2', 'focal-3', 'focal-4')


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be positive')
    return number


def fingerprints():
    files = sorted((ROOT / 'app/lib').rglob('*.dart')) + [
        ROOT / 'app/assets/models/window_policy.onnx',
        ROOT / 'app/assets/models/window_policy.metadata.json',
        ROOT / 'app/pubspec.lock', Path(__file__).resolve(),
    ]
    result = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in files}
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                          capture_output=True, text=True, check=False)
    dirty = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT,
                           capture_output=True, text=True, check=False)
    flutter = subprocess.run(['flutter', '--version', '--machine'], cwd=ROOT,
                             capture_output=True, text=True, check=True)
    return {'flutter': json.loads(flutter.stdout),
            'gitCommit': head.stdout.strip(), 'gitStatus': dirty.stdout,
            'sha256': result, 'python': sys.version, 'platform': sys.platform}


def fail_report(output, error, config):
    records = output / 'games.jsonl'
    count = sum(1 for _ in records.open()) if records.exists() else 0
    summary = {'status': 'failed', 'completedGames': count, 'error': str(error),
               'config': config, 'finishedUtc': datetime.now(timezone.utc).isoformat()}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (output / 'report.md').write_text(
        '# Adviser comparison — FAILED\n\nNo winner: the benchmark did not complete.\n\n'
        f'Completed games retained: {count}.\n\nError: {error}\n\nSee run.log.\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deals', type=positive, default=30,
                        help='independent initial deals per scenario (default: 30)')
    parser.add_argument('--seed', type=int, default=20261013)
    parser.add_argument('--scenarios', nargs='+', choices=SCENARIOS, default=['solo', 'head-to-head', 'focal-3', 'focal-4'])
    parser.add_argument('--opponents', nargs='+',
                        choices=('rl', 'statistics', 'casual', 'probability', 'cautious', 'mixed', 'varied'),
                        default=['varied'],
                        help='opponent styles for focal-player comparisons')
    parser.add_argument('--statistics-rounds', type=int, choices=(3, 6, 9, 12), default=12)
    parser.add_argument('--max-actions', type=positive, default=100000,
                        help='abort entire comparison if any game reaches this guard')
    parser.add_argument('--decision-timeout-seconds', type=positive, default=60)
    parser.add_argument('--bootstrap-samples', type=positive, default=2000)
    parser.add_argument('--practical-difference', type=float, default=1,
                        help='meaningful drinks saved per player/game (default: 1)')
    parser.add_argument('--timeout-seconds', type=positive,
                        help='optional whole-run timeout; expiration produces a failed report')
    parser.add_argument('--output', type=Path,
                        help='new output directory; never overwrites an existing directory')
    args = parser.parse_args(argv)
    if not 0 <= args.seed <= 0x7fffffff:
        parser.error('--seed must be between 0 and 2147483647')
    if args.bootstrap_samples < 100:
        parser.error('--bootstrap-samples must be at least 100')
    if not 0 <= args.practical_difference < float('inf'):
        parser.error('--practical-difference must be finite and nonnegative')
    if len(set(args.opponents)) != len(args.opponents):
        parser.error('--opponents cannot contain duplicates')
    if args.opponents == ['mixed'] and not any(s in args.scenarios for s in ('focal-3', 'focal-4')):
        parser.error('mixed opponents require focal-3 or focal-4')
    if len(set(args.scenarios)) != len(args.scenarios):
        parser.error('--scenarios cannot contain duplicates')
    output = (args.output or ROOT / 'benchmark-results' /
              datetime.now(ZoneInfo('Europe/Berlin')).strftime('%Y-%m-%d_%H-%M-%S')).resolve()
    output.mkdir(parents=True, exist_ok=False)
    config = {'deals': args.deals, 'seed': args.seed, 'scenarios': args.scenarios,
              'opponentStyles': args.opponents, 'balanceSeatsAcrossDeals': True, 'statisticsRounds': args.statistics_rounds, 'maxActions': args.max_actions,
              'decisionTimeoutSeconds': args.decision_timeout_seconds,
              'bootstrapSamples': args.bootstrap_samples,
              'practicalDifference': args.practical_difference,
              'outputDirectory': str(output)}
    child = None
    workspace = None
    try:
        if sys.platform != 'linux':
            raise RuntimeError('This launcher requires Linux and Xvfb.')
        missing = [name for name in ('flutter', 'xvfb-run', 'xauth', 'git')
                   if shutil.which(name) is None]
        if missing:
            raise RuntimeError('Missing prerequisite(s): ' + ', '.join(missing) +
                               '. For Xvfb on Ubuntu: sudo apt install xvfb xauth')
        config['provenance'] = fingerprints()
        config_path = output / 'config.json'
        config_path.write_text(json.dumps(config, indent=2) + '\n')
        build_root = ROOT / 'app/build'
        build_root.mkdir(exist_ok=True)
        workspace = tempfile.TemporaryDirectory(prefix='adviser-benchmark-', dir=build_root)
        build_project = Path(workspace.name) / 'app'
        shutil.copytree(ROOT / 'app', build_project, symlinks=True,
                        ignore=shutil.ignore_patterns('build', '.dart_tool', 'ephemeral',
                                                     '.symlinks', '.plugin_symlinks', '.git',
                                                     '.gradle', '.cxx'))
        print(f'Building an isolated snapshot of current code and ONNX model. Output: {output}', flush=True)
        with (output / 'run.log').open('w') as log:
            subprocess.run(['flutter', 'build', 'linux', '--release',
                            '--target=lib/benchmark_main.dart'], cwd=build_project,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            after = fingerprints()
            if after['sha256'] != config['provenance']['sha256']:
                raise RuntimeError('Sources changed during build; rerun on a stable revision.')
            # Launch only in an isolated display; never fall back to the desktop.
            env = dict(os.environ, WINDOW_BENCHMARK_CONFIG=str(config_path),
                       GDK_BACKEND='x11', LIBGL_ALWAYS_SOFTWARE='1')
            env.pop('WAYLAND_DISPLAY', None)
            binary = build_project / 'build/linux/x64/release/bundle/window_game'
            if not binary.is_file():
                binary = build_project / 'build/linux/arm64/release/bundle/window_game'
            command = ['xvfb-run', '-a', '-s', '-screen 0 1920x1080x24',
                       'env', '-u', 'WAYLAND_DISPLAY', str(binary)]
            print('Running full games in the background; progress is in run.log.', flush=True)
            child = subprocess.Popen(command, cwd=binary.parent, env=env,
                                     stdout=log, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            code = child.wait(timeout=args.timeout_seconds)
            if code:
                raise RuntimeError(f'Native benchmark exited with status {code}')
        summary = json.loads((output / 'summary.json').read_text())
        if summary.get('status') != 'complete':
            raise RuntimeError('Native benchmark did not produce a complete result')
        print((output / 'report.md').read_text(), flush=True)
        print(f'Report saved: {output / "report.md"}')
        return 0
    except (Exception, KeyboardInterrupt) as error:
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        # Preserve the native failure report, which has the precise game context.
        native_failed = False
        try:
            native_failed = json.loads((output / 'summary.json').read_text()).get('status') == 'failed'
        except (OSError, ValueError):
            pass
        if not native_failed or not (output / 'report.md').exists():
            fail_report(output, error or 'Interrupted by user', config)
        print(f'Comparison failed. No winner. Read {output / "report.md"}', file=sys.stderr)
        return 1
    finally:
        if workspace is not None:
            workspace.cleanup()


if __name__ == '__main__':
    raise SystemExit(main())
