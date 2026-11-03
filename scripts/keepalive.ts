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

try {
  const rows = await sql<{ ok: number }[]>`select 1 as ok`;
  const ok = rows[0]?.ok;
  if (ok !== 1) {
    console.error("keepalive query did not return 1");
    process.exit(1);
  }
  console.log("keepalive ok");
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
