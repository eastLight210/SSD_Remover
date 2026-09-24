# AGENTS.md

## Cursor Cloud specific instructions

This repository contains two independent products:

- `SSD_Remover/` — a native macOS menu bar app (SwiftUI, Swift 6.2, Xcode 26).
  It depends on Xcode and macOS-only frameworks, so it **cannot be built, run, or
  tested on the Linux Cloud Agent VM**. Build/test it on macOS per `README.md`
  (`xcodegen generate`, then `xcodebuild test -scheme SSD_Remover -destination 'platform=macOS'`).
- `landing/` — the public landing page (Next.js on Vite via `vinext`, React 19,
  Tailwind, Cloudflare Workers/Wrangler). It has no database, forms, or admin
  area; the app updates itself via Sparkle, so no mailing list is needed.
  This is the only part that runs on the Linux Cloud VM.

### landing service (the runnable product here)

Standard commands live in `landing/package.json` and `landing/README.md`. Run
them from the `landing/` directory:

- Dev server: `npm run dev` → serves `http://localhost:3000/` (a long-running
  process; run it in a dedicated tmux terminal, not via the update script).
- Lint: `npm run lint`
- Build + regression tests: `npm test` (runs `vinext build` then
  `node --test tests/rendered-html.test.mjs`).
