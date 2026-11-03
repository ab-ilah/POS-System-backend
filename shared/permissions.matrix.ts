/**
 * Staff permission matrix for the clothing-store POS.
 *
 * This module is dependency-free on purpose. The React app in ab-ilah/POS-system-
 * should consume `PERMISSIONS_MATRIX` (each row has `decision`: 'allow' | 'deny').
 * Publish it as `@pos/permissions` and pin the version. A copied file must record
 * the backend git SHA. After this shape change, the frontend pin has to be re-synced.
 *
 * Adding a role: extend `ROLES`, add a block in `ACCESS`, add a seed user, and
 * add matching policies. The booleans are table-level. Row scope that a boolean
 * cannot express is in `PERMISSION_SCOPE_NOTES` and enforced in the SQL policies.
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

export type Decision = "allow" | "deny";

export interface PermissionRow {
  role: Role;
  table: TableName;
  operation: Operation;
  decision: Decision;
}

const ACCESS: {
  readonly [R in Role]: {
    readonly [T in TableName]: {
      readonly [O in Operation]: Decision;
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
    "A new auth user has a profile and no role, so RLS allows nothing until an owner or manager assigns one. Cashier select and update apply only to that cashier's own row. A manager cannot edit an owner. Nobody inserts profiles through the API.",
  products: "Owner and manager maintain the catalogue. Cashiers can read it at the till.",
  product_variants:
    "Same catalogue rules as products. Shelf prices are integers in pesewas and already include tax.",
  customers:
    "Cashiers can register a customer and update name and phone. Only the owner can change credit_balance_pesewas. Cashiers cannot delete a customer.",
  sales:
    "Any staff member can record a sale attributed to themselves. Owner and manager can void a sale (status, void reason, void timestamp). Amounts and the rest of the row are immutable. Nobody deletes a sale.",
  sale_items:
    "A line can be inserted only on a sale whose cashier is the signed-in staff member. Lines are then immutable. Corrections are a void plus a new sale.",
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
          decision: ACCESS[role][table][operation],
        });
      }
    }
  }
  return rows;
}

export const PERMISSIONS_MATRIX: readonly PermissionRow[] = flatten();

export function decisionFor(role: Role, table: TableName, operation: Operation): Decision {
  const row = PERMISSIONS_MATRIX.find(
    (candidate) => candidate.role === role && candidate.table === table && candidate.operation === operation,
  );
  if (!row) {
    throw new Error(`missing permission row ${role} ${table} ${operation}`);
  }
  return row.decision;
}
