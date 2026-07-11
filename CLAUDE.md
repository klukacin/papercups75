# papercups75

Maintained fork of Papercups — open-source live customer-chat (Elixir/Phoenix + React).
Stack: Erlang/OTP 27.3, Elixir 1.18.4, Node 22 (build), PostgreSQL 16. See `README.md`.

## Where your changes appear (CI/CD)

This repo **auto-deploys to production**. **GitHub is the source of truth**; you keep
pushing to GitHub as usual.

| You push to (GitHub) | What happens | Live URL |
|---|---|---|
| `master` | GitHub CI (`Papercups`) runs → **if green**, the exact commit is mirrored into Gitea (`ws-agency/papercups75`) → Gitea Actions builds the image (factory-dind → Harbor) and deploys it to **ws03** | https://app.papercups75.com |

- **Full flow:** `git push` → GitHub `master` → CI must pass ✅ → auto-mirror to Gitea →
  build → Harbor → ws03 `docker compose pull`. Live in **~10–20 min** (the Elixir
  release + React build is slow — be patient).
- A **red ❌ CI** run means the change did **NOT** deploy — it never reaches Gitea. Fix CI first.
- **Migrations** (Ecto) run inside the container on boot (`db createdb && db migrate`);
  a failed migration crashes the container, so a bad migration fails the deploy visibly.
- **Watch runs:** GitHub → Actions tab (CI + "Mirror to Gitea"); Gitea →
  https://git.wsagency.io/ws-agency/papercups75/actions (build + deploy).
- **Test on https://app.papercups75.com. Do NOT SSH to the server or deploy manually.**

Infra details (compose, envs, Harbor, DNS) live in the ops repo, not here:
`servers/ws03.prod.nebion.host/changelog.md` + memory `project_papercups75`.
