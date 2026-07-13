interface Env {
  USDA_API_KEY: string;
  GLOBAL_USDA_QUOTA: DurableObjectNamespace;
}

type ErrorCode =
  | "invalid_request"
  | "not_found"
  | "method_not_allowed"
  | "rate_limited"
  | "upstream_timeout"
  | "upstream_unavailable"
  | "server_misconfigured";

interface SearchRequest {
  query: string;
  dataTypes?: DataType[];
  page: number;
  pageSize: number;
}

interface QuotaState {
  epochHour: number;
  count: number;
}

const USDA_ORIGIN = "https://api.nal.usda.gov";
const UPSTREAM_TIMEOUT_MS = 8_000;
const MAX_REQUEST_BODY_BYTES = 4_096;
const MAX_UPSTREAM_BODY_BYTES = 2 * 1024 * 1024;
const MAX_QUERY_LENGTH = 200;
const MAX_PAGE = 100;
const MAX_PAGE_SIZE = 50;
const GLOBAL_HOURLY_USDA_BUDGET = 900;
const QUOTA_OBJECT_NAME = "global";

const DATA_TYPES = [
  "Branded",
  "Foundation",
  "Survey (FNDDS)",
  "SR Legacy",
  "Experimental",
] as const;
type DataType = (typeof DATA_TYPES)[number];

const ALLOWED_SEARCH_KEYS = new Set(["query", "dataTypes", "page", "pageSize"]);
const FORWARDED_RATE_LIMIT_HEADERS = [
  "Retry-After",
  "X-RateLimit-Limit",
  "X-RateLimit-Remaining",
  "X-RateLimit-Reset",
] as const;

export class GlobalUSDAQuota implements DurableObject {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const now = Date.now();
    const epochHour = Math.floor(now / 3_600_000);
    const current = (await this.state.storage.get<QuotaState>("quota")) ?? {
      epochHour,
      count: 0,
    };
    const baseline =
      current.epochHour === epochHour ? current : { epochHour, count: 0 };

    if (baseline.count >= GLOBAL_HOURLY_USDA_BUDGET) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil(((epochHour + 1) * 3_600_000 - now) / 1_000),
      );
      return Response.json(
        { allowed: false, remaining: 0, retryAfterSeconds },
        { status: 429 },
      );
    }

    const next: QuotaState = {
      epochHour,
      count: baseline.count + 1,
    };
    await this.state.storage.put("quota", next);
    return Response.json({
      allowed: true,
      remaining: GLOBAL_HOURLY_USDA_BUDGET - next.count,
      retryAfterSeconds: 0,
    });
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/v1/foods/search") {
      if (request.method !== "POST") {
        return methodNotAllowed("POST");
      }
      if (url.search !== "") {
        return errorResponse(400, "invalid_request", "Query parameters are not allowed.");
      }
      return handleSearch(request, env);
    }

    const detailMatch = /^\/v1\/foods\/([1-9]\d*)$/.exec(url.pathname);
    if (detailMatch) {
      if (request.method !== "GET") {
        return methodNotAllowed("GET");
      }
      if (url.search !== "") {
        return errorResponse(400, "invalid_request", "Query parameters are not allowed.");
      }
      return handleDetails(detailMatch[1]!, env);
    }

    return errorResponse(404, "not_found", "Route not found.");
  },
} satisfies ExportedHandler<Env>;

async function handleSearch(request: Request, env: Env): Promise<Response> {
  const contentType = request.headers.get("Content-Type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    return errorResponse(400, "invalid_request", "Content-Type must be application/json.");
  }

  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BODY_BYTES) {
    return errorResponse(400, "invalid_request", "Request body is too large.");
  }

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return errorResponse(400, "invalid_request", "Request body could not be read.");
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BODY_BYTES) {
    return errorResponse(400, "invalid_request", "Request body is too large.");
  }

  let input: unknown;
  try {
    input = JSON.parse(rawBody);
  } catch {
    return errorResponse(400, "invalid_request", "Request body must be valid JSON.");
  }

  const parsed = parseSearchRequest(input);
  if (typeof parsed === "string") {
    return errorResponse(400, "invalid_request", parsed);
  }

  const upstreamBody: Record<string, unknown> = {
    query: parsed.query,
    pageNumber: parsed.page,
    pageSize: parsed.pageSize,
  };
  if (parsed.dataTypes) {
    upstreamBody.dataType = parsed.dataTypes;
  }

  return callUSDA("/fdc/v1/foods/search", env, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(upstreamBody),
  });
}

