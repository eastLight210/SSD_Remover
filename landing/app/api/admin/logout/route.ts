import { clearAdminSessionCookie } from "../../../admin-session";

export async function POST(request: Request) {
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin) return new Response("Forbidden", { status: 403 });

  return new Response(null, {
    status: 303,
    headers: {
      "Cache-Control": "private, no-store",
      Location: new URL("/", request.url).toString(),
      "Set-Cookie": clearAdminSessionCookie(),
    },
  });
}
