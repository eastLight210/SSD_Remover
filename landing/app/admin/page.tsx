import Link from "next/link";
import { requireAdminUser } from "../admin-auth";
import {
  ensureBetaSignupsTable,
  getBetaSignupStats,
  isUseCase,
  listBetaSignups,
  USE_CASES,
  type UseCase,
} from "../../db/beta-signups";

export const dynamic = "force-dynamic";

type AdminSearchParams = Promise<{
  q?: string | string[];
  useCase?: string | string[];
}>;

const useCaseLabels: Record<UseCase, string> = {
  backups: "Backups",
  "photo-video": "Photo & video",
  development: "Development",
  "general-storage": "General storage",
  other: "Other",
};

const dateFormatter = new Intl.DateTimeFormat("en", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Seoul",
});

function firstValue(value: string | string[] | undefined): string {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function formatDate(value: number | null): string {
  return value === null ? "—" : dateFormatter.format(new Date(value));
}

export default async function AdminPage({ searchParams }: { searchParams: AdminSearchParams }) {
  const user = await requireAdminUser("/admin");
  const params = await searchParams;
  const query = firstValue(params.q).trim();
  const requestedUseCase = firstValue(params.useCase);
  const useCase = isUseCase(requestedUseCase) ? requestedUseCase : undefined;

  await ensureBetaSignupsTable();
  const [signups, stats] = await Promise.all([
    listBetaSignups({ query, useCase }),
    getBetaSignupStats(),
  ]);

  const exportParams = new URLSearchParams();
  if (query) exportParams.set("q", query);
  if (useCase) exportParams.set("useCase", useCase);
  const exportHref = `/api/admin/signups/export${exportParams.size ? `?${exportParams}` : ""}`;

  return (
    <main className="admin-main">
      <header className="admin-header">
        <Link className="brand" href="/" aria-label="SSD Remover landing page">
          <span className="brand-mark" aria-hidden="true"><span /></span>
          <span>SSD Remover</span>
        </Link>
        <div className="admin-account">
          <span>{user.email}</span>
          <form action="/api/admin/logout" method="post"><button type="submit">Sign out</button></form>
        </div>
      </header>

      <section className="admin-content">
        <div className="admin-title-row">
          <div>
            <p className="eyebrow"><span /> Private beta</p>
            <h1>Beta signups</h1>
            <p>Review the people who asked to try SSD Remover.</p>
          </div>
          <a className="button button-secondary admin-export" href={exportHref}>Download CSV</a>
        </div>

        <div className="admin-stats" aria-label="Signup summary">
          <article><span>Total signups</span><strong>{stats.total}</strong><small>All time</small></article>
          <article><span>Last 7 days</span><strong>{stats.recent}</strong><small>New interest</small></article>
          <article><span>Latest signup</span><strong className="admin-date-stat">{formatDate(stats.latest)}</strong><small>Asia/Seoul</small></article>
        </div>

        <section className="admin-panel" aria-labelledby="signup-list-heading">
          <div className="admin-panel-heading">
            <div>
              <h2 id="signup-list-heading">Applicants</h2>
              <p>{signups.length} matching {signups.length === 1 ? "signup" : "signups"}</p>
            </div>
            <form className="admin-filters" method="get">
              <label>
                <span className="sr-only">Search by email</span>
                <input type="search" name="q" placeholder="Search email" defaultValue={query} />
              </label>
              <label>
                <span className="sr-only">Filter by drive use case</span>
                <select name="useCase" defaultValue={useCase ?? ""}>
                  <option value="">All use cases</option>
                  {USE_CASES.map((option) => <option key={option} value={option}>{useCaseLabels[option]}</option>)}
                </select>
              </label>
              <button type="submit">Filter</button>
              {(query || useCase) && <Link href="/admin">Reset</Link>}
            </form>
          </div>

          <div className="admin-use-cases" aria-label="Signups by use case">
            {USE_CASES.map((option) => (
              <span key={option}>{useCaseLabels[option]} <strong>{stats.byUseCase[option]}</strong></span>
            ))}
          </div>

          {signups.length ? (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead><tr><th>Email</th><th>Use case</th><th>Signed up</th><th>Source</th></tr></thead>
                <tbody>
                  {signups.map((signup) => (
                    <tr key={signup.id}>
                      <td><a href={`mailto:${signup.email}`}>{signup.email}</a></td>
                      <td><span className="admin-use-case">{useCaseLabels[signup.useCase]}</span></td>
                      <td>{formatDate(signup.createdAt)}</td>
                      <td>{signup.source}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="admin-empty">
              <strong>No matching signups</strong>
              <p>New beta requests will appear here automatically.</p>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}
