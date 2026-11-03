import postgres from "postgres";

const url = process.env["DATABASE_URL"];
if (!url) {
  console.error("DATABASE_URL is not set");
  process.exit(1);
}

const local = /@(127\.0\.0\.1|localhost)(:|\/)/.test(url);
const sql = postgres(url, {
  max: 1,
  prepare: false,
  ssl: local ? false : "require",
  connect_timeout: 20,
});

function asCount(value: unknown): number | null {
  const count = Number(value);
  if (!Number.isInteger(count) || count < 0) {
    return null;
  }
  return count;
}

try {
  const products = await sql<{ n: number }[]>`select count(*)::int as n from public.products`;
  const customers = await sql<{ n: number }[]>`select count(*)::int as n from public.customers`;
  const sales = await sql<{ n: number }[]>`select count(*)::int as n from public.sales`;
  const counts = [asCount(products[0]?.n), asCount(customers[0]?.n), asCount(sales[0]?.n)];
  if (counts.some((count) => count === null)) {
    console.error("keepalive read did not return a row count");
    process.exit(1);
  }
  console.log(
    `keepalive ok products=${String(counts[0])} customers=${String(counts[1])} sales=${String(counts[2])}`,
  );
} catch (error) {
  const message = error instanceof Error ? error.message : "unknown error";
  if (message.includes("://") || message.toLowerCase().includes("password")) {
    console.error("keepalive failed (connection error redacted)");
  } else {
    console.error(`keepalive failed: ${message}`);
  }
  process.exit(1);
} finally {
  await sql.end({ timeout: 5 });
}
