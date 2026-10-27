#!/usr/bin/env python3
"""Register the Linux bundle's application ID and icon with the desktop."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
bundle = root / 'app/build/linux/x64/release/bundle'
executable = bundle / 'window_game'
if not executable.is_file():
    raise SystemExit('Build the release Linux bundle first: cd app && flutter build linux')

# Desktop Entry Exec values need double quotes and escaped special characters.
def quote_exec(path):
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'

applications = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'applications'
applications.mkdir(parents=True, exist_ok=True)
entry = applications / 'com.timss.window.window_game.desktop'
entry.write_text('\n'.join([
    '[Desktop Entry]', 'Type=Application', 'Name=Window', 'Name[de]=Fenster',
    'Comment=German Window card game', f'Exec={quote_exec(executable)}',
    f'Icon={bundle / "data/window-icon.png"}', 'Terminal=false',
    'Categories=Game;CardGame;', 'StartupWMClass=com.timss.window.window_game', '',
]))
try:
    subprocess.run(['update-desktop-database', str(applications)], check=True)
except FileNotFoundError:
    pass
print(f'Installed {entry}')
