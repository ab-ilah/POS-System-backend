import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { renderSeedSql } from "./render.ts";

const outPath = resolve("supabase/seed.sql");
const sql = renderSeedSql();

if (process.argv.includes("--check")) {
  const current = readFileSync(outPath, "utf8");
  if (current !== sql) {
    console.error("supabase/seed.sql is stale. Run npm run seed:generate.");
    process.exit(1);
  }
  console.log("supabase/seed.sql matches the generator.");
} else {
  writeFileSync(outPath, sql);
  console.log(`wrote ${outPath}`);
}
