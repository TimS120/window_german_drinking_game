"""Padding must never acquire player context in deployment parity probes."""
import json
from pathlib import Path
import unittest
import numpy as np
from window_rl.deployment_fixtures import encode_fixture_history


class DeploymentFixtureTest(unittest.TestCase):
    def test_initial_legacy_fixture_has_only_one_real_record(self):
        fixture = json.loads((Path(__file__).parent / 'fixtures/recurrent_contract.json').read_text())[0]
        history = encode_fixture_history(fixture, 33, 134)
        self.assertFalse(history[0, :-1].any())
        self.assertEqual(history[0, -1, 130:].tolist(), [1., 0., 0., 0.])

    def test_new_fixtures_preserve_all_record_values_and_padding(self):
        fixtures = json.loads((Path(__file__).parent / 'fixtures/recurrent_contract_v5.json').read_text())
        for fixture in fixtures:
            actual = encode_fixture_history(fixture, fixture['historyLength'], 134)
            expected = np.asarray(fixture['history'], dtype=np.float32).reshape(actual.shape)
            np.testing.assert_array_equal(actual, expected, err_msg=fixture['name'])
