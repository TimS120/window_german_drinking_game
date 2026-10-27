#!/usr/bin/env python3
"""Create a private local admin key; upload only its hash as a Worker secret."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import secrets
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', type=Path, default=Path.home() / '.config/window-game/async-admin-key.txt')
    parser.add_argument('--upload', action='store_true')
    args = parser.parse_args()
    path = args.key_file.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as output:
            output.write(secrets.token_hex(32) + '\n')
    path.chmod(0o600)
    key = path.read_text().strip().lower()
    if not re.fullmatch('[a-f0-9]{64}', key):
        parser.error('The admin key file must contain exactly 64 hexadecimal characters.')
    if args.upload:
        subprocess.run(['npx', 'wrangler', 'secret', 'put', 'ADMIN_KEY_HASH'],
                       cwd=Path(__file__).resolve().parent.parent / 'backend',
                       input=(hashlib.sha256(key.encode()).hexdigest() + '\n').encode(), check=True)
    print(f'Private admin key file (keep local): {path}')


if __name__ == '__main__':
    main()
