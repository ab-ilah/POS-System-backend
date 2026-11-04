export function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

export function sqlUuid(value: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error(`not a uuid: ${value}`);
  }
  return `'${value.toLowerCase()}'::uuid`;
}

export function sqlInt(value: number, label: string): string {
  if (!Number.isSafeInteger(value)) {
    throw new Error(`${label} must be a whole number of pesewas, got ${String(value)}`);
  }
  return String(value);
}

export function sqlJson(value: unknown): string {
  return `${sqlString(JSON.stringify(value))}::jsonb`;
}

export function sqlTextOrNull(value: string | null): string {
  return value === null ? "null" : sqlString(value);
}
