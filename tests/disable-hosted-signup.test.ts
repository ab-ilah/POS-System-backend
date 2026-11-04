import { describe, expect, it } from "vitest";
import { DISABLE_SIGNUP_BODY, authConfigUrl, disableHostedSignup } from "../scripts/disable-hosted-signup.ts";

describe("disable hosted signup", () => {
  it("patches only disable_signup on the named project", async () => {
    const previousToken = process.env["SUPABASE_ACCESS_TOKEN"];
    const previousRef = process.env["SUPABASE_PROJECT_REF"];
    process.env["SUPABASE_ACCESS_TOKEN"] = "test-token";
    process.env["SUPABASE_PROJECT_REF"] = "hnbvmxebzaocdttlteib";
    const calls: { url: string; method: string; body: string; authorization: string }[] = [];
    try {
      await disableHostedSignup(async (input, init) => {
        calls.push({
          url: String(input),
          method: init?.method ?? "",
          body: String(init?.body ?? ""),
          authorization: new Headers(init?.headers).get("authorization") ?? "",
        });
        return new Response(JSON.stringify({ disable_signup: true }), { status: 200 });
      });
    } finally {
      if (previousToken === undefined) delete process.env["SUPABASE_ACCESS_TOKEN"];
      else process.env["SUPABASE_ACCESS_TOKEN"] = previousToken;
      if (previousRef === undefined) delete process.env["SUPABASE_PROJECT_REF"];
      else process.env["SUPABASE_PROJECT_REF"] = previousRef;
    }
    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe(authConfigUrl("hnbvmxebzaocdttlteib"));
    expect(calls[0]?.method).toBe("PATCH");
    expect(calls[0]?.body).toBe(JSON.stringify(DISABLE_SIGNUP_BODY));
    expect(calls[0]?.authorization).toBe("Bearer test-token");
  });

  it("rejects a project ref that is not the hosted shape", () => {
    expect(() => authConfigUrl("not-a-ref")).toThrow(/project ref/);
  });
});
