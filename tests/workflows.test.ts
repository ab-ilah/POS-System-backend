import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const workflowDir = ".github/workflows";
const workflows = Object.fromEntries(
  readdirSync(workflowDir)
    .filter((name) => name.endsWith(".yml"))
    .map((name) => [name, readFileSync(join(workflowDir, name), "utf8")]),
);

describe("workflows", () => {
  it("pins actions to full commit SHAs", () => {
    for (const [name, text] of Object.entries(workflows)) {
      const uses = text.match(/^[\s-]*uses:.*$/gm) ?? [];
      expect(uses.length, name).toBeGreaterThan(0);
      for (const line of uses) {
        expect(line, `${name}: ${line}`).toMatch(/@[0-9a-f]{40}/);
        expect(line, `${name}: ${line}`).not.toMatch(/@v\d/);
      }
    }
  });

  it("never uses pull_request_target", () => {
    for (const [name, text] of Object.entries(workflows)) {
      expect(text, name).not.toMatch(/^\s*pull_request_target\s*:/m);
    }
  });

  it("runs the PR checks without deploy secrets", () => {
    const ci = workflows["ci.yml"];
    expect(ci).toBeDefined();
    expect(ci).not.toMatch(/\$\{\{\s*secrets\./);
    expect(ci).toContain("npm run typecheck");
    expect(ci).toContain("npm run lint");
    expect(ci).toContain("npm test");
    expect(ci).toContain("npm run secrets:scan");
    expect(ci).toContain("supabase start");
    expect(ci).toContain("scripts/assert-postgres-major.sh");
    expect(readFileSync("scripts/restore-drill.sh", "utf8")).toContain("scripts/assert-postgres-major.sh");
    expect(readFileSync("supabase/config.toml", "utf8")).toMatch(/^major_version = 17$/m);
    expect(readFileSync("scripts/assert-postgres-major.sh", "utf8")).toContain("server_version_num");
    expect(readFileSync("scripts/assert-postgres-major.sh", "utf8")).toContain("pg_dump");
    expect(ci).toContain("supabase db reset");
    expect(ci).toContain("npm run test:rls");
    expect(ci).toContain("npm run test:commit-sale-api");
    expect(ci).toContain("scripts/check-credit-postgrest.ts");
    expect(ci).toContain("supabase test db");
    expect(ci).toContain("supabase db push --dry-run --yes --remote=");
    expect(ci).toContain("--remote[=<ref|branch|url>]");
    expect(ci).toContain("scripts/restore-drill.sh");
    expect(ci).toContain("pull_request:");
    expect(ci).toMatch(/branches:\s*\[main,\s*staging\]/);
    expect(ci).toMatch(/push:\s*\n\s*branches:\s*\[main,\s*staging\]/s);
  });

  it("pushes staging on staging and keeps production manual on main", () => {
    const deploy = workflows["deploy-db.yml"];
    expect(deploy).toBeDefined();
    expect(deploy).toContain("environment: staging");
    expect(deploy).toContain("environment: production");
    expect(deploy).toContain("STAGING_DB_URL");
    expect(deploy).toContain("PROD_DB_URL");
    expect(deploy).toContain("npm run auth:disable-signup");
    expect(deploy).toContain("hnbvmxebzaocdttlteib");
    expect(deploy).toContain("supabase db push --yes --remote=");
    expect(deploy).not.toContain("--db-url");
    expect(deploy).toContain("supabase db push");
    expect(deploy).not.toContain("include-seed");
    expect(deploy).not.toContain("--include-seed");
    expect(deploy).toContain("branches: [staging]");
    expect(deploy).not.toMatch(/push:\s*\n\s*branches:\s*\[main\]/);
    const staging = (deploy?.split("deploy-staging:")[1] ?? "").split("deploy-production:")[0] ?? "";
    expect(staging).toContain("github.ref == 'refs/heads/staging'");
    const production = deploy?.split("deploy-production:")[1] ?? "";
    expect(production).toContain("PROD_DB_URL");
    expect(production).not.toContain("STAGING_DB_URL");
    expect(production).toContain("refs/heads/main");
    expect(production).toContain("vasbjwzykqoebbtvqnjx");
    expect(production).toContain("workflow_dispatch");
    expect(deploy).toContain("validate-dispatch");
    expect(deploy).toContain("Reject production dispatch off main");
    expect(deploy).toContain("refs/heads/main");
    expect(deploy).toContain("Reject staging dispatch off staging");
    expect(deploy).toContain("refs/heads/staging");
    expect(deploy).toMatch(
      /inputs\.target == 'production' && github\.ref != 'refs\/heads\/main'/,
    );
    expect(deploy).toMatch(
      /inputs\.target == 'staging' && github\.ref != 'refs\/heads\/staging'/,
    );
  });

  it("pings staging and production on a schedule", () => {
    const keepalive = workflows["keepalive.yml"];
    expect(keepalive).toBeDefined();
    expect(keepalive).toContain("schedule:");
    expect(keepalive).toContain('cron: "15 6 * * *"');
    expect(keepalive).toContain('cron: "20 6 * * 1"');
    expect(keepalive).toContain("SUPABASE_AUTH_CONFIG_READ_TOKEN");
    const ping = readFileSync("scripts/keepalive.ts", "utf8");
    expect(ping).toContain("public.products");
    expect(ping).toContain("public.customers");
    expect(ping).toContain("public.sales");
    const stagingKeepalive = (keepalive?.split("keepalive-staging:")[1] ?? "").split("keepalive-production:")[0] ?? "";
    expect(stagingKeepalive).toContain("github.ref == 'refs/heads/main'");
    expect(keepalive).toContain("STAGING_DB_URL");
    expect(keepalive).toContain("PROD_DB_URL");
    const production = (keepalive?.split("keepalive-production:")[1] ?? "").split(
      "assert-signup-staging:",
    )[0] ?? "";
    expect(production).toContain("environment: prod-ops");
    expect(production).toContain("github.ref == 'refs/heads/main'");
    expect(production).not.toContain("environment: production");
    expect(production).toContain("PROD_DB_URL");
    expect(production).not.toContain("STAGING_DB_URL");
  });

  it("backs up to object storage and never to an Actions artifact", () => {
    const backup = workflows["backup-db.yml"];
    expect(backup).toBeDefined();
    expect(backup).toContain("environment: prod-ops");
    expect(backup).toContain("github.ref == 'refs/heads/main'");
    expect(backup).not.toContain("environment: production");
    expect(backup).toContain("scripts/backup-database.sh");
    expect(backup).toContain('cron: "0 2 * * *"');
    expect(backup).not.toMatch(/uses:\s*\S*upload-artifact/);
    const script = readFileSync("scripts/backup-database.sh", "utf8");
    expect(script).toContain("pg_dump");
    expect(script).toContain("--format=custom");
    expect(script).toContain("age");
    expect(script).toContain(".age");
    expect(script).toContain("BACKUP_MIN_BYTES");
    expect(script).toContain("postgres@sha256:");
    expect(script).not.toContain("upload-artifact");
  });
});
