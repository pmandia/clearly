import { sha256 } from "./crypto.js";

export interface ServiceConfig {
  port: number;
  publicBaseUrl: string;
  publisherToken?: string;
  publisherTokenHash?: string;
  signedUrlSecret?: string;
  databaseUrl?: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): ServiceConfig {
  const publisherToken = env.CLEARLY_REVIEW_PUBLISHER_TOKEN;
  const signedUrlSecret = env.CLEARLY_REVIEW_SIGNED_URL_SECRET;
  if (!signedUrlSecret || signedUrlSecret.trim() === "") {
    throw new Error("CLEARLY_REVIEW_SIGNED_URL_SECRET is required.");
  }
  return {
    port: Number(env.PORT ?? 3000),
    publicBaseUrl: env.PUBLIC_BASE_URL ?? `http://localhost:${env.PORT ?? 3000}`,
    publisherToken,
    publisherTokenHash: publisherToken ? sha256(publisherToken) : undefined,
    signedUrlSecret,
    databaseUrl: env.DATABASE_URL,
  };
}
