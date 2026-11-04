import { createHmac } from "node:crypto";
import postgres from "postgres";

const ownerId = "11111111-1111-4111-8111-111111111111";
const apiUrl = (process.env["API_URL"] ?? process.env["SUPABASE_URL"] ?? "http://127.0.0.1:54321").replace(/\/$/, "");
const databaseUrl =
  process.env["DATABASE_URL"] ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
// Public local-demo secret shipped by the Supabase CLI. Used only when the API is on loopback
// and the database has not published app.settings.jwt_secret. Never a hosted credential.
const localDemoJwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long";

async function jwtSecret(): Promise<string> {
  const fromEnv = process.env["AUTH_JWT_SECRET"] ?? process.env["JWT_SECRET"];
  if (fromEnv) return fromEnv;
  const sql = postgres(databaseUrl, { max: 1, connect_timeout: 10 });
  try {
    const rows = await sql<{ secret: string | null }[]>`
      select current_setting('app.settings.jwt_secret', true) as secret
    `;
    const secret = rows[0]?.secret;
    if (secret) return secret;
  } finally {
    await sql.end({ timeout: 5 });
  }
  const loopback = apiUrl.startsWith("http://127.0.0.1:") || apiUrl.startsWith("http://localhost:");
  if (loopback) return localDemoJwtSecret;
  throw new Error("JWT secret was not found for the local API");
}

function signJwt(secret: string, role: "service_role" | "authenticated" | "anon", sub?: string): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const header = encode({ alg: "HS256", typ: "JWT" });
  const payload: Record<string, unknown> = {
    aud: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 60 * 10,
    iat: Math.floor(Date.now() / 1000),
    iss: "supabase-demo",
    role,
  };
  if (sub) payload["sub"] = sub;
  const body = encode(payload);
  const signature = createHmac("sha256", secret).update(`${header}.${body}`).digest("base64url");
  return `${header}.${body}.${signature}`;
}

async function postCustomer(
  token: string,
  name: string,
  apiKey = token,
): Promise<{ status: number; body: string }> {
  const response = await fetch(`${apiUrl}/rest/v1/customers`, {
    method: "POST",
    headers: {
      apikey: apiKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      prefer: "return=representation",
    },
    body: JSON.stringify({
      full_name: name,
      phone: `020${Date.now().toString().slice(-7)}`,
      credit_balance_pesewas: 500,
    }),
  });
  return { status: response.status, body: await response.text() };
}

const secret = await jwtSecret();
const serviceToken = signJwt(secret, "service_role", ownerId);
const ownerToken = signJwt(secret, "authenticated", ownerId);
const anonKey = signJwt(secret, "anon");
const denied = await postCustomer(serviceToken, "PostgREST service owner sub");
if (denied.status >= 200 && denied.status < 300) {
  console.error("service_role JWT with the owner subject was allowed to set credit");
  console.error(denied.status, denied.body);
  process.exit(1);
}
if (!denied.body.includes("only the owner can set a credit balance")) {
  console.error("service_role denial did not come from the credit trigger");
  console.error(denied.status, denied.body);
  process.exit(1);
}

const allowed = await postCustomer(ownerToken, "PostgREST authenticated owner", anonKey);
if (allowed.status !== 201) {
  console.error("authenticated owner JWT was not allowed to set credit");
  console.error(allowed.status, allowed.body);
  process.exit(1);
}

console.log("PostgREST credit check: service_role denied, authenticated owner allowed");
