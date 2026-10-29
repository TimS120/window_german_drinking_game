#!/usr/bin/env python3
"""Persistent, single-threaded ONNX inference. No game state or hidden cards enter here."""
import json
from pathlib import Path
import sys
import numpy as np
import onnxruntime as ort


def main():
    model_path, metadata_path = map(Path, sys.argv[1:3])
    metadata = json.loads(metadata_path.read_text())
    if not (metadata.get('trained') is True and (metadata.get('format'), metadata.get('historyFeatureSize'), metadata.get('observationRevision')) in ((4, 130, 2), (5, 134, 3)) and
            metadata.get('actionSize') == 301 and
            1 <= metadata.get('historyLength', 0) <= 64):
        raise ValueError('Trained model metadata does not match the deployed recurrent contract')
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.add_session_config_entry('session.intra_op.allow_spinning', '0')
    session = ort.InferenceSession(str(model_path), sess_options=options,
                                  providers=['CPUExecutionProvider'])
    print(json.dumps({'ready': True, 'historyLength': metadata['historyLength'], 'historyFeatureSize': metadata['historyFeatureSize'],
                      'onnxruntime': ort.__version__, 'numpy': np.__version__,
                      'intraOpThreads': 1, 'interOpThreads': 1, 'providers': session.get_providers()}), flush=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            history = np.asarray(request['history'], dtype=np.float32).reshape(
                1, metadata['historyLength'], metadata['historyFeatureSize'])
            legal = np.asarray(request['legal'], dtype=np.int64)
            if legal.size == 0 or np.any(legal < 0) or np.any(legal >= 301):
                raise ValueError('No valid legal actions supplied')
            logits = session.run(['policy_logits'], {session.get_inputs()[0].name: history})[0].reshape(-1)
            if logits.size != 301 or not np.isfinite(logits).all():
                raise ValueError('Invalid policy logits')
            # Preserve Dart/app legal-action ordering, including tie breaking.
            action = int(legal[np.argmax(logits[legal])])
            print(json.dumps({'action': action}), flush=True)
        except Exception as error:
            print(json.dumps({'error': str(error)}), flush=True)
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
