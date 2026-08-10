import Link from "next/link";
import { redirect } from "next/navigation";
import { hasValidAdminSession, safeAdminReturnTo } from "../../admin-session";
import { requireChatGPTUser } from "../../chatgpt-auth";

export const dynamic = "force-dynamic";

type LoginSearchParams = Promise<{
  error?: string | string[];
  returnTo?: string | string[];
}>;

function firstValue(value: string | string[] | undefined): string {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function AdminLoginPage({ searchParams }: { searchParams: LoginSearchParams }) {
  const params = await searchParams;
  const returnTo = safeAdminReturnTo(firstValue(params.returnTo));
  const user = await requireChatGPTUser(`/admin/login?returnTo=${encodeURIComponent(returnTo)}`);
  if (await hasValidAdminSession(user)) redirect(returnTo);
  const hasError = firstValue(params.error) === "invalid";

  return (
    <main className="admin-login-main">
      <section className="admin-login-card">
        <Link className="brand" href="/" aria-label="SSD Remover landing page">
          <span className="brand-mark" aria-hidden="true"><span /></span>
          <span>SSD Remover</span>
        </Link>
        <p className="eyebrow"><span /> Owner access</p>
        <h1>Open beta admin</h1>
        <p className="admin-login-copy">Signed in as <strong>{user.email}</strong>. Enter the admin password to continue.</p>
        <form className="admin-login-form" action="/api/admin/login" method="post">
          <input type="hidden" name="returnTo" value={returnTo} />
          <label htmlFor="admin-password">Admin password</label>
          <input id="admin-password" name="password" type="password" autoComplete="current-password" required />
          {hasError && <p className="admin-login-error" role="alert">That password didn&apos;t match.</p>}
          <button className="button button-primary" type="submit">Continue to admin</button>
        </form>
        <Link className="text-link" href="/">Back to landing page</Link>
      </section>
    </main>
  );
}
