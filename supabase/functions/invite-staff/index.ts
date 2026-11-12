import { createClient } from "jsr:@supabase/supabase-js@2";

const STAFF_ROLES = new Set(["owner", "manager", "cashier"]);
const INVITE_ROLES_MANAGER = new Set(["cashier", "manager"]);

type InviteBody = {
  email?: string;
  full_name?: string;
  role?: string;
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, { error: "misconfigured" });
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "unauthorized" });
  }

  let payload: InviteBody;
  try {
    payload = (await request.json()) as InviteBody;
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const email = payload.email?.trim().toLowerCase() ?? "";
  const fullName = payload.full_name?.trim() ?? "";
  const role = payload.role?.trim() ?? "";
  if (!email || !fullName || !STAFF_ROLES.has(role)) {
    return jsonResponse(400, { error: "invalid_invite" });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: callerRole, error: roleError } = await callerClient.rpc("my_role");
  if (roleError || callerRole == null) {
    return jsonResponse(403, { error: "forbidden" });
  }
  if (callerRole !== "owner" && callerRole !== "manager") {
    return jsonResponse(403, { error: "forbidden" });
  }
  if (callerRole === "manager" && !INVITE_ROLES_MANAGER.has(role)) {
    return jsonResponse(403, { error: "forbidden" });
  }

  const {
    data: { user: caller },
    error: userError,
  } = await callerClient.auth.getUser();
  if (userError || !caller) {
    return jsonResponse(401, { error: "unauthorized" });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { error: rateError } = await adminClient.rpc("consume_staff_invite_slot", {
    p_caller: caller.id,
  });
  if (rateError) {
    const code = rateError.code === "P0004" ? 429 : 403;
    return jsonResponse(code, { error: "rate_limited" });
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (createError || !created.user) {
    return jsonResponse(400, { error: "invite_failed" });
  }

  const { error: metaError } = await adminClient.auth.admin.updateUserById(created.user.id, {
    app_metadata: { role },
  });
  if (metaError) {
    return jsonResponse(500, { error: "invite_failed" });
  }

  return jsonResponse(201, { invited: true });
});
