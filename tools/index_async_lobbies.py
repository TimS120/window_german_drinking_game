#!/usr/bin/env python3
"""Index pre-management lobbies without changing their activity or deleting data.

Requires an existing Wrangler login (run `npx wrangler whoami` to refresh it),
or CLOUDFLARE_API_TOKEN. No Cloudflare credential is sent to the game backend.
"""
import argparse
import json
import os
from pathlib import Path
import tomllib
import urllib.parse
import urllib.request


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--account-id', required=True)
    parser.add_argument('--worker-name', default='window-async')
    parser.add_argument('--backend-url')
    parser.add_argument('--admin-key-file', type=Path, default=Path.home() / '.config/window-game/async-admin-key.txt')
    args = parser.parse_args()
    token = os.environ.get('CLOUDFLARE_API_TOKEN')
    if not token:
        config = Path.home() / '.config/.wrangler/config/default.toml'
        token = tomllib.loads(config.read_text())['oauth_token']
    backend = args.backend_url or json.loads((root / 'firebase-options.json').read_text())['WINDOW_ASYNC_URL']
    admin_key = args.admin_key_file.expanduser().read_text().strip().lower()

    def request(url, credential, body=None):
        req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                     headers={'Authorization': 'Bearer ' + credential, 'Content-Type': 'application/json', 'User-Agent': 'WindowGameLobbyIndexer/1.0'})
        with urllib.request.urlopen(req, timeout=45) as response:
            return json.load(response)

    base = f'https://api.cloudflare.com/client/v4/accounts/{args.account_id}/workers/durable_objects/namespaces'
    namespaces = request(base, token)['result']
    matches = [n for n in namespaces if n.get('script') == args.worker_name and n.get('class') == 'GameRoom']
    if len(matches) != 1:
        raise SystemExit('Could not identify exactly one GameRoom namespace for this Worker.')
    namespace = matches[0]['id']
    objects, after = [], None
    while True:
        params = {'limit': 100}
        if after:
            params['after'] = after
        page = request(f'{base}/{namespace}/objects?' + urllib.parse.urlencode(params), token)['result']
        if not page:
            break
        objects.extend(item['id'] for item in page if item.get('hasStoredData'))
        after = page[-1]['id']
        if len(page) < 100:
            break
    indexed = 0
    for offset in range(0, len(objects), 10):
        result = request(backend.rstrip('/') + '/admin/import', admin_key, {'objectIds': objects[offset:offset + 10]})
        indexed += result['indexed']
    print(f'Indexed {indexed} existing lobbies; inspected {len(objects)} stored objects. No lobbies deleted.')


if __name__ == '__main__':
    main()
