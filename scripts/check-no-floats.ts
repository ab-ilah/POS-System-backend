import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const floatParser = ["parse", "Float"].join("");

function filesUnder(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".temp" || entry === ".branches") continue;
    const path = join(dir, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      found.push(...filesUnder(path));
    } else if (path.endsWith(".ts") || path.endsWith(".sql") || path.endsWith(".sh")) {
      found.push(path);
    }
  }
  return found;
}

export function findFloatOffenders(roots = ["shared", "supabase", "scripts", "tests"]): string[] {
  const offenders: string[] = [];
  for (const path of roots.flatMap((dir) => filesUnder(dir))) {
    const text = readFileSync(path, "utf8");
    if (
      path.endsWith(".sql") &&
      /\b(double precision|real|numeric|decimal|float4|float8|bytea)\b/i.test(text)
    ) {
      offenders.push(`${path} uses a fractional or binary column type`);
    }
    if (text.includes(`${floatParser}(`) || text.includes(`Number.${floatParser}`)) {
      offenders.push(`${path} parses a float`);
    }
    const stripped = text
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*--.*$/gm, "")
      .replace(/^\s*\/\/.*$/gm, "")
      .replace(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g, "");
    if (/(?<![\w])\d+\.\d+(?![\w])/.test(stripped)) {
      offenders.push(`${path} contains a decimal literal`);
    }
  }
  return offenders;
}
