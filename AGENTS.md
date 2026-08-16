# AGENTS.md

## Cursor Cloud specific instructions

This repository contains two independent products:

- `SSD_Remover/` — a native macOS menu bar app (SwiftUI, Swift 6.2, Xcode 26).
  It depends on Xcode and macOS-only frameworks, so it **cannot be built, run, or
  tested on the Linux Cloud Agent VM**. Build/test it on macOS per `README.md`
  (`xcodegen generate`, then `xcodebuild test -scheme SSD_Remover -destination 'platform=macOS'`).
- `landing/` — the private-beta landing page (Next.js on Vite via `vinext`,
  React 19, Drizzle ORM + Cloudflare D1, Tailwind, Cloudflare Workers/Wrangler).
  This is the only part that runs on the Linux Cloud VM.

### landing service (the runnable product here)

Standard commands live in `landing/package.json` and `landing/README.md`. Run
them from the `landing/` directory:

- Dev server: `npm run dev` → serves `http://localhost:3000/` (a long-running
  process; run it in a dedicated tmux terminal, not via the update script).
- Lint: `npm run lint`
- Build + regression tests: `npm test` (runs `vinext build` then
  `node --test tests/rendered-html.test.mjs`).

### Non-obvious gotchas

- **Generated `build/sites-vite-plugin` file:** `vite.config.ts` imports
  `./build/sites-vite-plugin`, which the OpenAI Sites tooling normally generates.
  It is **not** committed (`build/` is git-ignored by the root `.gitignore`), so
  every command that loads the Vite config (`dev`, `build`, `test`) fails with
  `Could not resolve './build/sites-vite-plugin'` until it exists. The startup
  update script recreates it as a one-line re-export of the published
  `@openai/sites-vite-plugin` package (added to `landing` devDependencies). If it
  ever goes missing, run from `landing/`:
  `mkdir -p build && printf 'export { sites } from "@openai/sites-vite-plugin";\n' > build/sites-vite-plugin.ts`.
- **Local D1 has no migrations applied, but the app self-heals:** the beta API
  (`app/api/beta/route.ts`) calls `ensureBetaSignupsTable()` (`CREATE TABLE IF
  NOT EXISTS`) before inserting, so beta signups work against a fresh local
  Miniflare D1 without running `db:generate`/migrations. Local D1 state persists
  under `landing/.wrangler/`.
- **Beta form `useCase` is a fixed enum:** valid values are `backups`,
  `photo-video`, `development`, `general-storage`, `other` (see `db/beta-signups.ts`).
- **Local ChatGPT sign-in is mocked** by the `sites()` plugin: visit
  `/signin-with-chatgpt?return_to=/` to sign in as `seedy@sites.test`
  (`/signout-with-chatgpt` to sign out).
- **Admin dashboard needs secrets:** `/admin` additionally requires the Worker
  env vars `SSD_REMOVER_ADMIN_PASSWORD` and `SSD_REMOVER_ADMIN_SESSION_SECRET`
  (plus a signed-in ChatGPT user). Provide them via a `landing/.dev.vars` file
  for local admin testing; they are not needed for the public landing page or
  beta signup flow.
