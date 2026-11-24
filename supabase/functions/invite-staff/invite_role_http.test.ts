import { assertEquals } from "jsr:@std/assert@1";
import { inviteRoleHttpError } from "./invite_role_http.ts";

Deno.test("role owner maps to HTTP 400 invalid_role", () => {
  const err = inviteRoleHttpError("owner");
  assertEquals(err, { status: 400, error: "invalid_role" });
});