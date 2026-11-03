import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { ROLES, TABLES } from "../shared/permissions.matrix.ts";

const migration = readFileSync("supabase/migrations/20261103215722_init_pos.sql", "utf8");
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

  it("revokes anon and keeps the private schema off the data API", () => {
    expect(lowered).toContain("revoke all on table");
    expect(lowered).toContain("from anon, public");
    expect(config).toContain('schemas = ["public", "graphql_public"]');
    expect(config).not.toMatch(/schemas\s*=\s*\[[^\]]*private/);
    expect(config).toContain("enable_signup = false");
  });
});
