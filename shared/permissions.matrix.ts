/**
 * Staff permission matrix for the clothing-store POS.
 *
 * This module is dependency-free on purpose. The React app in ab-ilah/POS-system-
 * should consume it as a versioned package (recommended name `@pos/permissions`)
 * that re-exports this file, and should pin the version. A hand-copied file will
 * drift from the RLS tests in this repo. Copying `shared/permissions.matrix.ts`
 * and recording the backend git SHA is only a bridge until that package exists.
 *
 * Adding a role: extend `ROLES`, add a block in `ACCESS`, add a seed user, and
 * add matching policies. `PERMISSIONS` is one row per role x table x operation.
 * The booleans are table-level. Row scope that a boolean cannot express is in
 * `PERMISSION_SCOPE_NOTES` and enforced in the SQL policies.
 */

export const ROLES = ["owner", "manager", "cashier"] as const;
export type Role = (typeof ROLES)[number];

export const TABLES = [
  "profiles",
  "products",
  "product_variants",
  "customers",
  "sales",
  "sale_items",
] as const;
export type TableName = (typeof TABLES)[number];

export const OPERATIONS = ["select", "insert", "update", "delete"] as const;
export type Operation = (typeof OPERATIONS)[number];

export type Access = "allow" | "deny";

export interface PermissionRow {
  role: Role;
  table: TableName;
  operation: Operation;
  access: Access;
}

const ACCESS: {
  readonly [R in Role]: {
    readonly [T in TableName]: {
      readonly [O in Operation]: Access;
    };
  };
} = {
  owner: {
    profiles: { select: "allow", insert: "deny", update: "allow", delete: "allow" },
    products: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    product_variants: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    customers: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    sales: { select: "allow", insert: "allow", update: "allow", delete: "deny" },
    sale_items: { select: "allow", insert: "allow", update: "deny", delete: "deny" },
  },
  manager: {
    profiles: { select: "allow", insert: "deny", update: "allow", delete: "deny" },
    products: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    product_variants: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    customers: { select: "allow", insert: "allow", update: "allow", delete: "allow" },
    sales: { select: "allow", insert: "allow", update: "allow", delete: "deny" },
    sale_items: { select: "allow", insert: "allow", update: "deny", delete: "deny" },
  },
  cashier: {
    profiles: { select: "allow", insert: "deny", update: "allow", delete: "deny" },
    products: { select: "allow", insert: "deny", update: "deny", delete: "deny" },
    product_variants: { select: "allow", insert: "deny", update: "deny", delete: "deny" },
    customers: { select: "allow", insert: "allow", update: "allow", delete: "deny" },
    sales: { select: "allow", insert: "allow", update: "deny", delete: "deny" },
    sale_items: { select: "allow", insert: "allow", update: "deny", delete: "deny" },
  },
};

export const PERMISSION_SCOPE_NOTES: Readonly<Record<TableName, string>> = {
  profiles:
    "Cashier select and update apply only to that cashier's own row. A manager cannot edit an owner and cannot change any role. Only the owner can change roles or delete a profile. No role may insert profiles through the API. The auth trigger creates each profile as cashier.",
  products: "Owner and manager maintain the catalogue. Cashiers can read it at the till.",
  product_variants:
    "Same catalogue rules as products. Shelf prices are integers in pesewas and already include tax.",
  customers:
    "Cashiers can register a customer and update the record, including the amount owed. They cannot delete a customer.",
  sales:
    "Any staff member can record a sale attributed to themselves. Owner and manager can void a sale. Nobody deletes a sale.",
  sale_items: "Lines are written with the sale and are then immutable. Corrections are a void plus a new sale.",
};

function flatten(): readonly PermissionRow[] {
  const rows: PermissionRow[] = [];
  for (const role of ROLES) {
    for (const table of TABLES) {
      for (const operation of OPERATIONS) {
        rows.push({
          role,
          table,
          operation,
          access: ACCESS[role][table][operation],
        });
      }
    }
  }
  return rows;
}

export const PERMISSIONS: readonly PermissionRow[] = flatten();

export function accessFor(role: Role, table: TableName, operation: Operation): Access {
  return ACCESS[role][table][operation];
}
