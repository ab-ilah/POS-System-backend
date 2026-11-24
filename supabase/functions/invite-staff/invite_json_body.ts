export type InviteBody = {
  email?: string;
  full_name?: string;
  role?: string;
};

/** Returns null when the parsed JSON is not a plain object (null, array, primitive). */
export function parseInviteJsonBody(raw: unknown): InviteBody | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }
  return raw as InviteBody;
}