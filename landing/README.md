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

Worker name, custom domain, D1 binding, and Access settings live in
`wrangler.jsonc`. Apply new D1 migrations before deploying:

```bash
npx wrangler d1 migrations apply ssd-remover-landing --remote
```

## Release-update signups

The signup form posts to `/api/beta` and stores email addresses plus drive use
cases in the `beta_signups` D1 table. Schema changes belong in `db/schema.ts`
and require a new migration:

```bash
npm run db:generate
```

The app itself inspects processes and file paths locally. The landing form
stores only the fields disclosed beside the form.

## Admin

`/admin` and `/api/admin/*` are protected by the `ssdremover` Cloudflare Access
application (team `shy-tooth-8a67`). The Worker also verifies the Access JWT
(`app/access-auth.ts`) and only admits emails listed in `ADMIN_EMAILS`, so the
`*.workers.dev` URL cannot be used to bypass Access.