async function handleDetails(fdcId: string, env: Env): Promise<Response> {
  const numericID = Number(fdcId);
  if (!Number.isSafeInteger(numericID)) {
    return errorResponse(400, "invalid_request", "Food identifier is invalid.");
  }

  return callUSDA(`/fdc/v1/food/${fdcId}`, env, {
    method: "GET",
    headers: { Accept: "application/json" },
  });
}

function parseSearchRequest(input: unknown): SearchRequest | string {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return "Request body must be a JSON object.";
  }

  const record = input as Record<string, unknown>;
  const unknownKeys = Object.keys(record).filter((key) => !ALLOWED_SEARCH_KEYS.has(key));
  if (unknownKeys.length > 0) {
    return `Unknown field: ${unknownKeys[0]}.`;
  }

  if (typeof record.query !== "string") {
    return "query must be a string.";
  }
  const query = record.query.trim().replace(/\s+/g, " ");
  if (query.length === 0 || query.length > MAX_QUERY_LENGTH) {
    return `query must contain between 1 and ${MAX_QUERY_LENGTH} characters.`;
  }

  const page = record.page ?? 1;
  if (!isIntegerBetween(page, 1, MAX_PAGE)) {
    return `page must be an integer between 1 and ${MAX_PAGE}.`;
  }

  const pageSize = record.pageSize ?? 20;
  if (!isIntegerBetween(pageSize, 1, MAX_PAGE_SIZE)) {
    return `pageSize must be an integer between 1 and ${MAX_PAGE_SIZE}.`;
  }

  let dataTypes: DataType[] | undefined;
  if (record.dataTypes !== undefined) {
    if (!Array.isArray(record.dataTypes) || record.dataTypes.length === 0) {
      return "dataTypes must be a non-empty array.";
    }
    if (record.dataTypes.length > DATA_TYPES.length) {
      return "dataTypes contains too many values.";
    }
    if (!record.dataTypes.every(isDataType)) {
      return "dataTypes contains an unsupported value.";
    }
    if (new Set(record.dataTypes).size !== record.dataTypes.length) {
      return "dataTypes must not contain duplicate values.";
    }
    dataTypes = record.dataTypes;
  }

  return { query, dataTypes, page, pageSize };
}

function isIntegerBetween(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum;
}

function isDataType(value: unknown): value is DataType {
  return typeof value === "string" && (DATA_TYPES as readonly string[]).includes(value);
}

async function reserveGlobalQuota(env: Env): Promise<Response | null> {
  if (!env.GLOBAL_USDA_QUOTA) {
    return errorResponse(
      500,
      "server_misconfigured",
      "Food search is not configured.",
    );
  }

  try {
    const id = env.GLOBAL_USDA_QUOTA.idFromName(QUOTA_OBJECT_NAME);
    const stub = env.GLOBAL_USDA_QUOTA.get(id);
    const quotaResponse = await stub.fetch("https://quota/reserve", { method: "POST" });
    if (quotaResponse.status === 429) {
      const payload = (await quotaResponse.json()) as { retryAfterSeconds?: number };
      const headers = new Headers();
      if (
        typeof payload.retryAfterSeconds === "number" &&
        Number.isFinite(payload.retryAfterSeconds) &&
        payload.retryAfterSeconds > 0
      ) {
        headers.set("Retry-After", String(Math.ceil(payload.retryAfterSeconds)));
      }
      return errorResponse(
        429,
        "rate_limited",
        "Food search is temporarily busy. Please try again later.",
        headers,
      );
    }
    if (!quotaResponse.ok) {
      return errorResponse(
        500,
        "server_misconfigured",
        "Food search is not configured.",
      );
    }
    return null;
  } catch {
    return errorResponse(
      500,
      "server_misconfigured",
      "Food search is not configured.",
    );
  }
}

