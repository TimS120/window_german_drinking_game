#!/usr/bin/env python3
"""Compare exact shared Dart advisers/rules using cached CLI builds and parallel games."""
import argparse
from collections import deque
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time
import venv

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ('solo', 'head-to-head', 'focal-2', 'focal-3', 'focal-4')
CORE = ['game_engine.dart', 'policy_core.dart', 'statistics_advisor.dart', 'advisor_benchmark.dart']


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be positive')
    return number


def fingerprints():
    files = [ROOT / 'app/lib' / name for name in CORE] + [
        ROOT / 'app/bin/benchmark_cli.dart', ROOT / 'tools/benchmark_onnx.py',
        ROOT / 'tools/benchmark_requirements.txt', Path(__file__).resolve(),
        ROOT / 'app/assets/models/window_policy.onnx',
        ROOT / 'app/assets/models/window_policy.metadata.json',
    ]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True, check=False)
    dirty = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True, check=False)
    sdk = subprocess.run(['dart', '--version'], capture_output=True, text=True, check=True)
    return {'gitCommit': head.stdout.strip(), 'gitStatus': dirty.stdout, 'sha256': hashes,
            'dart': sdk.stdout.strip(), 'python': sys.version, 'platform': sys.platform}


def prepare_runtime(provenance, log):
    cache = ROOT / 'benchmark-cache'
    cache.mkdir(exist_ok=True)
    python = cache / 'venv/bin/python'
    if not python.exists():
        print('Installing the isolated ONNX benchmark runtime (first run only).', flush=True)
        venv.EnvBuilder(with_pip=True).create(cache / 'venv')
    probe = subprocess.run([str(python), '-c', 'import onnxruntime, numpy; assert onnxruntime.__version__ == "1.31.0" and numpy.__version__ == "2.5.4"'], stdout=log, stderr=log)
    if probe.returncode:
        subprocess.run([str(python), '-m', 'pip', 'install', '-r', str(ROOT / 'tools/benchmark_requirements.txt')],
                       stdout=log, stderr=log, check=True)
    source_hashes = {name: value for name, value in provenance['sha256'].items()
                     if not name.endswith(('.onnx', '.metadata.json'))}
    digest = hashlib.sha256(json.dumps([source_hashes, provenance['dart']], sort_keys=True).encode()).hexdigest()[:24]
    snapshot = cache / digest
    binary = snapshot / 'benchmark'
    if not binary.exists():
        print('Compiling the shared Dart rules/advisers (cached for subsequent runs).', flush=True)
        (snapshot / 'lib').mkdir(parents=True, exist_ok=True)
        (snapshot / 'bin').mkdir(exist_ok=True)
        for name in CORE:
            shutil.copyfile(ROOT / 'app/lib' / name, snapshot / 'lib' / name)
        shutil.copyfile(ROOT / 'app/bin/benchmark_cli.dart', snapshot / 'bin/benchmark_cli.dart')
        shutil.copyfile(ROOT / 'tools/benchmark_onnx.py', snapshot / 'benchmark_onnx.py')
        temporary_binary = snapshot / 'benchmark.tmp'
        subprocess.run(['dart', 'compile', 'exe', 'bin/benchmark_cli.dart', '-o', str(temporary_binary)],
                       cwd=snapshot, stdout=log, stderr=log, check=True)
        temporary_binary.replace(binary)
    # Model snapshots are separate, so new weights do not require Dart compilation.
    model_hash = provenance['sha256']['app/assets/models/window_policy.onnx']
    metadata_hash = provenance['sha256']['app/assets/models/window_policy.metadata.json']
    model_dir = cache / ('model-' + model_hash[:20] + '-' + metadata_hash[:12])
    model_dir.mkdir(exist_ok=True)
    for name in ('window_policy.onnx', 'window_policy.metadata.json'):
        target = model_dir / name
        expected_hash = provenance['sha256']['app/assets/models/' + name]
        if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != expected_hash:
            temporary_model = target.with_suffix(target.suffix + '.tmp')
            shutil.copyfile(ROOT / 'app/assets/models' / name, temporary_model)
            temporary_model.replace(target)
    if fingerprints()['sha256'] != provenance['sha256']:
        raise RuntimeError('Sources changed during preparation; rerun on a stable revision.')
    return {'python': str(python), 'onnxWorker': str(snapshot / 'benchmark_onnx.py'),
            'modelPath': str(model_dir / 'window_policy.onnx'),
            'metadataPath': str(model_dir / 'window_policy.metadata.json')}, binary


