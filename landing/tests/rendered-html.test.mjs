import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("landing source keeps the beta funnel and proof artifact intact", async () => {
  const [page, layout, css, form, route, signupStore, schema, hosting] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("app/globals.css", root), "utf8"),
    readFile(new URL("app/components/BetaSignupForm.tsx", root), "utf8"),
    readFile(new URL("app/api/beta/route.ts", root), "utf8"),
    readFile(new URL("db/beta-signups.ts", root), "utf8"),
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
  assert.match(route, /upsertBetaSignup/);
  assert.match(signupStore, /ON CONFLICT\(email\)/);
  assert.match(schema, /beta_signups/);
  const hostingConfig = JSON.parse(hosting);
  assert.equal(hostingConfig.d1, "DB");
  assert.equal(hostingConfig.r2, null);
  assert.match(hostingConfig.project_id, /^appgprj_/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--color-bg-accent:/);
});

test("admin signups stay owner-only and provide a protected CSV export", async () => {
  const [adminPage, adminAuth, chatGPTAuth, exportRoute] = await Promise.all([
    readFile(new URL("app/admin/page.tsx", root), "utf8"),
    readFile(new URL("app/admin-auth.ts", root), "utf8"),
    readFile(new URL("app/chatgpt-auth.ts", root), "utf8"),
    readFile(new URL("app/api/admin/signups/export/route.ts", root), "utf8"),
  ]);

  assert.match(adminPage, /requireAdminUser\("\/admin"\)/);
  assert.match(adminPage, /Download CSV/);
  assert.match(adminPage, /export const dynamic = "force-dynamic"/);
  assert.match(adminAuth, /SSD_REMOVER_ADMIN_EMAIL/);
  assert.match(adminAuth, /user\.email\.trim\(\)\.toLowerCase\(\) === adminEmail/);
  assert.match(chatGPTAuth, /oai-authenticated-user-id/);
  assert.match(exportRoute, /getAdminUser/);
  assert.match(exportRoute, /Content-Disposition/);
  assert.match(exportRoute, /Cache-Control.*private, no-store/s);
});

test("does not ship the disposable Sites starter", async () => {
  const page = await readFile(new URL("app/page.tsx", root), "utf8");
  assert.doesNotMatch(page, /SkeletonPreview|codex-preview|Your site is taking shape/);
});
