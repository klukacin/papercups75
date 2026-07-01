# Inherited upstream branches (from the Papercups fork)

This repository was forked from [papercups-io/papercups](https://github.com/papercups-io/papercups).
It came with ~48 leftover feature/experiment branches created upstream between
2020 and 2022 — none of which we (papercups75) authored. This document records
what each was, so ideas aren't lost when the branches are cleaned up.

**None of these are mergeable into papercups75's modern codebase** (Phoenix
1.7 / React 18 / OTP 27). They predate the whole modernization and, for most,
git finds **no common ancestor** with the current `master` (history was
rewritten upstream). Any wanted feature should be **re-implemented fresh** on
the current base, not merged.

## Analyzable branches (share history with master; real diffs)

| Branch | Date | What it is | Verdict |
|---|---|---|---|
| `dashboard-trial-banner` | 2022-01 | Trial/billing banner in the dashboard + trial logic in accounts.ex | Idea: reimplement if billing UI wanted |
| `discord-integration-v1` | 2021-10 | **Discord integration** (client/consumer/controller + UI), like Slack/Mattermost | Idea worth reimplementing |
| `message-templates-sandbox` | 2021-10 | **Message templates + broadcasts** (mass messaging): migrations, controllers, tests | Substantial feature; reimplement if wanted |
| `posthog-events-integration` | 2021-08 | **PostHog** product-analytics client + frontend event tracking | Idea: reimplement if product analytics wanted |
| `use-mailbox-client` | 2022-01 | Refactor of email sending into a `Mailbox` client (deletes emails/email.ex) | Conflicts with current email.ex; skip |
| `email-forwarding` | 2021-08 | Early SES inbound email forwarding (ses_controller, lambda) | Superseded — SES/forwarding already in app |
| `storybook` | 2021-08 | Storybook 6 component-dev setup | Outdated; re-add modern Storybook if wanted |
| `fix-workers` | 2021-09 | 5-line Oban queue config tweak | Superseded by our Oban 2.23 config |
| `elixir-releases` | 2021-08 | Docker/Procfile/heroku.yml for Elixir releases | Superseded by our Docker/release setup |
| `gigalixir` | 2021-08 | Gigalixir deploy config | Not used |
| `redis-one-click` | 2021-08 | Redis in Heroku one-click deploy | Not used |

## Orphaned branches (no common ancestor with master; un-mergeable, un-diffable)

These 37 are ancient experiments/spikes/deploy-configs with no shared history —
nothing to merge or analyze. Listed for the record before deletion.

| Branch | Date | Tip commit |
|---|---|---|
| `broken-package-upload` | 2021-06-15 | lambda-function-broken |
| `client-side-zipping` | 2021-06-17 | Try again |
| `conversations-provider-refactor-2` | 2021-04-26 | Refactors how conversations are stored in Conversa |
| `dark-mode-sandbox` | 2021-07-16 | Play around with dark mode |
| `debug-slack-notification-eu` | 2021-03-19 | Merge branch 'master' into debug-slack-notificatio |
| `docker-build-fix` | 2021-02-26 | --amend |
| `elixir-upgrade-fly` | 2021-03-24 | WIP |
| `email-form` | 2021-06-07 | Merge branch 'master' into email-form |
| `fix-socket-disconnect` | 2021-04-28 | Adds continuous attempt to reconnect |
| `fly-test-2` | 2021-03-17 | Merge branch 'master' into fly-test-2 |
| `hotfix` | 2021-03-23 | Add logging for broadcasts |
| `improve-getting-started-fields` | 2021-02-19 | Start adding more fields to Getting Started page ( |
| `improve-identify-by-external-id` | 2021-01-14 | Play around with some more potential improvements  |
| `improve-perf` | 2021-03-16 | Test disabling gzip |
| `improve-slack-logging` | 2021-01-09 | Clean up logging some more |
| `lambdas-boilerplate` | 2021-06-14 | Minor cleanup |
| `layers` | 2021-06-19 | use layers |
| `list-forgotten-conversations-query` | 2021-05-06 | Set up boilerplate for worker to send conversation |
| `load-previous-conversation-ui` | 2021-01-20 | Start playing around with the UI for loading previ |
| `make-ssl-optional` | 2021-03-01 | fix env by converting to boolean |
| `message-notification-logging` | 2021-03-23 | More log info for message notification debugging |
| `minor-css-fix` | 2021-01-23 | fix padding height on all conversations css |
| `no-proc` | 2021-08-08 | test removing procfile |
| `personal-api-key-ui` | 2021-02-24 | Sort messages by inserted_at |
| `pricing-for-eu-edition` | 2021-03-12 | Update copy for starter price |
| `query-latest-customer-message` | 2021-04-30 | Include latest message in customer index api respo |
| `redis-tls-url` | 2021-06-22 | Test socket_opts |
| `setup-feedback-widget` | 2020-10-09 | Play around with idea of a 'feedback widget' |
| `slack-async-hotfix` | 2021-03-23 | Add logging for debugging |
| `test-lambda-layer` | 2021-06-21 | Play around with using lambda layer for deps |
| `test-monaco-editor` | 2021-06-25 | Test out monaco code editor |
| `tweak-sample-code` | 2021-06-23 | Fix merge comments |
| `twilio-instructions` | 2021-05-05 | Add twillio instructions |
| `twilio-integration-boilerplate` | 2021-03-19 | Set up dependency and config for Twilio |
| `update-elixir-1.11` | 2021-03-15 | WIP |
| `update-reporting-colors` | 2021-01-14 | Play around with some different coloring in the re |
| `user-profile-improvement` | 2021-05-06 | Trigger is editing when the text is changed |
