"""Check an exported ONNX policy against its checkpoint on public game histories."""
import argparse
import json
from pathlib import Path

import numpy as np
import onnx
from onnx.reference import ReferenceEvaluator
import torch

from export_onnx import DeploymentPolicy, load_checkpoint
from window_rl.contract import HISTORY_FEATURE_SIZE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--onnx', type=Path, required=True)
    args = parser.parse_args()
    torch.set_num_threads(1)
    model, payload = load_checkpoint(args.checkpoint)
    deployment = DeploymentPolicy(model, payload.get("training", {}).get("reward_scale", 1.0)).eval()
    length = payload['training'].get('history_length', 16)
    graph = onnx.load(args.onnx)
    onnx.checker.check_model(graph, full_check=True)
    runtime = ReferenceEvaluator(graph)
    fixtures = json.loads((Path(__file__).parent / 'fixtures/recurrent_contract.json').read_text())
    max_error = 0.
    for fixture in fixtures:
        records = np.array(fixture['history'], dtype=np.float32).reshape(-1, HISTORY_FEATURE_SIZE)
        history = np.zeros((1, length, HISTORY_FEATURE_SIZE), dtype=np.float32)
        count = min(length, records.shape[0])
        history[0, -count:] = records[-count:]
        with torch.no_grad():
            expected = deployment(torch.from_numpy(history))
        actual = runtime.run(['policy_logits', 'state_value'], {'history': history})
        for target, output in zip(expected, actual):
            np.testing.assert_allclose(output, target.numpy(), rtol=1e-4, atol=1e-5,
                                       err_msg=fixture['name'])
            max_error = max(max_error, float(np.abs(output-target.numpy()).max()))
        legal = fixture['legalActions']
        assert legal[int(actual[0][0, legal].argmax())] == legal[int(expected[0][0, legal].argmax())], fixture['name']
    print(json.dumps({'fixtures': len(fixtures), 'max_absolute_error': max_error,
                      'all_masked_actions_match': True}, indent=2))


if __name__ == '__main__':
    main()
