import { notFound } from "next/navigation";
import { getAccessUser, type AccessUser } from "./access-auth";

export async function requireAdminUser(): Promise<AccessUser> {
  const user = await getAccessUser();
  if (!user) notFound();
  return user;
}

export async function getAdminUser(): Promise<AccessUser | null> {
  return getAccessUser();
}
