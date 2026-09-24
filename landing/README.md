# SSD Remover landing page

Landing page for SSD Remover, built with vinext and deployed to Cloudflare Workers
(`ssd-remover-landing`, served at https://ssdremover.badgerworks.dev).

## Local development

```bash
npm install
npm run dev
```

The development server runs at `http://localhost:3000`.

## Validation

```bash
npm run lint
npm test
```

`npm test` produces a production build and runs source-level regression tests.

## Deploy

```bash
npm run build
npx wrangler deploy
```

Worker name and custom domain live in `wrangler.jsonc`.

## Data

The site stores nothing: there is no signup form, database, or admin area.
New versions reach users through the app's built-in updater (Sparkle), and the
download button always points at the latest GitHub release.
