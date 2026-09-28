import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const history = JSON.parse(readFileSync(resolve(root, "docs/MIGRATION_RECOVERY_MANIFEST.json"), "utf8"));
const dir = resolve(root, "supabase/migrations");
const files = new Set(readdirSync(dir));
const errors = [];

for (const migration of history.migrations) {
  const file = `${migration.version}_${migration.name}.sql`;
  if (!files.has(file)) {
    errors.push(`Missing: ${file}`);
    continue;
  }
  const source = readFileSync(resolve(dir, file), "utf8").trimEnd();
  const digest = createHash("md5").update(source).digest("hex");
  if (digest !== migration.digest) errors.push(`Source differs from recorded migration: ${file}`);
  files.delete(file);
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Verified ${history.migrations.length} recorded migrations; ${files.size} new migration(s) pending isolated database validation.`);
}
