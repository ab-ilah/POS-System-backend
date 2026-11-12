import { describe, expect, it } from "vitest";
import { assertHostedSignupDisabled } from "../scripts/assert-hosted-signup.ts";
import { authConfigUrl } from "../scripts/disable-hosted-signup.ts";

describe("assert hosted signup", () => {
  it("GETs auth config and requires disable_signup", async () => {
    const previousToken = process.env["SUPABASE_AUTH_CONFIG_READ_TOKEN"];
    const previousRef = process.env["SUPABASE_PROJECT_REF"];
    process.env["SUPABASE_AUTH_CONFIG_READ_TOKEN"] = "read-token";
    process.env["SUPABASE_PROJECT_REF"] = "hnbvmxebzaocdttlteib";
    const calls: { url: string; method: string }[] = [];
    try {
      await assertHostedSignupDisabled(async (input, init) => {
        calls.push({ url: String(input), method: init?.method ?? "GET" });
        return new Response(JSON.stringify({ disable_signup: true }), { status: 200 });
      });
    } finally {
      if (previousToken === undefined) delete process.env["SUPABASE_AUTH_CONFIG_READ_TOKEN"];
      else process.env["SUPABASE_AUTH_CONFIG_READ_TOKEN"] = previousToken;
      if (previousRef === undefined) delete process.env["SUPABASE_PROJECT_REF"];
      else process.env["SUPABASE_PROJECT_REF"] = previousRef;
    }
    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe(authConfigUrl("hnbvmxebzaocdttlteib"));
    expect(calls[0]?.method).toBe("GET");
  });
});
