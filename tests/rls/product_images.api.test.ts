import { randomUUID } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Role } from "../../shared/permissions.matrix.ts";
import { LOCAL_SEED_PASSWORD, userForRole } from "../../supabase/seed/catalog.ts";

const runProductImagesApi = process.env["RUN_PRODUCT_IMAGES_API"] === "1";

const PRODUCT_ID = "10000000-0000-4000-8000-000000000001";

const apiUrl = (process.env["SUPABASE_URL"] ?? process.env["API_URL"] ?? "http://127.0.0.1:54321").replace(
  /\/$/,
  "",
);

const PNG_1X1 = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

function requireAnonKey(): string {
  const key = process.env["SUPABASE_ANON_KEY"] ?? process.env["ANON_KEY"];
  if (!key) {
    throw new Error("SUPABASE_ANON_KEY or ANON_KEY must be set (supabase status -o env).");
  }
  return key;
}

async function signInRole(role: Role): Promise<SupabaseClient> {
  const anonKey = requireAnonKey();
  const user = userForRole(role);
  const authClient = createClient(apiUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await authClient.auth.signInWithPassword({
    email: user.email,
    password: LOCAL_SEED_PASSWORD,
  });
  if (error || !data.session) {
    throw error ?? new Error(`${role} sign-in failed`);
  }
  return createClient(apiUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

function objectPath(suffix: string): string {
  return `products/${PRODUCT_ID}/${suffix}`;
}

describe.skipIf(!runProductImagesApi)("product-images storage API", () => {
  let managerClient: SupabaseClient;
  let cashierClient: SupabaseClient;

  beforeAll(async () => {
    managerClient = await signInRole("manager");
    cashierClient = await signInRole("cashier");
  });

  it("denies a cashier upload", async () => {
    const path = objectPath(`cashier-denied-${randomUUID()}.png`);
    const { error } = await cashierClient.storage.from("product-images").upload(path, PNG_1X1, {
      contentType: "image/png",
      upsert: false,
    });
    expect(error).not.toBeNull();
  });

  it("allows a manager upload of a small PNG", async () => {
    const path = objectPath(`manager-ok-${randomUUID()}.png`);
    const { error } = await managerClient.storage.from("product-images").upload(path, PNG_1X1, {
      contentType: "image/png",
      upsert: false,
    });
    expect(error).toBeNull();
  });

  it("rejects a disallowed MIME type", async () => {
    const path = objectPath(`bad-mime-${randomUUID()}.txt`);
    const { error } = await managerClient.storage.from("product-images").upload(path, Buffer.from("not an image"), {
      contentType: "text/plain",
      upsert: false,
    });
    expect(error).not.toBeNull();
  });

  it("rejects an oversize file", async () => {
    const path = objectPath(`too-large-${randomUUID()}.png`);
    const blob = Buffer.alloc(2_097_153, 0);
    const { error } = await managerClient.storage.from("product-images").upload(path, blob, {
      contentType: "image/png",
      upsert: false,
    });
    expect(error).not.toBeNull();
  });
});