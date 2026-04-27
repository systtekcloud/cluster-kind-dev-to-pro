#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "Uso: $0 <dev|pro>"
  exit 1
fi

exec "$ROOT_DIR/components/vault/setup/seed-secrets.sh" "$TARGET"
