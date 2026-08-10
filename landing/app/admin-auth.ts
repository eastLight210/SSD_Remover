import { env } from "cloudflare:workers";
import { redirect } from "next/navigation";
import { getChatGPTUser, requireChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";

function configuredAdminUserId(): string | null {
  const value = (env as unknown as { SSD_REMOVER_ADMIN_USER_ID?: string }).SSD_REMOVER_ADMIN_USER_ID;
  return value?.trim() || null;
}

function isConfiguredAdmin(user: ChatGPTUser): boolean {
  const adminUserId = configuredAdminUserId();
  return adminUserId !== null && user.userId === adminUserId;
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
