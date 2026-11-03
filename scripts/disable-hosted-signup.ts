/**
 * Turns off public signup on one hosted Supabase project.
 * Call this only from the deploy workflow. It never runs during tests.
 * The auth config response can contain provider secrets, so this script
 * prints status only.
 */

export const DISABLE_SIGNUP_BODY = { disable_signup: true } as const;

const REF_PATTERN = /^[a-z]{20}$/;

export function authConfigUrl(projectRef: string): string {
  if (!REF_PATTERN.test(projectRef)) {
    throw new Error("SUPABASE_PROJECT_REF must be a 20 character project ref");
  }
  return `https://api.supabase.com/v1/projects/${projectRef}/config/auth`;
}

export async function disableHostedSignup(fetchImpl: typeof fetch = fetch): Promise<void> {
  const token = process.env["SUPABASE_ACCESS_TOKEN"];
  const projectRef = process.env["SUPABASE_PROJECT_REF"];
  if (!token || !projectRef) {
    console.error("SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF are required");
    process.exit(1);
  }
  const response = await fetchImpl(authConfigUrl(projectRef), {
    method: "PATCH",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(DISABLE_SIGNUP_BODY),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error(`auth config update failed with status ${String(response.status)}`);
    process.exit(1);
  }
  let body: unknown;
  try {
    body = JSON.parse(text) as unknown;
  } catch {
    console.error("auth config update returned a body that was not JSON");
    process.exit(1);
  }
  const disabled =
    typeof body === "object" &&
    body !== null &&
    "disable_signup" in body &&
    (body as { disable_signup?: unknown }).disable_signup === true;
  if (!disabled) {
    console.error("hosted signup is still enabled");
    process.exit(1);
  }
  console.log(`signup disabled on ${projectRef}`);
}

const invokedDirectly = process.argv[1]?.endsWith("disable-hosted-signup.ts") === true;
if (invokedDirectly) {
  await disableHostedSignup();
}
