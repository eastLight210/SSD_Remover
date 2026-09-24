import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("landing source keeps the download, update copy, and proof artifact intact", async () => {
  const [page, layout, css, wrangler] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("app/globals.css", root), "utf8"),
    readFile(new URL("wrangler.jsonc", root), "utf8"),
  ]);

  assert.match(page, /Find what&apos;s holding your drive/);
  assert.match(page, /ssd-remover-demo\.gif/);
  assert.match(page, /releases\/latest\/download\/SSD_Remover\.zip/);
  assert.match(page, /Download for macOS/);
  assert.match(page, /Automatic updates/);
  assert.match(page, /Runs locally/);
  assert.match(layout, /SSD Remover — Find the blocker/);
  assert.match(layout, /https:\/\/ssdremover\.badgerworks\.dev/);
  assert.match(layout, /\/og\.png/);
  assert.match(wrangler, /"pattern": "ssdremover\.badgerworks\.dev", "custom_domain": true/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--color-bg-accent:/);
});

test("collects no personal data: no signup form, admin area, or database", async () => {
  const [page, wrangler] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("wrangler.jsonc", root), "utf8"),
  ]);

  assert.doesNotMatch(page, /<form|type="email"|BetaSignupForm/);
  assert.doesNotMatch(wrangler, /d1_databases|CF_ACCESS/);
  await assert.rejects(access(new URL("app/api", root)));
  await assert.rejects(access(new URL("app/admin", root)));
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
