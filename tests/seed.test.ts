import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildSeed } from "../supabase/seed/catalog.ts";
import { renderSeedSql } from "../supabase/seed/render.ts";

const seed = buildSeed();

function everyInteger(values: number[]): boolean {
  return values.every((value) => Number.isSafeInteger(value));
}

describe("seed catalogue", () => {
  it("matches the committed seed.sql", () => {
    const committed = readFileSync("supabase/seed.sql", "utf8");
    const rendered = renderSeedSql(seed);
    expect(committed).toBe(rendered);
    expect(rendered).not.toContain("app.seed");
    expect(rendered).toContain('"role":"owner"');
    expect(rendered).toContain("insert into public.profiles (id, full_name)");
    expect(rendered).not.toContain("::public.app_role");
  });

  it("has about forty clothing products across the shop categories", () => {
    expect(seed.products.length).toBeGreaterThanOrEqual(40);
    const categories = new Set(seed.products.map((product) => product.category));
    expect(categories).toEqual(
      new Set(["shirts", "dresses", "kaftans", "jeans", "shoes", "accessories"]),
    );
    expect(seed.products.flatMap((product) => product.variants).length).toBeGreaterThan(40);
  });

  it("includes out-of-stock, low-stock, and no-image items", () => {
    const variants = seed.products.flatMap((product) => product.variants);
    expect(variants.some((variant) => variant.stockQty === 0)).toBe(true);
    expect(
      variants.some(
        (variant) => variant.stockQty > 0 && variant.stockQty <= variant.lowStockThreshold,
      ),
    ).toBe(true);
    expect(seed.products.filter((product) => product.imagePath === null).length).toBeGreaterThanOrEqual(3);
  });

  it("includes long Ghanaian-style names and very long size and colour names", () => {
    expect(seed.products.some((product) => product.name.length >= 100)).toBe(true);
    const variants = seed.products.flatMap((product) => product.variants);
    expect(variants.some((variant) => variant.sizeName.length >= 60)).toBe(true);
    expect(variants.some((variant) => variant.colourName.length >= 60)).toBe(true);
  });

  it("keeps every amount as a whole number of pesewas", () => {
    const variants = seed.products.flatMap((product) => product.variants);
    expect(
      everyInteger([
        ...variants.flatMap((variant) => [variant.pricePesewas, variant.stockQty, variant.lowStockThreshold]),
        ...seed.customers.map((customer) => customer.creditBalancePesewas),
        ...seed.sales.flatMap((sale) => [
          sale.subtotalPesewas,
          sale.totalPesewas,
          sale.tenderedPesewas,
          sale.changePesewas,
          sale.creditAppliedPesewas,
          ...sale.items.flatMap((item) => [item.qty, item.unitPricePesewas, item.lineTotalPesewas]),
        ]),
      ]),
    ).toBe(true);
  });

  it("has a customer with a large balance and a few settled sales", () => {
    expect(seed.customers.some((customer) => customer.creditBalancePesewas >= 1_000_000)).toBe(true);
    expect(seed.sales.length).toBeGreaterThanOrEqual(3);
    for (const sale of seed.sales) {
      const lines = sale.items.reduce((sum, item) => sum + item.lineTotalPesewas, 0);
      expect(sale.subtotalPesewas).toBe(lines);
      expect(sale.totalPesewas).toBe(lines);
      expect(sale.tenderedPesewas + sale.creditAppliedPesewas).toBe(
        sale.totalPesewas + sale.changePesewas,
      );
      for (const item of sale.items) {
        expect(item.lineTotalPesewas).toBe(item.qty * item.unitPricePesewas);
      }
    }
  });

  it("keeps disposable rows out of the sales history", () => {
    const soldVariants = new Set(seed.sales.flatMap((sale) => sale.items.map((item) => item.variantId)));
    const disposable = seed.products.find((product) => product.disposable);
    expect(disposable).toBeDefined();
    for (const variant of disposable?.variants ?? []) {
      expect(soldVariants.has(variant.id)).toBe(false);
    }
    expect(seed.sales.some((sale) => sale.customerId === seed.targets.disposableCustomerId)).toBe(false);
    expect(seed.sales.some((sale) => sale.cashierId === seed.targets.disposableProfileId)).toBe(false);
  });
});