async function callUSDA(path: string, env: Env, init: RequestInit): Promise<Response> {
  if (!env.USDA_API_KEY) {
    return errorResponse(500, "server_misconfigured", "Food search is not configured.");
  }

  if (!isPinnedUSDAPath(path)) {
    return errorResponse(500, "server_misconfigured", "Food search is not configured.");
  }

  const quotaError = await reserveGlobalQuota(env);
  if (quotaError) {
    return quotaError;
  }

  const url = new URL(path, USDA_ORIGIN);
  if (url.origin !== USDA_ORIGIN) {
    return errorResponse(500, "server_misconfigured", "Food search is not configured.");
  }

  const headers = new Headers(init.headers);
  headers.set("X-Api-Key", env.USDA_API_KEY);
  headers.set("Accept", "application/json");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  try {
    let upstream: Response;
    try {
      upstream = await fetch(url, {
        method: init.method,
        headers,
        body: init.body,
        redirect: "error",
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        return errorResponse(504, "upstream_timeout", "Food search timed out. Please try again.");
      }
      return errorResponse(502, "upstream_unavailable", "Food search is temporarily unavailable.");
    }

    const rateHeaders = copyRateLimitHeaders(upstream.headers);
    const declaredUpstreamLength = Number(upstream.headers.get("Content-Length") ?? "NaN");
    if (
      Number.isFinite(declaredUpstreamLength) &&
      declaredUpstreamLength > MAX_UPSTREAM_BODY_BYTES
    ) {
      return errorResponse(
        502,
        "upstream_unavailable",
        "Food search is temporarily unavailable.",
        rateHeaders,
      );
    }

    let body: ArrayBuffer;
    try {
      const readResult = await readBodyWithLimit(upstream, MAX_UPSTREAM_BODY_BYTES, controller.signal);
      if (readResult === "too_large") {
        return errorResponse(
          502,
          "upstream_unavailable",
          "Food search is temporarily unavailable.",
          rateHeaders,
        );
      }
      body = readResult;
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        return errorResponse(504, "upstream_timeout", "Food search timed out. Please try again.");
      }
      return errorResponse(502, "upstream_unavailable", "Food search is temporarily unavailable.");
    }

    if (upstream.ok) {
      const upstreamType = upstream.headers.get("Content-Type")?.toLowerCase() ?? "";
      if (!upstreamType.startsWith("application/json")) {
        return errorResponse(
          502,
          "upstream_unavailable",
          "Food search is temporarily unavailable.",
          rateHeaders,
        );
      }
      return new Response(body, {
        status: upstream.status,
        headers: responseHeaders(rateHeaders),
      });
    }

    if (upstream.status === 404) {
      return errorResponse(404, "not_found", "Food not found.", rateHeaders);
    }
    if (upstream.status === 429) {
      return errorResponse(
        429,
        "rate_limited",
        "Food search is temporarily busy. Please try again later.",
        rateHeaders,
      );
    }
    if (upstream.status === 401 || upstream.status === 403) {
      return errorResponse(
        502,
        "upstream_unavailable",
        "Food search is temporarily unavailable.",
        rateHeaders,
      );
    }
    return errorResponse(
      502,
      "upstream_unavailable",
      "Food search is temporarily unavailable.",
      rateHeaders,
    );
  } finally {
    clearTimeout(timeout);
  }
}

function isPinnedUSDAPath(path: string): boolean {
  if (path === "/fdc/v1/foods/search") {
    return true;
  }
  return /^\/fdc\/v1\/food\/[1-9]\d*$/.test(path);
}

async function readBodyWithLimit(
  response: Response,
  maxBytes: number,
  signal: AbortSignal,
): Promise<ArrayBuffer | "too_large"> {
  if (!response.body) {
    return new ArrayBuffer(0);
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  while (true) {
    if (signal.aborted) {
      await reader.cancel().catch(() => undefined);
      throw new DOMException("The operation was aborted.", "AbortError");
    }

    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    if (!value) {
      continue;
    }

    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      return "too_large";
    }
    chunks.push(value);
  }

  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return merged.buffer;
}

function copyRateLimitHeaders(source: Headers): Headers {
  const result = new Headers();
  for (const name of FORWARDED_RATE_LIMIT_HEADERS) {
    const value = source.get(name);
    if (value !== null) {
      result.set(name, value);
    }
  }
  return result;
}

function methodNotAllowed(allowedMethod: string): Response {
  const headers = new Headers({ Allow: allowedMethod });
  return errorResponse(405, "method_not_allowed", `Use ${allowedMethod} for this route.`, headers);
}

function errorResponse(
  status: number,
  code: ErrorCode,
  message: string,
  extraHeaders?: Headers,
): Response {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: responseHeaders(extraHeaders),
  });
}

function responseHeaders(extra?: Headers): Headers {
  const headers = new Headers(extra);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}
