import { describe, expect, it } from "vitest";
import { createClient } from "@supabase/supabase-js";

const runSignupCheck = process.env["RUN_AUTH_SIGNUP_CHECK"] === "1";

const apiUrl = (process.env["SUPABASE_URL"] ?? process.env["API_URL"] ?? "http://127.0.0.1:54321").replace(
  /\/$/,
  "",
);

function requireAnonKey(): string {
  const key = process.env["SUPABASE_ANON_KEY"] ?? process.env["ANON_KEY"];
  if (!key) {
    throw new Error("SUPABASE_ANON_KEY or ANON_KEY must be set");
  }
  return key;
}

describe.skipIf(!runSignupCheck)("hosted signup disabled locally", () => {
  it("rejects auth.signUp", async () => {
    const client = createClient(apiUrl, requireAnonKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await client.auth.signUp({
      email: `reject-${crypto.randomUUID()}@example.com`,
      password: "Passw0rd!local",
    });
    expect(error).not.toBeNull();
    expect(error?.message).toMatch(/signups not allowed/i);
  });
});
