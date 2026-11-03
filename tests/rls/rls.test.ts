import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  PERMISSIONS,
  type Access,
  type Operation,
  type Role,
  type TableName,
} from "../../shared/permissions.matrix.ts";
import { buildSeed, userForRole } from "../../supabase/seed/catalog.ts";

if (process.env["RUN_RLS"] !== "1") {
  throw new Error("RUN_RLS=1 is required. Use npm run test:rls after supabase db reset.");
}

const databaseUrl =
  process.env["DATABASE_URL"] ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

type Tx = TransactionSql<Record<string, never>>;

class RollbackSignal extends Error {
  constructor() {
    super("rollback");
    this.name = "RollbackSignal";
  }
}

function isDeny(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "42501"
  );
}

function verdict(count: number): Access {
  if (count === 1) return "allow";
  if (count === 0) return "deny";
  throw new Error(`expected 0 or 1 affected row, got ${String(count)}`);
}

const model = buildSeed();
let sql: ReturnType<typeof postgres>;

beforeAll(() => {
  sql = postgres(databaseUrl, { max: 1, prepare: false, connect_timeout: 20 });
});

afterAll(async () => {
  await sql.end({ timeout: 5 });
});

async function asUser<T>(userId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
  let value: T | undefined;
  let done = false;
  try {
    await sql.begin(async (tx) => {
      const claims = JSON.stringify({ sub: userId, role: "authenticated" });
      await tx`select set_config('request.jwt.claims', ${claims}, true)`;
      await tx`select set_config('request.jwt.claim.sub', ${userId}, true)`;
      await tx`select set_config('request.jwt.claim.role', ${"authenticated"}, true)`;
      await tx.unsafe("set local role authenticated");
      value = await fn(tx as unknown as Tx);
      done = true;
      throw new RollbackSignal();
    });
  } catch (error) {
    if (error instanceof RollbackSignal && done) {
      return value as T;
    }
    throw error;
  }
  throw new Error("transaction did not roll back");
}

