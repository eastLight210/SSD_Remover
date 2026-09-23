import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("landing source keeps the download, signup, and proof artifact intact", async () => {
  const [page, layout, css, form, route, signupStore, schema, wrangler] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("app/globals.css", root), "utf8"),
    readFile(new URL("app/components/BetaSignupForm.tsx", root), "utf8"),
    readFile(new URL("app/api/beta/route.ts", root), "utf8"),
    readFile(new URL("db/beta-signups.ts", root), "utf8"),
    readFile(new URL("db/schema.ts", root), "utf8"),
    readFile(new URL("wrangler.jsonc", root), "utf8"),
  ]);

  assert.match(page, /Find what&apos;s holding your drive/);
  assert.match(page, /ssd-remover-demo\.gif/);
  assert.match(page, /releases\/latest\/download\/SSD_Remover\.zip/);
  assert.match(page, /Download for macOS/);
  assert.match(form, /Get release updates/);
  assert.match(page, /Runs locally/);
  assert.match(layout, /SSD Remover — Find the blocker/);
  assert.match(layout, /https:\/\/ssdremover\.badgerworks\.dev/);
  assert.match(layout, /\/og\.png/);
  assert.match(form, /autoComplete="email"/);
  assert.match(form, /aria-live="polite"/);
  assert.match(route, /upsertBetaSignup/);
  assert.match(signupStore, /ON CONFLICT\(email\)/);
  assert.match(schema, /beta_signups/);
  assert.match(wrangler, /"binding": "DB"/);
  assert.match(wrangler, /"pattern": "ssdremover\.badgerworks\.dev", "custom_domain": true/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--color-bg-accent:/);
});

test("admin signups require a verified Cloudflare Access identity and provide a protected CSV export", async () => {
  const [adminPage, adminAuth, accessAuth, exportRoute, wrangler] = await Promise.all([
    readFile(new URL("app/admin/page.tsx", root), "utf8"),
    readFile(new URL("app/admin-auth.ts", root), "utf8"),
    readFile(new URL("app/access-auth.ts", root), "utf8"),
    readFile(new URL("app/api/admin/signups/export/route.ts", root), "utf8"),
    readFile(new URL("wrangler.jsonc", root), "utf8"),
  ]);

  assert.match(adminPage, /requireAdminUser\(\)/);
  assert.match(adminPage, /Download CSV/);
  assert.match(adminPage, /export const dynamic = "force-dynamic"/);
  assert.match(adminAuth, /getAccessUser/);
  assert.match(adminAuth, /notFound\(\)/);
  assert.match(accessAuth, /cf-access-jwt-assertion/);
  assert.match(accessAuth, /cdn-cgi\/access\/certs/);
  assert.match(accessAuth, /RSASSA-PKCS1-v1_5/);
  assert.match(accessAuth, /ADMIN_EMAILS/);
  assert.match(wrangler, /"CF_ACCESS_AUD"/);
  assert.match(exportRoute, /getAdminUser/);
  assert.match(exportRoute, /Content-Disposition/);
  assert.match(exportRoute, /Cache-Control.*private, no-store/s);
});

test("does not ship the disposable Sites starter", async () => {
  const page = await readFile(new URL("app/page.tsx", root), "utf8");
  assert.doesNotMatch(page, /SkeletonPreview|codex-preview|Your site is taking shape/);
});

test("publishes crawl discovery files for the canonical domain", async () => {
  const [robots, sitemap] = await Promise.all([
    readFile(new URL("public/robots.txt", root), "utf8"),
    readFile(new URL("public/sitemap.xml", root), "utf8"),
  ]);

  assert.match(robots, /^User-agent: \*$/m);
  assert.match(robots, /^Allow: \/$/m);
  assert.match(robots, /^Sitemap: https:\/\/ssdremover\.badgerworks\.dev\/sitemap\.xml$/m);
  assert.match(sitemap, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
  assert.match(sitemap, /<loc>https:\/\/ssdremover\.badgerworks\.dev\/<\/loc>/);
});
