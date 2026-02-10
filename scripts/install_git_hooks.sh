#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "error: expected a git repository at: $repo_root" >&2
  exit 1
fi

if [[ ! -d ".githooks" ]]; then
  echo "error: .githooks directory is missing" >&2
  exit 1
fi

if [[ ! -f ".githooks/pre-commit" ]]; then
  echo "error: missing pre-commit hook: .githooks/pre-commit" >&2
  exit 1
fi

chmod +x .githooks/pre-commit

git config core.hooksPath .githooks

echo "install_git_hooks: OK"
echo "Git hooks path set to: $(git config core.hooksPath)"
