import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const restore = readFileSync("docs/runbooks/restore.md", "utf8");
const rotation = readFileSync("docs/runbooks/key-rotation.md", "utf8");
const backup = readFileSync("docs/backup/README.md", "utf8");
const protection = readFileSync("docs/branch-protection.md", "utf8");

describe("restore and operations docs", () => {
  it("describes an empty restore and a data-only restore", () => {
    expect(restore).toContain("--schema=private");
    expect(restore).toContain("--data-only");
    expect(restore).toContain("--single-transaction");
    expect(restore).toContain("--disable-triggers");
    expect(restore).toContain("--force-path-style");
    expect(restore).not.toContain("--clean");
    expect(restore).not.toContain("--if-exists");
  });

  it("tells a leak response to treat old backups as exposed", () => {
    expect(rotation.toLowerCase()).toContain("treat old backups as exposed");
    expect(rotation).toContain("prod-ops");
    expect(rotation).toContain("PROD_DB_URL");
  });

  it("puts storage secrets on prod-ops and limits deployment branches to main", () => {
    expect(backup).toContain("`prod-ops`");
    expect(backup).toContain("not on `production`");
    expect(protection).toContain("Deployment branches");
    expect(protection).toContain("`main` only");
  });
});