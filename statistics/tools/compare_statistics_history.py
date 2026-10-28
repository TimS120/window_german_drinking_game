#!/usr/bin/env python3
"""Native, public-input history ablation. No Flutter, display, ONNX or network."""
import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import signal
import statistics
import subprocess
import threading
from datetime import datetime
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
CORE = ['game_engine.dart', 'game_state_codec.dart', 'policy_core.dart',
        'statistics/statistics_advisor.dart', 'statistics/statistics_card_beliefs.dart', 'statistics/statistics_table_model.dart', 'statistics/statistics_policy.dart']


def mean(values):
    return statistics.mean(values) if values else None


def paired_interval(values):
    rng = random.Random(52)
    bootstrap = sorted(mean(rng.choices(values, k=len(values))) for _ in range(5000))
    return [bootstrap[int(.025 * len(bootstrap))], bootstrap[int(.975 * len(bootstrap))]]


def summarize(games, probes, lengths):
    prediction = []
    for length in range(33):
        rows = [r for r in probes if r['historyLength'] == length]
        cards = sum(r['cards'] for r in rows)
        prediction.append({'historyLength': length, 'snapshots': len(rows), 'cards': cards,
            'brier': sum(r['brierSum'] for r in rows) / cards if cards else None,
            'logLoss': sum(r['logLossSum'] for r in rows) / cards if cards else None,
            'fallbackRate': mean([int(r['fallback']) for r in rows]),
            'beliefMs': mean([r['beliefMicros'] / 1000 for r in rows])})
    gameplay = []
    for count in range(1, 5):
        baseline = {r['seed']: r for r in games if r['players'] == count and r['historyLength'] == 16}
        for length in lengths:
            rows = [r for r in games if r['players'] == count and r['historyLength'] == length]
            if not rows:
                continue
            differences = [r['drinks'] - baseline[r['seed']]['drinks'] for r in rows] if baseline else []
            decisions = sum(r['decisions'] for r in rows)
            gameplay.append({'players': count, 'historyLength': length, 'games':len(rows),
                'meanDrinks': mean([r['drinks'] for r in rows]),
                'differenceFrom16': mean(differences),
                'difference95': paired_interval(differences) if differences else None,
                'decisionMs': sum(r['micros'] for r in rows) / decisions / 1000,
                'beliefMs': sum(r['beliefMicros'] for r in rows) / decisions / 1000,
                'fallbackRate': sum(r['fallbacks'] for r in rows) / decisions,
                'searchFallbackRate': sum(r.get('searchFallbacks', r['fallbacks']) for r in rows) / decisions})
    return {'prediction': prediction, 'gameplay': gameplay}