def stop_workers(processes):
    # Kill the process group, including each worker's persistent Python child.
    for process in processes:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for process in processes:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    for process in processes:
        for pipe in (process.stdin, process.stdout, process.stderr):
            if pipe is not None and not pipe.closed:
                try:
                    pipe.close()
                except OSError:
                    pass


def run_parallel(binary, config_path, jobs, config, log, records):
    pending = deque(jobs)
    workers = []
    selector = selectors.DefaultSelector()
    completed = 0
    done = 0
    runtime = None
    started = time.monotonic()
    try:
        for _ in range(min(config['workers'], len(jobs))):
            process = subprocess.Popen([str(binary), '--worker', str(config_path)], cwd=ROOT,
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
            state = {'process': process, 'buffers': {'out': b'', 'err': b''},
                     'last': time.monotonic(), 'finished': False, 'job': None}
            workers.append(state)
            selector.register(process.stdout, selectors.EVENT_READ, (state, 'out'))
            selector.register(process.stderr, selectors.EVENT_READ, (state, 'err'))
        while done < len(jobs):
            now = time.monotonic()
            if config.get('timeoutSeconds') and now - started > config['timeoutSeconds']:
                raise TimeoutError('Whole-run timeout expired')
            for state in workers:
                if state['finished']:
                    continue
                if now - state['last'] > config['decisionTimeoutSeconds'] + 5:
                    raise TimeoutError(f"Worker stopped responding during {state['job']}")
            for key, _ in selector.select(timeout=0.25):
                state, channel = key.data
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    if channel == 'out' and not state['finished']:
                        raise RuntimeError(f"Worker output closed during {state['job']}; see run.log")
                    continue
                state['last'] = time.monotonic()
                buffer = state['buffers'][channel] + data
                lines = buffer.split(b'\n')
                state['buffers'][channel] = lines.pop()
                for line in lines:
                    if not line:
                        continue
                    if channel == 'err':
                        log.write(line.decode(errors='replace') + '\n')
                        log.flush()
                        continue
                    message = json.loads(line)
                    kind = message.get('type')
                    if kind == 'game':
                        game = message['game']
                        if game.get('completed') is not True:
                            raise RuntimeError('Worker returned an unfinished game; no truncated score')
                        records.write(json.dumps(game, separators=(',', ':')) + '\n')
                        records.flush()
                        completed += 1
                        progress = (f"Completed {completed}: {game['scenario']}, deal {game['deal'] + 1}/"
                                    f"{config['deals']}, seat {game['seat'] + 1}, {game['method']} "
                                    f"({game['actions']} actions)")
                        print(progress, flush=True)
                        log.write(progress + '\n')
                        log.flush()
                    elif kind == 'heartbeat':
                        state['progress'] = message.get('progress')
                    elif kind == 'error':
                        log.write(json.dumps(message) + '\n')
                        log.flush()
                        raise RuntimeError(f"{message.get('context')}: {message['error']}; "
                                           f"progress={message.get('progress')}")
                    elif kind in ('ready', 'done'):
                        if kind == 'ready':
                            runtime = message['runtime']
                        else:
                            done += 1
                        if pending:
                            job = pending.popleft()
                            state['job'] = job
                            state['process'].stdin.write((json.dumps(job) + '\n').encode())
                            state['process'].stdin.flush()
                        else:
                            state['finished'] = True
                            state['process'].stdin.close()
                    else:
                        raise RuntimeError(f'Unknown worker response: {message}')
        return completed, runtime
    finally:
        selector.close()
        stop_workers([state['process'] for state in workers])


def fail_report(output, error, config):
    records = output / 'games.jsonl'
    count = sum(1 for line in records.open() if line.strip()) if records.exists() else 0
    detail = str(error) or type(error).__name__
    summary = {'status': 'failed', 'completedGames': count, 'error': detail,
               'config': config, 'finishedUtc': datetime.now(timezone.utc).isoformat()}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (output / 'report.md').write_text('# Adviser comparison — FAILED\n\n'
        'No winner: the benchmark did not complete.\n\n'
        f'Completed games retained: {count}.\n\nError: {detail}\n\nSee run.log.\n')


MAXIMUM_GAMES = 250


def checked_game_count(scenarios, deals):
    expected = sum(s['gamesPerDeal'] for s in scenarios) * deals
    if expected > MAXIMUM_GAMES:
        raise ValueError(f'Selected comparison needs {expected} games; maximum is {MAXIMUM_GAMES}. '
                         'Reduce --deals or select fewer scenarios/opponents.')
    return expected


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deals', type=positive, default=30)
    parser.add_argument('--seed', type=int, default=20261013)
    parser.add_argument('--scenarios', nargs='+', choices=SCENARIOS, default=['solo', 'head-to-head', 'focal-3', 'focal-4'])
    parser.add_argument('--opponents', nargs='+', choices=('rl', 'statistics', 'casual', 'probability', 'cautious', 'mixed', 'varied'),
                        default=['varied'])
    parser.add_argument('--workers', type=positive, default=max(1, min(8, (os.cpu_count() or 2) - 1)),
                        help='parallel independent game workers; default leaves one CPU core free')
    parser.add_argument('--statistics-rounds', type=int, choices=(3, 6, 9, 12), default=12)
    parser.add_argument('--max-actions', type=positive, default=100000)
    parser.add_argument('--decision-timeout-seconds', type=positive, default=60)
    parser.add_argument('--bootstrap-samples', type=positive, default=2000)
    parser.add_argument('--practical-difference', type=float, default=1)
    parser.add_argument('--timeout-seconds', type=positive)
    parser.add_argument('--output', type=Path, help='new directory; existing results are never overwritten')
    args = parser.parse_args(argv)
    if not 0 <= args.seed <= 0x7fffffff or args.bootstrap_samples < 100:
        parser.error('Invalid seed or bootstrap sample count')
    if not 0 <= args.practical_difference < float('inf'):
        parser.error('--practical-difference must be finite and nonnegative')
    if len(set(args.scenarios)) != len(args.scenarios) or len(set(args.opponents)) != len(args.opponents):
        parser.error('Duplicate scenario/opponent selections')
    output = (args.output or ROOT / 'benchmark-results' / datetime.now(ZoneInfo('Europe/Berlin')).strftime('%Y-%m-%d_%H-%M-%S')).resolve()
    output.mkdir(parents=True, exist_ok=False)
    config = {'deals': args.deals, 'seed': args.seed, 'scenarios': args.scenarios,
              'opponentStyles': args.opponents, 'balanceSeatsAcrossDeals': True, 'workers': args.workers,
              'statisticsRounds': args.statistics_rounds, 'maxActions': args.max_actions,
              'decisionTimeoutSeconds': args.decision_timeout_seconds,
              'bootstrapSamples': args.bootstrap_samples, 'practicalDifference': args.practical_difference,
              'timeoutSeconds': args.timeout_seconds, 'outputDirectory': str(output)}
    try:
        if sys.platform != 'linux':
            raise RuntimeError('This launcher currently supports Linux; no display is required.')
        missing = [name for name in ('dart', 'git') if shutil.which(name) is None]
        if missing:
            raise RuntimeError('Missing prerequisite(s): ' + ', '.join(missing))
        config['provenance'] = fingerprints()
        with (output / 'run.log').open('w') as log:
            runtime, binary = prepare_runtime(config['provenance'], log)
            config.update(runtime)
            config_path = output / 'config.json'
            config_path.write_text(json.dumps(config, indent=2) + '\n')
            plan = subprocess.run([str(binary), '--plan', str(config_path)], capture_output=True,
                                  text=True, check=True)
            scenarios = json.loads(plan.stdout)['scenarios']
            if not scenarios:
                raise ValueError('No scenarios match this opponent selection')
            jobs = [{'scenario': s['name'], 'deal': d} for d in range(args.deals) for s in scenarios]
            expected = checked_game_count(scenarios, args.deals)
            print(f'Running {expected} complete games in {min(args.workers, len(jobs))} '
                  f'headless workers. Report: {output / "report.md"}', flush=True)
            started = time.monotonic()
            config['startedUtc'] = datetime.now(timezone.utc).isoformat()
            with (output / 'games.jsonl').open('w') as records:
                count, ort = run_parallel(binary, config_path, jobs, config, log, records)
            if count != expected:
                raise RuntimeError(f'Expected {expected} games, got {count}; no partial ranking')
            config['elapsedSeconds'] = time.monotonic() - started
            config['execution'] = {'backend': 'native Dart CLI + persistent ONNX CPU',
                                   'workers': min(args.workers, len(jobs)), 'runtime': ort}
            config_path.write_text(json.dumps(config, indent=2) + '\n')
            subprocess.run([str(binary), '--summarize', str(config_path)], stdout=log, stderr=log, check=True)
        print((output / 'report.md').read_text(), flush=True)
        return 0
    except (Exception, KeyboardInterrupt) as error:
        fail_report(output, error, config)
        print(f'Comparison failed. No winner. Read {output / "report.md"}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
