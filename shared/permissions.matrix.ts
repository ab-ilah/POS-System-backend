/**
 * Staff permission matrix for the clothing-store POS.
 *
 * The React app imports this file directly (`shared/permissions.matrix.ts`).
 * Keep it self-contained: no imports. The names it relies on are
 * `PERMISSIONS_MATRIX` (rows with `decision`), `ROLES`, and the types
 * `Role`, `TableName`, `Operation`, `Decision`, and `PermissionRow`.
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
    "Cashiers can register a customer at a zero credit balance and update name and phone. Only an authenticated owner can set or change credit_balance_pesewas. A service-role JWT is denied even when its subject is the owner. Cashiers cannot delete a customer.",
  sales:
    "Any staff member can record a sale attributed to themselves. An authenticated owner or manager can complete an open sale or void a sale. Amounts stay immutable. Once a sale is voided, every update is rejected. Nobody deletes a sale.",
  sale_items:
    "A line can be inserted only on an open sale whose cashier is the signed-in staff member. Completed and voided sales reject new lines, line edits, line deletes, and moving a line to another sale. Corrections are a void plus a new sale.",
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
