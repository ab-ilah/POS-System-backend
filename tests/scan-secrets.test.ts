import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { scanText, scanWorktree, type FindingKind } from "../scripts/scan-secrets.ts";

function jwt(payload: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode(payload)}.c2lnbmF0dXJl`;
}

function kinds(text: string): FindingKind[] {
  return scanText(text, "fixture").map((finding) => finding.kind);
}

function readNote(dir: string): string {
  return readFileSync(join(dir, "note.txt"), "utf8");
}

describe("secret scan", () => {
  it("allows an anon JWT and rejects other keys", () => {
    expect(kinds(`token=${jwt({ role: "anon" })}`)).toEqual([]);
    expect(kinds(`token=${jwt({ role: "service_role" })}`)).toEqual(["service_role_jwt"]);
    expect(kinds(`token=${jwt({ role: "authenticated", sub: "user" })}`)).toEqual(["non_anon_jwt"]);
    const secretPrefix = "sb_secret_";
    expect(kinds(`${secretPrefix}thisIsAFakeKeyNotReal12345`)).toEqual(["sb_secret"]);
    expect(kinds("no keys here")).toEqual([]);
  });

  it("fails closed when a JWT payload does not decode", () => {
    const token = ["eyJhbGciOiJub25lIn0", "not-json-payload", "c2lnbmF0dXJl"].join(".");
    expect(kinds(token)).toEqual(["non_anon_jwt"]);
  });

  it("finds nothing in the tracked worktree", () => {
    const dir = mkdtempSync(join(tmpdir(), "pos-secret-scan-"));
    writeFileSync(join(dir, "note.txt"), jwt({ role: "service_role" }));
    expect(scanWorktree(process.cwd())).toEqual([]);
    expect(scanText(readNote(dir), "temp-note").map((finding) => finding.kind)).toEqual([
      "service_role_jwt",
    ]);
  });
});
