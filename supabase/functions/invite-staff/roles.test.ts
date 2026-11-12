import { assertEquals } from "jsr:@std/assert@1";
import { isInvitableStaffRole } from "./roles.ts";

Deno.test("owner is not an invitable staff role", () => {
  assertEquals(isInvitableStaffRole("owner"), false);
});

Deno.test("manager and cashier are invitable", () => {
  assertEquals(isInvitableStaffRole("manager"), true);
  assertEquals(isInvitableStaffRole("cashier"), true);
});

Deno.test("unknown roles are rejected", () => {
  assertEquals(isInvitableStaffRole(""), false);
  assertEquals(isInvitableStaffRole("admin"), false);
});
