#!/usr/bin/env python3
"""Compile the very same Dart game rules for the Cloudflare backend."""
from pathlib import Path
import shutil
import subprocess
root = Path(__file__).resolve().parent.parent
dart = shutil.which('dart') or str(Path.home() / '.local/flutter/bin/dart')
subprocess.run([dart, 'compile', 'js', '-O2', '--no-source-maps',
                '-o', str(root / 'backend/src/engine.generated.js'),
                str(root / 'backend/engine_bridge.dart')], check=True)
