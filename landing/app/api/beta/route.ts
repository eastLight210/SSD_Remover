import { ensureBetaSignupsTable, isUseCase, upsertBetaSignup } from "../../../db/beta-signups";

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { email?: unknown; useCase?: unknown; company?: unknown };
    if (typeof body.company === "string" && body.company.trim()) {
      return Response.json({ message: "You’re on the update list." });
    }

    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const useCase = typeof body.useCase === "string" ? body.useCase.trim() : "";
    if (!emailPattern.test(email)) {
      return Response.json({ message: "Enter a valid email address." }, { status: 400 });
    }
    if (!isUseCase(useCase)) {
      return Response.json({ message: "Choose how you use external drives." }, { status: 400 });
    }

    await ensureBetaSignupsTable();
    await upsertBetaSignup(email, useCase);

    return Response.json({ message: "You’re on the update list. I’ll email you when a new version ships." });
  } catch {
    return Response.json({ message: "Could not save your request. Please try again." }, { status: 500 });
  }
}
