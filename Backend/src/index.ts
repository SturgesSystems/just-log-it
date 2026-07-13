interface Env {
  USDA_API_KEY: string;
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

const USDA_ORIGIN = "https://api.nal.usda.gov";
const UPSTREAM_TIMEOUT_MS = 8_000;
const MAX_BODY_BYTES = 4_096;
const MAX_QUERY_LENGTH = 200;
const MAX_PAGE = 100;
const MAX_PAGE_SIZE = 25;
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
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return errorResponse(400, "invalid_request", "Request body is too large.");
  }

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return errorResponse(400, "invalid_request", "Request body could not be read.");
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
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

async function callUSDA(path: string, env: Env, init: RequestInit): Promise<Response> {
  if (!env.USDA_API_KEY) {
    return errorResponse(500, "server_misconfigured", "Food search is not configured.");
  }

  const url = new URL(path, USDA_ORIGIN);
  url.searchParams.set("api_key", env.USDA_API_KEY);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  let upstream: Response;
  try {
    upstream = await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      return errorResponse(504, "upstream_timeout", "Food search timed out. Please try again.");
    }
    return errorResponse(502, "upstream_unavailable", "Food search is temporarily unavailable.");
  } finally {
    clearTimeout(timeout);
  }

  const rateHeaders = copyRateLimitHeaders(upstream.headers);
  if (upstream.ok) {
    const body = await upstream.arrayBuffer();
    return new Response(body, {
      status: upstream.status,
      headers: responseHeaders(rateHeaders),
    });
  }
  if (upstream.status === 404) {
    return errorResponse(404, "not_found", "Food not found.", rateHeaders);
  }
  if (upstream.status === 429) {
    return errorResponse(429, "rate_limited", "Food search is temporarily busy. Please try again later.", rateHeaders);
  }
  return errorResponse(502, "upstream_unavailable", "Food search is temporarily unavailable.", rateHeaders);
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

function errorResponse(status: number, code: ErrorCode, message: string, extraHeaders?: Headers): Response {
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