async function selectCount(tx: Tx, table: TableName): Promise<number> {
  if (table === "profiles") {
    const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.profiles`;
    return Number(rows[0]?.n ?? 0);
  }
  if (table === "products") {
    const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.products`;
    return Number(rows[0]?.n ?? 0);
  }
  if (table === "product_variants") {
    const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.product_variants`;
    return Number(rows[0]?.n ?? 0);
  }
  if (table === "customers") {
    const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.customers`;
    return Number(rows[0]?.n ?? 0);
  }
  if (table === "sales") {
    const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.sales`;
    return Number(rows[0]?.n ?? 0);
  }
  const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.sale_items`;
  return Number(rows[0]?.n ?? 0);
}

async function insertProbe(tx: Tx, table: TableName): Promise<void> {
  if (table === "profiles") {
    await tx`
      insert into public.profiles (id, full_name, role)
      values ('55555555-5555-4555-8555-555555555555'::uuid, 'RLS Probe', 'cashier')
    `;
    return;
  }
  if (table === "products") {
    await tx`
      insert into public.products (name, category, description)
      values ('RLS Probe Shirt', 'shirts', 'probe')
    `;
    return;
  }
  if (table === "product_variants") {
    await tx`
      insert into public.product_variants (
        product_id, sku, size_name, colour_name, price_pesewas, stock_qty, low_stock_threshold
      ) values (
        ${model.targets.updateProductId}::uuid,
        'RLS-' || gen_random_uuid()::text,
        'M',
        'Probe Black',
        1000,
        1,
        5
      )
    `;
    return;
  }
  if (table === "customers") {
    await tx`
      insert into public.customers (full_name, phone, credit_balance_pesewas)
      values ('RLS Probe Customer', '0200999001', 0)
    `;
    return;
  }
  if (table === "sales") {
    await tx`
      insert into public.sales (
        receipt_no,
        customer_id,
        cashier_id,
        status,
        subtotal_pesewas,
        total_pesewas,
        tendered_pesewas,
        change_pesewas,
        credit_applied_pesewas
      ) values (
        'RLS-' || replace(gen_random_uuid()::text, '-', ''),
        null,
        (select auth.uid()),
        'completed',
        1000,
        1000,
        1000,
        0,
        0
      )
    `;
    return;
  }
  await tx`
    insert into public.sale_items (
      sale_id,
      variant_id,
      product_name,
      size_name,
      colour_name,
      qty,
      unit_price_pesewas,
      line_total_pesewas
    ) values (
      ${model.targets.probeSaleId}::uuid,
      ${model.targets.probeVariantId}::uuid,
      'RLS Probe',
      'L',
      'Crisp White',
      1,
      1000,
      1000
    )
  `;
}

async function updateProbe(tx: Tx, role: Role, table: TableName): Promise<number> {
  if (table === "profiles") {
    const target =
      role === "owner" ? userForRole("manager").id : userForRole("cashier").id;
    const result = await tx`
      update public.profiles
      set full_name = 'RLS Renamed'
      where id = ${target}::uuid
    `;
    return Number(result.count);
  }
  if (table === "products") {
    const result = await tx`
      update public.products
      set description = 'RLS probe update'
      where id = ${model.targets.updateProductId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "product_variants") {
    const result = await tx`
      update public.product_variants
      set stock_qty = stock_qty
      where id = ${model.targets.updateVariantId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "customers") {
    const result = await tx`
      update public.customers
      set phone = '0201111111'
      where id = ${model.targets.updateCustomerId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "sales") {
    const result = await tx`
      update public.sales
      set status = 'voided'
      where id = ${model.targets.updateSaleId}::uuid
    `;
    return Number(result.count);
  }
  const result = await tx`
    update public.sale_items
    set qty = qty
    where id = ${model.targets.updateSaleItemId}::uuid
  `;
  return Number(result.count);
}

async function deleteProbe(tx: Tx, table: TableName): Promise<number> {
  if (table === "profiles") {
    const result = await tx`
      delete from public.profiles
      where id = ${model.targets.disposableProfileId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "products") {
    const result = await tx`
      delete from public.products
      where id = ${model.targets.disposableProductId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "product_variants") {
    const result = await tx`
      delete from public.product_variants
      where id = ${model.targets.disposableVariantId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "customers") {
    const result = await tx`
      delete from public.customers
      where id = ${model.targets.disposableCustomerId}::uuid
    `;
    return Number(result.count);
  }
  if (table === "sales") {
    const result = await tx`
      delete from public.sales
      where id = ${model.targets.updateSaleId}::uuid
    `;
    return Number(result.count);
  }
  const result = await tx`
    delete from public.sale_items
    where id = ${model.targets.updateSaleItemId}::uuid
  `;
  return Number(result.count);
}

async function probe(role: Role, table: TableName, operation: Operation): Promise<Access> {
  const userId = userForRole(role).id;
  return asUser(userId, async (tx) => {
    if (operation === "select") {
      const count = await selectCount(tx, table);
      return count > 0 ? "allow" : "deny";
    }
    if (operation === "insert") {
      try {
        await insertProbe(tx, table);
        return "allow";
      } catch (error) {
        if (isDeny(error)) return "deny";
        throw error;
      }
    }
    if (operation === "update") {
      return verdict(await updateProbe(tx, role, table));
    }
    return verdict(await deleteProbe(tx, table));
  });
}

describe("RLS matches the permission matrix", () => {
  it("resolves each primary seed user's role", async () => {
    for (const role of ["owner", "manager", "cashier"] as const) {
      const actual = await asUser(userForRole(role).id, async (tx) => {
        const rows = await tx<{ role: string }[]>`
          select private.current_app_role()::text as role
        `;
        return rows[0]?.role;
      });
      expect(actual).toBe(role);
    }
  });

  for (const row of PERMISSIONS) {
    it(`${row.role} ${row.operation} ${row.table} is ${row.access}`, async () => {
      const actual = await probe(row.role, row.table, row.operation);
      expect(actual).toBe(row.access);
    });
  }

  it("a cashier can read only their own profile", async () => {
    const cashierId = userForRole("cashier").id;
    const ids = await asUser(cashierId, async (tx) => {
      const rows = await tx<{ id: string }[]>`select id::text as id from public.profiles`;
      return rows.map((row) => row.id);
    });
    expect(ids).toEqual([cashierId]);
  });

  it("the owner can read every staff profile", async () => {
    const count = await asUser(userForRole("owner").id, async (tx) => {
      const rows = await tx<{ n: number }[]>`select count(*)::int as n from public.profiles`;
      return Number(rows[0]?.n ?? 0);
    });
    expect(count).toBe(model.users.length);
  });

  it("a manager cannot edit the owner profile", async () => {
    const result = await asUser(userForRole("manager").id, async (tx) => {
      return tx`
        update public.profiles
        set full_name = 'Should Not Stick'
        where id = ${userForRole("owner").id}::uuid
      `;
    });
    expect(Number(result.count)).toBe(0);
  });

  it("a cashier cannot change their own role", async () => {
    const cashierId = userForRole("cashier").id;
    await expect(
      asUser(cashierId, async (tx) => {
        await tx`
          update public.profiles
          set role = 'owner'
          where id = ${cashierId}::uuid
        `;
      }),
    ).rejects.toMatchObject({ code: "42501" });
  });

  it("a manager cannot change a cashier role", async () => {
    const cashierId = userForRole("cashier").id;
    await expect(
      asUser(userForRole("manager").id, async (tx) => {
        await tx`
          update public.profiles
          set role = 'manager'
          where id = ${cashierId}::uuid
        `;
      }),
    ).rejects.toMatchObject({ code: "42501" });
  });

  it("the owner can change a spare cashier role", async () => {
    const count = await asUser(userForRole("owner").id, async (tx) => {
      const result = await tx`
        update public.profiles
        set role = 'manager'
        where id = ${model.targets.disposableProfileId}::uuid
      `;
      return Number(result.count);
    });
    expect(count).toBe(1);
  });

  it("anon has no table privilege on products", async () => {
    let denied = false;
    try {
      await sql.begin(async (tx) => {
        await tx.unsafe("set local role anon");
        try {
          await tx`select count(*)::int as n from public.products`;
        } catch (error) {
          if (!isDeny(error)) throw error;
          denied = true;
        }
        throw new RollbackSignal();
      });
    } catch (error) {
      if (!(error instanceof RollbackSignal)) throw error;
    }
    expect(denied).toBe(true);
  });
});
