"""Held-out game evaluation and public-rank sanity probes (never training features)."""
import argparse
import json
from pathlib import Path

import torch

from export_onnx import load_checkpoint
from train import evaluate_held_out, load_json, masked_distribution, select_device
from window_rl.contract import action_index
from window_rl.cuda_environment import BatchedWindowEnv


@torch.no_grad()
def rank_sanity(model, config, device, seed=8675309):
    """Force only the publicly visible handle rank on fresh starting boards.

    Swap physical cards to preserve the deck. No target identity or computed
    success probability is supplied to the policy. Impossible guesses remain
    legal: this measures learning, rather than hiding errors with a new mask.
    """
    results = {}
    for rank, bad_guess in [(0, 2), (8, 0)]:
        env = BatchedWindowEnv(config['reward'], 256, 1000, device, seed,
                               config['environment']['history_length'],
                               config['environment']['player_count'])
        for i in range(env.num_envs):
            wanted = rank * 4
            old = env.cards[i, 2, 5].clone()
            on_board = (env.cards[i] == wanted).nonzero()
            if on_board.numel():
                r, c = on_board[0]
                env.cards[i, r, c] = old
            else:
                env.deck[i, :env.deck_size[i]][env.deck[i, :env.deck_size[i]] == wanted] = old
            env.cards[i, 2, 5] = wanted
        env._append_current_record()
        probabilities = masked_distribution(model(env.history_observation())[0], env.action_mask()).probs
        bad_action = action_index(2, 4, 0, bad_guess)
        results['lowest' if rank == 0 else 'highest'] = {
            'impossible_greedy_fraction': float((probabilities.argmax(1) == bad_action).float().mean().cpu()),
            'impossible_probability_mean': float(probabilities[:, bad_action].mean().cpu()),
        }
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--config', type=Path, default=Path('configs/training_config.json'))
    parser.add_argument('--device', default='cuda')
    parser.add_argument('--episodes', type=int, default=128)
    parser.add_argument('--max-steps', type=int, help='Evaluation-only game horizon; never changes model inputs.')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--seeds', type=int, nargs='+', default=[1729, 271828])
    parser.add_argument('--probe-seed', type=int, default=8675309)
    args = parser.parse_args()
    device = select_device(args.device)
    config = load_json(args.config)
    if args.episodes < 1 or (args.max_steps is not None and args.max_steps < 1):
        parser.error("episodes and max-steps must be positive")
    if args.max_steps is not None:
        config["environment"]["max_steps"] = args.max_steps
    config['evaluation']['episodes_per_seed'] = args.episodes
    # These are independent of the checkpoint-selection board sets.
    config['evaluation']['seeds'] = args.seeds
    model, payload = load_checkpoint(args.checkpoint)
    model.to(device).eval()
    config['environment']['history_length'] = payload['training'].get('history_length', 16)
    result = {'checkpoint': str(args.checkpoint), 'player_count': config['environment']['player_count'],
              'seeds': config['evaluation']['seeds'], 'episodes_per_seed': args.episodes,
              'max_steps': config['environment']['max_steps'],
              **evaluate_held_out(model, config, device), 'probe_seed': args.probe_seed, 'rank_sanity': rank_sanity(model, config, device, args.probe_seed)}
    output = json.dumps(result, indent=2)
    print(output)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + '\n')


if __name__ == '__main__':
    main()
