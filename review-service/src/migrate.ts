import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error("DATABASE_URL is required.");
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const migrationsDirectory = join(root, "migrations");
const pool = new Pool({ connectionString: databaseUrl });

try {
  const files = (await readdir(migrationsDirectory)).filter((file) => file.endsWith(".sql")).sort();
  for (const file of files) {
    const migration = await readFile(join(migrationsDirectory, file), "utf8");
    await pool.query(migration);
  }
  console.log("review-service migration complete");
} finally {
  await pool.end();
}
