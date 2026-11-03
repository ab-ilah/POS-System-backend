import { describe, expect, it } from "vitest";
import {
  OPERATIONS,
  PERMISSIONS,
  ROLES,
  TABLES,
  accessFor,
  type Role,
} from "../shared/permissions.matrix.ts";
import { USERS } from "../supabase/seed/catalog.ts";

describe("permission matrix", () => {
  it("has one row for every role, table, and operation", () => {
    expect(PERMISSIONS).toHaveLength(ROLES.length * TABLES.length * OPERATIONS.length);
    const keys = PERMISSIONS.map((row) => `${row.role}:${row.table}:${row.operation}`);
    expect(new Set(keys).size).toBe(keys.length);
    for (const role of ROLES) {
      for (const table of TABLES) {
        for (const operation of OPERATIONS) {
          const row = PERMISSIONS.find(
            (candidate) =>
              candidate.role === role && candidate.table === table && candidate.operation === operation,
          );
          expect(row?.access).toBe(accessFor(role, table, operation));
        }
      }
    }
  });

  it("only uses allow or deny", () => {
    for (const row of PERMISSIONS) {
      expect(["allow", "deny"]).toContain(row.access);
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
      accessFor("cashier" satisfies Role, table, operation);
    expect(cashier("products", "insert")).toBe("deny");
    expect(cashier("products", "update")).toBe("deny");
    expect(cashier("products", "delete")).toBe("deny");
    expect(cashier("sales", "insert")).toBe("allow");
    expect(cashier("sales", "update")).toBe("deny");
    expect(cashier("sales", "delete")).toBe("deny");
    expect(cashier("sale_items", "update")).toBe("deny");
  });
});
