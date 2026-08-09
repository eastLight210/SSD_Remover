import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("landing source keeps the beta funnel and proof artifact intact", async () => {
  const [page, layout, css, form, route, schema, hosting] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("app/globals.css", root), "utf8"),
    readFile(new URL("app/components/BetaSignupForm.tsx", root), "utf8"),
    readFile(new URL("app/api/beta/route.ts", root), "utf8"),
    readFile(new URL("db/schema.ts", root), "utf8"),
    readFile(new URL(".openai/hosting.json", root), "utf8"),
  ]);

  assert.match(page, /Find what&apos;s holding your drive/);
  assert.match(page, /ssd-remover-demo\.gif/);
  assert.match(page, /Join the private beta/);
  assert.match(page, /Runs locally/);
  assert.match(layout, /SSD Remover — Find the blocker/);
  assert.match(layout, /\/og\.png/);
  assert.match(form, /autoComplete="email"/);
  assert.match(form, /aria-live="polite"/);
  assert.match(route, /ON CONFLICT\(email\)/);
  assert.match(schema, /beta_signups/);
  const hostingConfig = JSON.parse(hosting);
  assert.equal(hostingConfig.d1, "DB");
  assert.equal(hostingConfig.r2, null);
  assert.match(hostingConfig.project_id, /^appgprj_/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--color-bg-accent:/);
});

test("does not ship the disposable Sites starter", async () => {
  const page = await readFile(new URL("app/page.tsx", root), "utf8");
  assert.doesNotMatch(page, /SkeletonPreview|codex-preview|Your site is taking shape/);
});
