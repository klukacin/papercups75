#!/usr/bin/env bash
# Deletes the 48 upstream/inherited remote branches from origin (klukacin/papercups75).
# Keeps only: master (default) and claude/repo-analysis-mniloc.
# Run this LOCALLY where you have full push rights (the Claude Code cloud env is blocked by org policy / 403).
#
# Usage: bash scripts/delete-inherited-branches.sh
set -uo pipefail

BRANCHES=(
  "broken-package-upload"
  "client-side-zipping"
  "conversations-provider-refactor-2"
  "dark-mode-sandbox"
  "dashboard-trial-banner"
  "debug-slack-notification-eu"
  "discord-integration-v1"
  "docker-build-fix"
  "elixir-releases"
  "elixir-upgrade-fly"
  "email-form"
  "email-forwarding"
  "fix-socket-disconnect"
  "fix-workers"
  "fly-test-2"
  "gigalixir"
  "hotfix"
  "improve-getting-started-fields"
  "improve-identify-by-external-id"
  "improve-perf"
  "improve-slack-logging"
  "lambdas-boilerplate"
  "layers"
  "list-forgotten-conversations-query"
  "load-previous-conversation-ui"
  "make-ssl-optional"
  "message-notification-logging"
  "message-templates-sandbox"
  "minor-css-fix"
  "no-proc"
  "personal-api-key-ui"
  "posthog-events-integration"
  "pricing-for-eu-edition"
  "query-latest-customer-message"
  "redis-one-click"
  "redis-tls-url"
  "setup-feedback-widget"
  "slack-async-hotfix"
  "storybook"
  "test-lambda-layer"
  "test-monaco-editor"
  "tweak-sample-code"
  "twilio-instructions"
  "twilio-integration-boilerplate"
  "update-elixir-1.11"
  "update-reporting-colors"
  "use-mailbox-client"
  "user-profile-improvement"
)

for b in "${BRANCHES[@]}"; do
  echo "Deleting origin/$b ..."
  git push origin --delete "$b"
done

echo "Done. Remaining remote branches:"
git branch -r
