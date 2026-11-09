import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { ROLES, TABLES } from "../shared/permissions.matrix.ts";

const migration = readdirSync("supabase/migrations")
  .sort()
  .map((name) => readFileSync(join("supabase/migrations", name), "utf8"))
  .join("\n");
const config = readFileSync("supabase/config.toml", "utf8");
const lowered = migration.toLowerCase();

describe("schema", () => {
  it("enables row level security on every application table", () => {
    for (const table of TABLES) {
      expect(lowered).toContain(`alter table public.${table} enable row level security`);
    }
  });

  it("defines the same roles as the matrix", () => {
    const match = migration.match(/create type public\.app_role as enum \(([^)]+)\)/);
    expect(match?.[1]?.split(",").map((part) => part.trim().replaceAll("'", ""))).toEqual([...ROLES]);
  });

  it("stores amounts as integers and has no fractional or card columns", () => {
    expect(lowered).not.toMatch(/\b(double precision|real|numeric|decimal|float4|float8|bytea)\b/);
    expect(lowered).toContain("price_pesewas integer");
    expect(lowered).toContain("credit_balance_pesewas integer");
    expect(lowered).toContain("total_pesewas integer");
    expect(lowered).not.toMatch(/\b(card_number|pan|cvv)\b/);
  });

  it("does not grant a role on signup and does not expose profile_role", () => {
    expect(migration).not.toContain("default 'cashier'");
    expect(migration).not.toContain("private.profile_role");
    expect(migration).toContain("raw_app_meta_data ->> 'role'");
    expect(migration).toContain("assign_staff_role");
    expect(migration).toContain("current_user = 'authenticated'");
    expect(migration).toContain("auth.jwt() ->> 'role'");
    expect(migration).toContain("current_user = session_user");
    expect(migration).not.toContain("app.seed");
    expect(migration).toContain("revoke all on function private.staff_role(uuid) from public, anon, authenticated");
  });

  it("revokes anon and keeps the private schema off the data API", () => {
    expect(lowered).toContain("revoke all on table");
    expect(lowered).toContain("from anon, public");
    expect(config).toContain('schemas = ["public", "graphql_public"]');
    expect(config).not.toMatch(/schemas\s*=\s*\[[^\]]*private/);
    expect(config).toContain("enable_signup = false");
  });
});
