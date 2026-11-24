import { isInvitableStaffRole } from "./roles.ts";

/** Maps invite payload role to an early HTTP error, if any. */
export function inviteRoleHttpError(role: string): { status: number; error: string } | null {
  const trimmed = role.trim();
  if (!trimmed) {
    return null;
  }
  if (!isInvitableStaffRole(trimmed)) {
    return { status: 400, error: "invalid_role" };
  }
  return null;
}