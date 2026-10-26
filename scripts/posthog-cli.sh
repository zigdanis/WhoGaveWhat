#!/bin/bash

set -euo pipefail

# Runs posthog-cli against the WhoGaveWhat PostHog project (EU Cloud) with the personal API key
# stored outside the repository. The key never lives in the checkout; see docs/analytics.md.
#
# One-time setup per machine, with a key from the "PostHog personal API key" entry in Passwords:
#   mkdir -p ~/.config/posthog && umask 077 && cat > ~/.config/posthog/whogavewhat.env <<EOT
#   POSTHOG_CLI_API_KEY=phx_...
#   POSTHOG_CLI_PROJECT_ID=320692
#   POSTHOG_CLI_HOST=https://eu.posthog.com
#   EOT
#
# Then: scripts/posthog-cli.sh api --agent-help
#       scripts/posthog-cli.sh api call --json execute-sql '{"query":"SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 1 DAY GROUP BY event"}'
export POSTHOG_CLI_DOTENV_FILE="${POSTHOG_CLI_DOTENV_FILE:-$HOME/.config/posthog/whogavewhat.env}"
if [ -z "${POSTHOG_CLI_API_KEY:-}" ] && [ ! -r "$POSTHOG_CLI_DOTENV_FILE" ]; then
  echo "posthog-cli: no credentials; create $POSTHOG_CLI_DOTENV_FILE (see the header of this script)" >&2
  exit 10
fi
if command -v posthog-cli >/dev/null 2>&1; then
  exec posthog-cli "$@"
fi
exec npx -y @posthog/cli@0.18.12 "$@"
