import { assertEquals } from "jsr:@std/assert@1";
import { parseInviteJsonBody } from "./invite_json_body.ts";

Deno.test("parseInviteJsonBody accepts a plain object", () => {
  assertEquals(parseInviteJsonBody({ email: "a@b.c" }), { email: "a@b.c" });
});

Deno.test("parseInviteJsonBody rejects null", () => {
  assertEquals(parseInviteJsonBody(null), null);
});

Deno.test("parseInviteJsonBody rejects arrays", () => {
  assertEquals(parseInviteJsonBody([]), null);
});

Deno.test("parseInviteJsonBody rejects non-object primitives", () => {
  assertEquals(parseInviteJsonBody("text"), null);
  assertEquals(parseInviteJsonBody(42), null);
});