# SSD Remover landing page

Private-beta landing page for SSD Remover, built with vinext and OpenAI Sites.

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

## Beta signups

The signup form posts to `/api/beta` and stores email addresses plus drive use
cases in the `beta_signups` D1 table. The binding name is declared in
`.openai/hosting.json`; schema changes belong in `db/schema.ts` and require a
new migration:

```bash
npm run db:generate
```

The app itself inspects processes and file paths locally. The landing form is a
separate beta-invitation surface and stores only the fields disclosed beside
the form.
