import { getAdminUser } from "../../../../admin-auth";
import {
  ensureBetaSignupsTable,
  isUseCase,
  listBetaSignups,
  type BetaSignup,
} from "../../../../../db/beta-signups";

export const dynamic = "force-dynamic";

function csvCell(value: string | number): string {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function toCsvRow(signup: BetaSignup): string {
  return [
    signup.email,
    signup.useCase,
    signup.source,
    new Date(signup.createdAt).toISOString(),
    new Date(signup.updatedAt).toISOString(),
  ].map(csvCell).join(",");
}

export async function GET(request: Request) {
  const admin = await getAdminUser();
  if (!admin) return new Response("Forbidden", { status: 403 });

  const url = new URL(request.url);
  const query = url.searchParams.get("q")?.trim() || undefined;
  const requestedUseCase = url.searchParams.get("useCase") ?? "";
  const useCase = isUseCase(requestedUseCase) ? requestedUseCase : undefined;

  await ensureBetaSignupsTable();
  const signups = await listBetaSignups({ query, useCase }, 5000);
  const header = ["email", "use_case", "source", "created_at", "updated_at"].map(csvCell).join(",");
  const csv = `\uFEFF${[header, ...signups.map(toCsvRow)].join("\r\n")}`;
  const date = new Date().toISOString().slice(0, 10);

  return new Response(csv, {
    headers: {
      "Cache-Control": "private, no-store",
      "Content-Disposition": `attachment; filename="ssd-remover-beta-signups-${date}.csv"`,
      "Content-Type": "text/csv; charset=utf-8",
    },
  });
}
