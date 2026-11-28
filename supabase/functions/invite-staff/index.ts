/**
 * invite-staff Edge Function — creates a confirmed auth user for staff onboarding.
 * Does not send email; the operator shares credentials or reset flows out of band.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { inviteRoleHttpError } from "./invite_role_http.ts";
import { parseInviteJsonBody, type InviteBody } from "./invite_json_body.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

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

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }
  const payload = parseInviteJsonBody(raw);
  if (payload === null) {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const email = payload.email?.trim().toLowerCase() ?? "";
  const fullName = payload.full_name?.trim() ?? "";
  const role = payload.role?.trim() ?? "";
  if (!email || !fullName || !role.trim()) {
    return jsonResponse(400, { error: "invalid_invite" });
  }
  const invalidRole = inviteRoleHttpError(role);
  if (invalidRole) {
    return jsonResponse(invalidRole.status, { error: invalidRole.error });
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

  const { error: rateError } = await callerClient.rpc("consume_staff_invite_slot");
  if (rateError) {
    if (rateError.code === "P0004") {
      return jsonResponse(429, { error: "rate_limited" });
    }
    return jsonResponse(500, { error: "internal_error" });
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    email_confirm: true,
    app_metadata: { role },
    user_metadata: { full_name: fullName },
  });
  if (createError || !created.user) {
    return jsonResponse(400, { error: "invite_failed" });
  }

  return jsonResponse(201, { invited: true });
});