def write_report(output, summary, config):
    lines = ['# Statistics history-length investigation', '',
        f"Complete games: {config['games']}; {0 if config.get('probeOnly') else config['deals']} matched initial deals per player count; "
        f"{config['rounds']} fixed search rounds. " + (
            f"Search scenario seed {config['scenarioSeed']} is independent of the real game's seed and of belief reconstruction."
            if config['scenarioSeed'] is not None else
            "This follow-up retains the deployed shared belief/search RNG stream; history changes can also change its randomized search sequence."), '',
        '## Card prediction (all lengths 0–32)', '',
        'All lengths predict the same public-board snapshots. Hidden cards are read only by the evaluator after prediction. Lower Brier/log loss is better. Snapshots within a trajectory are correlated; card counts are not independent sample sizes.', '',
        '| History | Brier | Log loss | Belief ms | Reset rate |', '|---|---:|---:|---:|---:|']
    for row in summary['prediction']:
        if row['brier'] is not None:
            lines.append(f"| {row['historyLength']} | {row['brier']:.5f} | {row['logLoss']:.5f} | {row['beliefMs']:.3f} | {100*row['fallbackRate']:.1f}% |")
    lines += ['', '## Mean personal drinks through completion', '',
        '| Players | History | Mean drinks | Change vs 16 | Approx. paired 95% interval | Decision ms | Probability reset | Search reset |',
        '|---|---|---:|---:|---|---:|---:|---:|']
    for row in summary['gameplay']:
        interval = row['difference95']
        ci = f'[{interval[0]:.1f}, {interval[1]:.1f}]' if interval else '—'
        delta = f"{row['differenceFrom16']:+.1f}" if interval else '—'
        lines.append(f"| {row['players']} | {row['historyLength']} | {row['meanDrinks']:.1f} | {delta} | {ci} | {row['decisionMs']:.2f} | {100*row['fallbackRate']:.1f}% | {100*row['searchFallbackRate']:.1f}% |")
    lines += ['', '## Interpretation limits', '',
        'The default remains 16 events unless a separate recommendation explicitly changes it. A 0-event run still sees the current public board, player list and legal turn flags. The history limit counts public events (including passes), not just guesses. The actual retained history can be shorter early in a game.', '',
        ('The independent scenario stream isolates memory from accidental random-number consumption during belief reconstruction. Production retains its original random stream unless this optional evaluation seed is supplied. These results assess history under matched search scenarios rather than certify a drop-in production improvement.'
         if config['scenarioSeed'] is not None else
         'This follow-up keeps the deployed shared random stream. Changes in history can change both the belief and subsequent randomized search draws. It tests the actual production behavior, not a clean isolation of memory alone.'), '',
        'Strategic search retains 128 samples and may lose history; reported probabilities now use direct constraints. Probability resets and search resets are separate counters. Older reports predate that split. More history can still deplete the search samples. The fixed-round comparison measures prediction/decision changes without letting longer preparation reduce search rounds. With the app’s 180 ms target, preparation and mandatory rounds can still overshoot; smartphone performance is not measured here.', '',
        'Native Dart desktop timings exclude Flutter UI/isolate overhead and run with concurrent workers. Opponents use fixed casual, probability-aware and cautious styles, rotated by seat and deal. Paired games share their initial deck, but later histories diverge. Confidence intervals are exploratory percentile paired bootstrap intervals from 5,000 resamples, with no multiple-comparison correction. Large game variance and small per-count samples preclude selecting a universal best length from the smallest observed mean alone.', '',
        'The probability probe uses separate fixed public heuristics to generate trajectories. All 33 lengths see each same snapshot with at least 32 available events. Probe seeds are separate for each player count (23000 + 1000×players + deal). That isolates prediction quality but does not establish a gameplay advantage. No policy learns or receives actual hidden cards, deck order or game RNG state.', '']
    (output/'report.md').write_text('\n'.join(lines))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lengths', nargs='+', type=int, default=[0,4,8,16,24,32])
    parser.add_argument('--deals', type=int, default=10)
    parser.add_argument('--rounds', type=int, choices=[3,6,9,12], default=6)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--seed', type=int, default=16000)
    parser.add_argument('--production-stream', action='store_true', help='Keep the deployed belief/search RNG coupling')
    parser.add_argument('--scenario-seed', type=int, default=48271)
    parser.add_argument('--probe-only', action='store_true', help='Score all 33 lengths without running games')
    parser.add_argument('--probe-deals', type=int, default=4)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    lengths = sorted(set(args.lengths))
    total = 0 if args.probe_only else 4 * args.deals * len(lengths)
    if any(n < 0 or n > 32 for n in lengths) or args.deals < 1 or args.workers < 1 or args.probe_deals < 1:
        parser.error('Lengths must be 0–32; deals, workers and probe-deals must be positive.')
    if total > 250:
        parser.error(f'{total} games exceeds the 250-game comparison cap.')
    if 16 not in lengths and not args.probe_only:
        parser.error('Include length 16 as the paired reference.')
    if not shutil.which('dart'):
        parser.error('Dart SDK is required; no desktop fallback is used.')
    output = (args.output or ROOT/'benchmark-results'/('history-'+datetime.now(ZoneInfo('Europe/Berlin')).strftime('%Y-%m-%d_%H-%M-%S'))).resolve()
    output.mkdir(parents=True, exist_ok=False)
    paths = [ROOT/'app/lib'/n for n in CORE] + [ROOT/'statistics/bin/history_benchmark.dart', Path(__file__)]
    hashes = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    sdk = subprocess.check_output(['dart','--version'],text=True).strip()
    digest = hashlib.sha256(json.dumps([hashes,sdk],sort_keys=True).encode()).hexdigest()[:24]
    cache = ROOT/'benchmark-cache'/('history-'+digest)
    binary = cache/'history_benchmark'
    config = {**vars(args),'output':str(output),'lengths':lengths,'games':total,
        'scenarioSeed':None if args.production_stream else args.scenario_seed,'probeDeals':args.probe_deals,'probeOnly':args.probe_only,'sha256':hashes,'dart':sdk}
    (output/'config.json').write_text(json.dumps(config,indent=2,default=str))
    running = set()
    lock = threading.Lock()
    stopped = threading.Event()

    def call(mode, job):
        with lock:
            if stopped.is_set():
                raise RuntimeError('Comparison cancelled')
            process = subprocess.Popen([str(binary),mode,json.dumps(job)], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,text=True,start_new_session=True)
            running.add(process)
        try:
            stdout, stderr = process.communicate(timeout=600)
            if process.returncode:
                raise RuntimeError(stderr or f'Worker exited {process.returncode}')
            return json.loads(stdout)
        finally:
            if process.poll() is None:
                os.killpg(process.pid,signal.SIGTERM)
                process.wait()
            with lock:
                running.discard(process)

    pool = None
    try:
        with (output/'build.log').open('w') as log:
            if not binary.exists():
                (cache/'app/lib').mkdir(parents=True,exist_ok=True)
                (cache/'statistics/bin').mkdir(parents=True,exist_ok=True)
                for name in CORE:
                    destination = cache/'app/lib'/name
                    destination.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copyfile(ROOT/'app/lib'/name,destination)
                shutil.copyfile(ROOT/'statistics/bin/history_benchmark.dart',cache/'statistics/bin/history_benchmark.dart')
                print('Compiling the actual shared Dart adviser.',flush=True)
                subprocess.run(['dart','compile','exe','statistics/bin/history_benchmark.dart','-o',str(binary)],
                    cwd=cache,stdout=log,stderr=log,check=True)
        print('Scoring all history lengths 0–32 on matched public snapshots.',flush=True)
        probes = call('probe',config)
        (output/'probes.json').write_text(json.dumps(probes))
        if args.probe_only:
            summary = summarize([],probes,lengths)
            (output/'summary.json').write_text(json.dumps(summary,indent=2))
            write_report(output,summary,config)
            print(f'Report: {output / "report.md"}',flush=True)
            return
        jobs = [{'players':n,'seed':args.seed+deal,'historyLength':h,'rounds':args.rounds,
            'scenarioSeed':config['scenarioSeed']} for n in range(1,5) for deal in range(args.deals) for h in lengths]
        games = []
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=args.workers)
        futures = [pool.submit(call,'game',job) for job in jobs]
        with (output/'games.jsonl').open('w') as raw:
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                games.append(result)
                raw.write(json.dumps(result)+'\n'); raw.flush()
                print(f"{len(games)}/{total}: {result['players']} players, H={result['historyLength']}, seed={result['seed']}, drinks={result['drinks']}",flush=True)
        summary = summarize(games,probes,lengths)
        (output/'summary.json').write_text(json.dumps(summary,indent=2))
        write_report(output,summary,config)
        print(f'Report: {output / "report.md"}',flush=True)
    except BaseException as exc:
        stopped.set()
        with lock:
            for process in list(running):
                if process.poll() is None:
                    os.killpg(process.pid,signal.SIGTERM)
        (output/'FAILED.txt').write_text(f'No completed comparison: {type(exc).__name__}: {exc}\n')
        raise
    finally:
        if pool:
            pool.shutdown(wait=True,cancel_futures=True)


if __name__ == '__main__':
    main()
