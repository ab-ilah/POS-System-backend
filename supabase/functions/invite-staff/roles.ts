/** Roles that invite-staff may assign. Owners are created only via bootstrap. */
export const INVITABLE_STAFF_ROLES = new Set(["manager", "cashier"]);

export function isInvitableStaffRole(role: string): boolean {
  return INVITABLE_STAFF_ROLES.has(role);
}
