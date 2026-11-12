import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { createClient } from "@supabase/supabase-js";

const runCommitSaleApi = process.env["RUN_COMMIT_SALE_API"] === "1";

const apiUrl = (process.env["SUPABASE_URL"] ?? process.env["API_URL"] ?? "http://127.0.0.1:54321").replace(
  /\/$/,
  "",
);

function requireServiceRoleKey(): string {
  const key = process.env["SUPABASE_SERVICE_ROLE_KEY"] ?? process.env["SERVICE_ROLE_KEY"];
  if (!key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY or SERVICE_ROLE_KEY must be set (supabase status -o env).");
  }
  return key;
}

describe.skipIf(!runCommitSaleApi)("Auth admin API email uniqueness", () => {
  it("rejects creating A@x.com after a@x.com", async () => {
    const admin = createClient(apiUrl, requireServiceRoleKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const tag = randomUUID().slice(0, 8);
    const base = `pgtap-case-${tag}@x.com`;
    const { error: firstError } = await admin.auth.admin.createUser({
      email: base.toLowerCase(),
      email_confirm: true,
      password: "Passw0rd!local",
    });
    expect(firstError).toBeNull();

    const { error: duplicateError } = await admin.auth.admin.createUser({
      email: base.toUpperCase(),
      email_confirm: true,
      password: "Passw0rd!local",
    });
    expect(duplicateError).not.toBeNull();
  });
});
