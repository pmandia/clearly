import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

export function makeId(prefix: string): string {
  return `${prefix}_${randomBytes(8).toString("hex")}`;
}

export function makeToken(): string {
  return randomBytes(32).toString("base64url");
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function hmacSha256(value: string, secret: string): string {
  return createHmac("sha256", secret).update(value).digest("hex");
}

export function tokenMatches(token: string, expectedHash: string): boolean {
  const actual = Buffer.from(sha256(token), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function hexMatches(actualHex: string, expectedHex: string): boolean {
  const actual = Buffer.from(actualHex, "hex");
  const expected = Buffer.from(expectedHex, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function encodeCursor(value: CursorValue): string {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

export function decodeCursor(cursor: string | undefined): CursorValue | undefined {
  if (!cursor) return undefined;
  const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as CursorValue;
  if (typeof parsed.createdAt !== "string" || typeof parsed.id !== "string") {
    throw new Error("invalid cursor");
  }
  return parsed;
}

export interface CursorValue {
  createdAt: string;
  id: string;
}
