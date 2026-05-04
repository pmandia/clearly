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
    publicBaseUrl: normalizePublicBaseUrl(env.PUBLIC_BASE_URL, env.PORT),
    publisherToken,
    publisherTokenHash: publisherToken ? sha256(publisherToken) : undefined,
    signedUrlSecret,
    databaseUrl: env.DATABASE_URL,
  };
}

function normalizePublicBaseUrl(raw: string | undefined, port: string | undefined): string {
  if (raw === undefined) {
    return `http://localhost:${port ?? 3000}`;
  }

  const trimmed = raw.trim();
  if (trimmed === "") {
    throw new Error("PUBLIC_BASE_URL must be an absolute public URL, for example https://clearly-production.up.railway.app.");
  }
  if (trimmed.startsWith("/")) {
    throw new Error("PUBLIC_BASE_URL must include a host, for example https://clearly-production.up.railway.app.");
  }

  const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  const url = new URL(withScheme);
  return url.toString().replace(/\/$/, "");
}
