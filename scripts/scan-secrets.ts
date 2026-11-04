import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

export type FindingKind = "sb_secret" | "service_role_jwt" | "non_anon_jwt";

export interface Finding {
  kind: FindingKind;
  where: string;
  line: number;
}

const JWT_RE = /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g;
const SB_SECRET_RE = /sb_secret_[A-Za-z0-9_-]{8,}/g;

function decodePayload(token: string): Record<string, unknown> | null {
  const part = token.split(".")[1];
  if (!part) {
    return null;
  }
  try {
    const padded = part.replaceAll("-", "+").replaceAll("_", "/");
    const json = Buffer.from(padded, "base64").toString("utf8");
    const payload: unknown = JSON.parse(json);
    if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
      return null;
    }
    return payload as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function scanText(text: string, where: string): Finding[] {
  const findings: Finding[] = [];
  const lines = text.split(/\r?\n/);
  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    for (const match of line.matchAll(SB_SECRET_RE)) {
      findings.push({
        kind: "sb_secret",
        where: `${where}:${lineNumber}`,
        line: lineNumber,
      });
      void match;
    }
    for (const match of line.matchAll(JWT_RE)) {
      const token = match[0] ?? "";
      const payload = decodePayload(token);
      const role = payload?.["role"];
      if (role === "anon") {
        continue;
      }
      findings.push({
        kind: role === "service_role" ? "service_role_jwt" : "non_anon_jwt",
        where: `${where}:${lineNumber}`,
        line: lineNumber,
      });
    }
  });
  return findings;
}

function gitLines(args: string[]): string[] {
  const output = execFileSync("git", args, { encoding: "utf8" });
  return output.split("\0").filter((entry) => entry.length > 0);
}

export function scanWorktree(root = process.cwd()): Finding[] {
  const tracked = gitLines(["-C", root, "ls-files", "-z"]);
  const untracked = gitLines(["-C", root, "ls-files", "-z", "-o", "--exclude-standard"]);
  const findings: Finding[] = [];
  for (const relative of [...tracked, ...untracked]) {
    if (relative.endsWith(".png") || relative.endsWith(".jpg") || relative.endsWith(".webp")) {
      continue;
    }
    let text: string;
    try {
      const bytes = readFileSync(`${root}/${relative}`);
      if (bytes.subarray(0, 8000).includes(0)) {
        continue;
      }
      text = bytes.toString("utf8");
    } catch {
      continue;
    }
    findings.push(...scanText(text, relative));
  }
  return findings;
}

export function scanDiff(base: string, root = process.cwd()): Finding[] {
  if (!/^origin\/[A-Za-z0-9._/-]+$/.test(base)) {
    throw new Error(`refusing to scan diff against unexpected base ${base}`);
  }
  const diff = execFileSync("git", ["-C", root, "diff", `${base}...HEAD`], { encoding: "utf8" });
  return scanText(diff, `diff ${base}...HEAD`);
}

function main(): void {
  const findings = [...scanWorktree()];
  const base = process.env["SECRET_SCAN_BASE"];
  if (base) {
    findings.push(...scanDiff(base));
  }
  if (findings.length === 0) {
    console.log("secret scan: no service_role keys, sb_secret_ keys, or non-anon JWTs");
    return;
  }
  for (const finding of findings) {
    console.error(`${finding.kind} at ${finding.where}`);
  }
  console.error(`secret scan failed with ${String(findings.length)} finding(s)`);
  process.exit(1);
}

const invokedDirectly = process.argv[1]?.endsWith("scan-secrets.ts") === true;
if (invokedDirectly) {
  main();
}
