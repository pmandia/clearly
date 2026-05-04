import { loadConfig } from "./config.js";
import { PostgresReviewStore } from "./postgres-store.js";
import { buildServer } from "./server.js";

const config = loadConfig();

if (!config.databaseUrl) {
  throw new Error("DATABASE_URL is required.");
}

const store = PostgresReviewStore.fromDatabaseUrl(config.databaseUrl);
const server = buildServer(store, config);

await server.listen({ port: config.port, host: "0.0.0.0" });
