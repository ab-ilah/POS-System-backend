import { randomUUID } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  LOCAL_SEED_PASSWORD,
  userForRole,
  type SeedUser,
} from "../../supabase/seed/catalog.ts";

const runCommitSaleApi = process.env["RUN_COMMIT_SALE_API"] === "1";

const DEFAULT_STORE_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

const apiUrl = (process.env["SUPABASE_URL"] ?? process.env["API_URL"] ?? "http://127.0.0.1:54321").replace(
  /\/$/,
  "",
);

function requireAnonKey(): string {
  const key = process.env["SUPABASE_ANON_KEY"] ?? process.env["ANON_KEY"];
  if (!key) {
    throw new Error("SUPABASE_ANON_KEY or ANON_KEY must be set (supabase status -o env).");
  }
  return key;
}

type VariantRow = {
  id: string;
  stock_qty: number;
  price_pesewas: number;
};

let cashierClient: SupabaseClient;

async function signInCashier(): Promise<SupabaseClient> {
  const anonKey = requireAnonKey();
  const cashier: SeedUser = userForRole("cashier");
  const client = createClient(apiUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: cashier.email,
    password: LOCAL_SEED_PASSWORD,
  });
  if (error || !data.session) {
    throw error ?? new Error("cashier sign-in failed");
  }
  return createClient(apiUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function stockedVariant(client: SupabaseClient): Promise<VariantRow> {
  const { data, error } = await client
    .from("product_variants")
    .select("id, stock_qty, price_pesewas")
    .gte("stock_qty", 5)
    .order("sku", { ascending: true })
    .limit(1)
    .single();
  if (error || !data) {
    throw error ?? new Error("no stocked variant");
  }
  return data as VariantRow;
}

async function zeroStockVariant(client: SupabaseClient): Promise<VariantRow> {
  const { data, error } = await client
    .from("product_variants")
    .select("id, stock_qty, price_pesewas")
    .eq("stock_qty", 0)
    .limit(1)
    .single();
  if (error || !data) {
    throw error ?? new Error("no zero-stock variant");
  }
  return data as VariantRow;
}

function linePayload(variant: VariantRow, quantity: number, lineId: string) {
  return {
    id: lineId,
    variant_id: variant.id,
    quantity,
    unit_price_pesewas: variant.price_pesewas,
  };
}

describe.skipIf(!runCommitSaleApi)("commit_sale via Supabase JS", () => {
  beforeAll(async () => {
    cashierClient = await signInCashier();
  });
  it("completes a sale, writes lines, decrements stock, and replays idempotently", async () => {
    const variant = await stockedVariant(cashierClient);
    const saleId = randomUUID();
    const lineId = randomUUID();
    const stockBefore = variant.stock_qty;

    const lines = [linePayload(variant, 2, lineId)];
    const { data, error } = await cashierClient.rpc("commit_sale", {
      p_idempotency_key: saleId,
      p_store_id: DEFAULT_STORE_ID,
      p_lines: lines,
    });
    expect(error).toBeNull();
    expect(data).toEqual({ sale_id: saleId, replayed: false });

    const { data: sale, error: saleError } = await cashierClient
      .from("sales")
      .select("status, cashier_id")
      .eq("id", saleId)
      .single();
    expect(saleError).toBeNull();
    expect(sale?.status).toBe("completed");
    expect(sale?.cashier_id).toBe(userForRole("cashier").id);

    const { count: lineCount, error: lineError } = await cashierClient
      .from("sale_items")
      .select("id", { count: "exact", head: true })
      .eq("sale_id", saleId);
    expect(lineError).toBeNull();
    expect(lineCount).toBe(1);

    const { data: variantAfter, error: variantError } = await cashierClient
      .from("product_variants")
      .select("stock_qty")
      .eq("id", variant.id)
      .single();
    expect(variantError).toBeNull();
    expect(variantAfter?.stock_qty).toBe(stockBefore - 2);

    const replay = await cashierClient.rpc("commit_sale", {
      p_idempotency_key: saleId,
      p_store_id: DEFAULT_STORE_ID,
      p_lines: lines,
    });
    expect(replay.error).toBeNull();
    expect(replay.data).toEqual({ sale_id: saleId, replayed: true });

    const mismatch = await cashierClient.rpc("commit_sale", {
      p_idempotency_key: saleId,
      p_store_id: DEFAULT_STORE_ID,
      p_lines: [linePayload(variant, 3, lineId)],
    });
    expect(mismatch.error).not.toBeNull();
    expect(mismatch.error?.code).toBe("P0004");
    expect(mismatch.error?.message).toContain("idempotency_key_reuse");
  });

  it("returns PSTCK with variant_id in details", async () => {
    const variant = await zeroStockVariant(cashierClient);
    const saleId = randomUUID();
    const lineId = randomUUID();

    const { error } = await cashierClient.rpc("commit_sale", {
      p_idempotency_key: saleId,
      p_store_id: DEFAULT_STORE_ID,
      p_lines: [linePayload(variant, 1, lineId)],
    });
    expect(error).not.toBeNull();
    expect(error?.code).toBe("PSTCK");
    expect(error?.message).toContain("insufficient stock");
    expect(error?.details).toBe(`variant_id=${variant.id}`);

    const { count } = await cashierClient
      .from("sales")
      .select("id", { count: "exact", head: true })
      .eq("id", saleId);
    expect(count).toBe(0);
  });
});
