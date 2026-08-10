import { redirect } from "next/navigation";
import { getChatGPTUser, requireChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";
import { hasValidAdminSession, safeAdminReturnTo } from "./admin-session";

export async function requireAdminUser(returnTo: string): Promise<ChatGPTUser> {
  const user = await requireChatGPTUser(returnTo);
  if (!await hasValidAdminSession(user)) {
    redirect(`/admin/login?returnTo=${encodeURIComponent(safeAdminReturnTo(returnTo))}`);
  }
  return user;
}

export async function getAdminUser(): Promise<ChatGPTUser | null> {
  const user = await getChatGPTUser();
  return user && await hasValidAdminSession(user) ? user : null;
}
