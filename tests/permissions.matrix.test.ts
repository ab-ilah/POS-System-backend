import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  OPERATIONS,
  PERMISSIONS_MATRIX,
  ROLES,
  TABLES,
  decisionFor,
  type Role,
} from "../shared/permissions.matrix.ts";
import { USERS } from "../supabase/seed/catalog.ts";

describe("permission matrix", () => {
  it("stays a self-contained module the frontend can import", () => {
    const source = readFileSync("shared/permissions.matrix.ts", "utf8");
    expect(source).not.toMatch(/^\s*import\s/m);
    expect(source).not.toMatch(/\bfrom\s+["']/);
    expect(source).toMatch(/^export const ROLES\b/m);
    expect(source).toMatch(/^export const PERMISSIONS_MATRIX\b/m);
    expect(source).toMatch(/^export type Role\b/m);
    expect(source).toMatch(/^export type TableName\b/m);
    expect(source).toMatch(/^export type Operation\b/m);
    expect(source).toMatch(/^export type Decision\b/m);
    expect(source).toMatch(/^export interface PermissionRow\b/m);
    for (const row of PERMISSIONS_MATRIX) {
      expect(Object.keys(row).sort()).toEqual(["decision", "operation", "role", "table"]);
    }
  });

  it("has one row for every role, table, and operation", () => {
    expect(PERMISSIONS_MATRIX).toHaveLength(ROLES.length * TABLES.length * OPERATIONS.length);
    const keys = PERMISSIONS_MATRIX.map((row) => `${row.role}:${row.table}:${row.operation}`);
    expect(new Set(keys).size).toBe(keys.length);
    for (const role of ROLES) {
      for (const table of TABLES) {
        for (const operation of OPERATIONS) {
          const row = PERMISSIONS_MATRIX.find(
            (candidate) =>
              candidate.role === role && candidate.table === table && candidate.operation === operation,
          );
          expect(row?.decision).toBe(decisionFor(role, table, operation));
        }
      }
    }
  });

  it("only uses allow or deny on decision", () => {
    for (const row of PERMISSIONS_MATRIX) {
      expect(["allow", "deny"]).toContain(row.decision);
      expect(row).not.toHaveProperty("access");
    }
  });

  it("keeps the baseline roles and has a seed user for each", () => {
    expect(ROLES).toEqual(["owner", "manager", "cashier"]);
    for (const role of ROLES) {
      expect(USERS.some((user) => user.role === role && !user.disposable)).toBe(true);
    }
  });

  it("does not let a cashier maintain the catalogue or void a sale", () => {
    const cashier = (table: (typeof TABLES)[number], operation: (typeof OPERATIONS)[number]) =>
      decisionFor("cashier" satisfies Role, table, operation);
    expect(cashier("products", "insert")).toBe("deny");
    expect(cashier("products", "update")).toBe("deny");
    expect(cashier("products", "delete")).toBe("deny");
    expect(cashier("sales", "insert")).toBe("allow");
    expect(cashier("sales", "update")).toBe("deny");
    expect(cashier("sales", "delete")).toBe("deny");
    expect(cashier("sale_items", "update")).toBe("deny");
  });
});
