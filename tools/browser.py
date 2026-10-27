#!/usr/bin/env python3
"""Build or publish the browser guest client with the same Firebase config as apps."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "deploy"])
    parser.add_argument("--config", type=Path, default=root / "firebase-options.json")
    parser.add_argument("--local-only", action="store_true", help="Build without publishing (build action only).")
    args = parser.parse_args()
    if args.local_only and args.action != "build":
        parser.error("--local-only is available only with build")
    config_path = args.config.resolve()
    if not config_path.is_file():
        parser.error(f"Firebase configuration not found: {config_path}")
    config = json.loads(config_path.read_text())
    required = ["FIREBASE_PROJECT_ID", "FIREBASE_DATABASE_URL"]
    missing = [key for key in required if not config.get(key)]
    if not (config.get("FIREBASE_WEB_API_KEY") or config.get("FIREBASE_API_KEY")):
        missing.append("FIREBASE_WEB_API_KEY or FIREBASE_API_KEY")
    if missing:
        parser.error("Missing configuration: " + ", ".join(missing))
    subprocess.run([os.sys.executable, str(root / 'tools/configure_async_notifications.py')], check=True)
    subprocess.run(
        ["flutter", "build", "web", "--release", "--no-wasm-dry-run",
         f"--dart-define-from-file={config_path}"],
        cwd=root / "app", check=True,
    )
    if not args.local_only:
        env = os.environ.copy()
        # Flutter ships sizable WASM assets; avoid saturating slower uplinks.
        env.setdefault("FIREBASE_HOSTING_UPLOAD_CONCURRENCY", "4")
        subprocess.run(
            ["npx", "--yes", "firebase-tools", "deploy", "--only", "database,hosting" if args.action == "deploy" else "hosting",
             "--project", config["FIREBASE_PROJECT_ID"], "--non-interactive"],
            cwd=root, check=True, env=env,
        )


if __name__ == "__main__":
    main()
