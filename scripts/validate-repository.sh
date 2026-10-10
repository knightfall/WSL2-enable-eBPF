#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo_dir"
shellcheck -x -P SCRIPTDIR scripts/*.sh
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/check-links.py
python3 -m unittest discover -s tests -v
docker compose --env-file examples/.env.example -f examples/compose.yaml --profile demo config --quiet
