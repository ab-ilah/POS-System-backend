import { createHmac } from "node:crypto";

const ownerId = "11111111-1111-4111-8111-111111111111";
const apiUrl = (process.env["API_URL"] ?? process.env["SUPABASE_URL"] ?? "http://127.0.0.1:54321").replace(/\/$/, "");
const jwtSecret = process.env["AUTH_JWT_SECRET"] ?? process.env["JWT_SECRET"];

function requireSecret(): string {
  if (!jwtSecret) {
    throw new Error("AUTH_JWT_SECRET or JWT_SECRET is required");
  }
  return jwtSecret;
}

function signJwt(role: "service_role" | "authenticated"): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const header = encode({ alg: "HS256", typ: "JWT" });
  const body = encode({
    aud: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 60 * 10,
    iat: Math.floor(Date.now() / 1000),
    iss: "supabase-demo",
    role,
    sub: ownerId,
  });
  const signature = createHmac("sha256", requireSecret()).update(`${header}.${body}`).digest("base64url");
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

const serviceToken = signJwt("service_role");
const ownerToken = signJwt("authenticated");
const anonKey = process.env["SUPABASE_ANON_KEY"] ?? process.env["ANON_KEY"] ?? ownerToken;
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
