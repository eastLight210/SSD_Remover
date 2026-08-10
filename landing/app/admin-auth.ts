import { env } from "cloudflare:workers";
import { redirect } from "next/navigation";
import { getChatGPTUser, requireChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";

function configuredAdminEmail(): string | null {
  const value = (env as unknown as { SSD_REMOVER_ADMIN_EMAIL?: string }).SSD_REMOVER_ADMIN_EMAIL;
  return value?.trim().toLowerCase() || null;
}

function isConfiguredAdmin(user: ChatGPTUser): boolean {
  const adminEmail = configuredAdminEmail();
  return adminEmail !== null && user.email.trim().toLowerCase() === adminEmail;
}

export async function requireAdminUser(returnTo: string): Promise<ChatGPTUser> {
  const user = await requireChatGPTUser(returnTo);
  if (!isConfiguredAdmin(user)) redirect("/");
  return user;
}

export async function getAdminUser(): Promise<ChatGPTUser | null> {
  const user = await getChatGPTUser();
  return user && isConfiguredAdmin(user) ? user : null;
}
