/**
 * Read-only check that hosted signup is disabled on a Supabase project.
 * Used from keepalive (weekly). Requires a read-scoped platform token.
 */

import { authConfigUrl } from "./disable-hosted-signup.ts";

export async function assertHostedSignupDisabled(fetchImpl: typeof fetch = fetch): Promise<void> {
  const token = process.env["SUPABASE_AUTH_CONFIG_READ_TOKEN"];
  const projectRef = process.env["SUPABASE_PROJECT_REF"];
  if (!token) {
    console.error(
      "SUPABASE_AUTH_CONFIG_READ_TOKEN is required. Add a read-scoped Supabase access token to this GitHub environment.",
    );
    process.exit(1);
  }
  if (!projectRef) {
    console.error("SUPABASE_PROJECT_REF is required");
    process.exit(1);
  }
  const response = await fetchImpl(authConfigUrl(projectRef), {
    method: "GET",
    headers: {
      authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    console.error(`auth config read failed with status ${String(response.status)}`);
    process.exit(1);
  }
  let body: unknown;
  try {
    body = JSON.parse(await response.text()) as unknown;
  } catch {
    console.error("auth config read returned a body that was not JSON");
    process.exit(1);
  }
  const disabled =
    typeof body === "object" &&
    body !== null &&
    "disable_signup" in body &&
    (body as { disable_signup?: unknown }).disable_signup === true;
  if (!disabled) {
    console.error(`hosted signup is still enabled on ${projectRef}`);
    process.exit(1);
  }
  console.log(`signup disabled on ${projectRef} (assert ok)`);
}

const invokedDirectly = process.argv[1]?.endsWith("assert-hosted-signup.ts") === true;
if (invokedDirectly) {
  await assertHostedSignupDisabled();
}
