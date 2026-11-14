#!/bin/bash

set -euo pipefail

# Runs posthog-cli against the WhoGaveWhat PostHog project (EU Cloud) with the personal API key.
# The key never lives in the checkout or in a plaintext file: it is in Danis's SOPS vault
# (~/myai/fleet-secrets/whogavewhat/posthog-cli.env, opened by MacPro, MacAir and Raspi), and
# this script decrypts it into the posthog-cli environment only. See docs/analytics.md.
#
# The vault file holds three lines (edit with `sops edit`, then commit and push in fleet-secrets):
#   POSTHOG_CLI_API_KEY=phx_...
#   POSTHOG_CLI_PROJECT_ID=320692
#   POSTHOG_CLI_HOST=https://eu.posthog.com
#
# Then: scripts/posthog-cli.sh api --agent-help
#       scripts/posthog-cli.sh api call --json execute-sql '{"query":"SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 1 DAY GROUP BY event"}'
# POSTHOG_CLI_API_KEY already in the environment, or POSTHOG_CLI_DOTENV_FILE, overrides the vault.
VAULT_FILE="${WHOGAVEWHAT_POSTHOG_VAULT:-$HOME/myai/fleet-secrets/whogavewhat/posthog-cli.env}"
if [ -z "${POSTHOG_CLI_API_KEY:-}" ] && [ -z "${POSTHOG_CLI_DOTENV_FILE:-}" ]; then
  sops=$(command -v sops || true)
  [ -n "$sops" ] || [ ! -x "$HOME/.local/bin/sops" ] || sops=$HOME/.local/bin/sops
  [ -n "$sops" ] || [ ! -x /opt/homebrew/bin/sops ] || sops=/opt/homebrew/bin/sops
  if [ -z "$sops" ] || [ ! -r "$VAULT_FILE" ]; then
    echo "posthog-cli: no credentials; need sops and $VAULT_FILE (clone zigdanis/fleet-secrets to ~/myai/fleet-secrets)" >&2
    exit 10
  fi
  if ! decrypted=$("$sops" decrypt "$VAULT_FILE"); then
    echo "posthog-cli: sops could not decrypt $VAULT_FILE" >&2
    exit 10
  fi
  while IFS='=' read -r name value; do
    case "$name" in
      POSTHOG_CLI_*) export "$name=$value" ;;
    esac
  done <<< "$decrypted"
  unset decrypted
fi
if command -v posthog-cli >/dev/null 2>&1; then
  exec posthog-cli "$@"
fi
exec npx -y @posthog/cli@0.18.12 "$@"
