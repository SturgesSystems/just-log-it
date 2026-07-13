import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { GlobalUSDAQuota } from "../src/index";

type QuotaResponse = {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
};

function makeQuotaBinding(handler?: (request: Request) => Promise<Response> | Response) {
  const fetchHandler =
    handler ??
    (async () =>
      Response.json({
        allowed: true,
        remaining: 899,
        retryAfterSeconds: 0,
      } satisfies QuotaResponse));

  return {
    idFromName(name: string) {
      expect(name).toBe("global");
      return { name } as unknown as DurableObjectId;
    },
    get() {
      return {
        fetch: fetchHandler,
      } as unknown as DurableObjectStub;
    },
  } as unknown as DurableObjectNamespace;
}

function makeEnv(overrides: Partial<{ USDA_API_KEY: string; quota: DurableObjectNamespace }> = {}) {
  return {
    USDA_API_KEY: overrides.USDA_API_KEY ?? "test-secret",
    GLOBAL_USDA_QUOTA: overrides.quota ?? makeQuotaBinding(),
  };
}

function request(path: string, init?: RequestInit): Request {
  return new Request(`https://proxy.example${path}`, init);
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("routing and validation", () => {
  it("rejects unknown routes", async () => {
    const response = await worker.fetch(request("/nope"), makeEnv());
    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: { code: "not_found", message: "Route not found." },
    });
  });

  it("requires POST for search", async () => {
    const response = await worker.fetch(request("/v1/foods/search"), makeEnv());
    expect(response.status).toBe(405);
    expect(response.headers.get("Allow")).toBe("POST");
  });

  it("rejects unknown fields and oversized page sizes without calling USDA", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    for (const body of [
      { query: "apple", unexpected: true },
      { query: "apple", pageSize: 51 },
      { query: "apple", dataTypes: ["Not real"] },
    ]) {
      const response = await worker.fetch(
        request("/v1/foods/search", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }),
        makeEnv(),
      );
      expect(response.status).toBe(400);
      expect((await response.json()) as object).toHaveProperty("error.code", "invalid_request");
    }
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects query strings on public routes", async () => {
    const response = await worker.fetch(request("/v1/foods/123?format=abridged"), makeEnv());
    expect(response.status).toBe(400);
  });
});

describe("USDA proxying", () => {
  it("normalizes and forwards an allowlisted search with header auth", async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ foods: [{ fdcId: 123 }] }), {
        headers: {
          "Content-Type": "application/json",
          "X-RateLimit-Remaining": "999",
        },
      }),
    );
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(
      request("/v1/foods/search", {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({
          query: "  greek   yogurt ",
          dataTypes: ["Branded", "Foundation"],
          page: 2,
          pageSize: 50,
        }),
      }),
      makeEnv(),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("X-RateLimit-Remaining")).toBe("999");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
    const [url, init] = upstream.mock.calls[0] as [URL, RequestInit];
    expect(url.origin + url.pathname).toBe("https://api.nal.usda.gov/fdc/v1/foods/search");
    expect(url.searchParams.get("api_key")).toBeNull();
    expect(url.search).toBe("");
    expect(init.redirect).toBe("error");
    const headers = new Headers(init.headers);
    expect(headers.get("X-Api-Key")).toBe("test-secret");
    expect(headers.get("Accept")).toBe("application/json");
    expect(JSON.parse(init.body as string)).toEqual({
      query: "greek yogurt",
      pageNumber: 2,
      pageSize: 50,
      dataType: ["Branded", "Foundation"],
    });
  });

  it("proxies food details with only controlled request headers", async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ fdcId: 123 }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());

    expect(response.status).toBe(200);
    const [url, init] = upstream.mock.calls[0] as [URL, RequestInit];
    expect(url.pathname).toBe("/fdc/v1/food/123");
    expect(url.searchParams.get("api_key")).toBeNull();
    expect(init.redirect).toBe("error");
    const headers = new Headers(init.headers);
    expect(headers.get("X-Api-Key")).toBe("test-secret");
    expect(headers.get("Accept")).toBe("application/json");
    expect(headers.get("Content-Type")).toBeNull();
  });

  it("normalizes upstream errors without forwarding their body or secret", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("upstream secret diagnostic test-secret", {
          status: 429,
          headers: { "Retry-After": "60", "X-Unrelated": "discard-me" },
        }),
      ),
    );

    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    const text = await response.text();

    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(response.headers.get("X-Unrelated")).toBeNull();
    expect(text).not.toContain("upstream secret diagnostic");
    expect(text).not.toContain("test-secret");
  });

  it("maps upstream 401 and 403 to a stable unavailable error", async () => {
    for (const status of [401, 403]) {
      vi.stubGlobal(
        "fetch",
        vi.fn().mockResolvedValue(
          new Response("auth failure containing test-secret", {
            status,
            headers: { "Content-Type": "text/plain" },
          }),
        ),
      );
      const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
      const body = await response.json();
      expect(response.status).toBe(502);
      expect(body).toEqual({
        error: {
          code: "upstream_unavailable",
          message: "Food search is temporarily unavailable.",
        },
      });
      expect(JSON.stringify(body)).not.toContain("test-secret");
    }
  });

  it("maps upstream 5xx to unavailable without reflecting the body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("internal USDA stack trace", {
          status: 503,
          headers: { "Content-Type": "text/html" },
        }),
      ),
    );
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain("stack trace");
  });

  it("rejects non-JSON success content types", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("<html>not json</html>", {
          status: 200,
          headers: { "Content-Type": "text/html" },
        }),
      ),
    );
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toHaveProperty("error.code", "upstream_unavailable");
  });

  it("rejects oversized upstream responses by declared length", async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response("x".repeat(100), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": String(2 * 1024 * 1024 + 1),
        },
      }),
    );
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    expect(response.status).toBe(502);
  });

  it("rejects oversized upstream responses while streaming the body", async () => {
    const oversized = new Uint8Array(2 * 1024 * 1024 + 1);
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(oversized);
        controller.close();
      },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(stream, {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      ),
    );
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    expect(response.status).toBe(502);
  });

  it("treats upstream redirect attempts as unavailable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new TypeError("Redirect mode is set to error")),
    );
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv());
    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toHaveProperty("error.code", "upstream_unavailable");
  });

  it("returns a timeout when the abort signal fires", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation((_url: URL, init: RequestInit) => {
        return new Promise((_resolve, reject) => {
          init.signal?.addEventListener("abort", () => {
            const error = new Error("Aborted");
            error.name = "AbortError";
            reject(error);
          });
        });
      }),
    );
    vi.useFakeTimers();
    const pending = worker.fetch(request("/v1/foods/123"), makeEnv());
    await vi.advanceTimersByTimeAsync(8_001);
    const response = await pending;
    expect(response.status).toBe(504);
    await expect(response.json()).resolves.toHaveProperty("error.code", "upstream_timeout");
  });

  it("returns a stable error when the secret is missing", async () => {
    const response = await worker.fetch(request("/v1/foods/123"), makeEnv({ USDA_API_KEY: "" }));
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toHaveProperty("error.code", "server_misconfigured");
  });

  it("fails closed when the global quota binding is missing", async () => {
    const env = makeEnv();
    // @ts-expect-error intentional misconfiguration for fail-closed coverage
    delete env.GLOBAL_USDA_QUOTA;
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request("/v1/foods/123"), env);
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toHaveProperty("error.code", "server_misconfigured");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("enforces the global quota before calling USDA", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(
      request("/v1/foods/123"),
      makeEnv({
        quota: makeQuotaBinding(async () =>
          Response.json(
            { allowed: false, remaining: 0, retryAfterSeconds: 42 },
            { status: 429 },
          ),
        ),
      }),
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("42");
    expect(upstream).not.toHaveBeenCalled();
  });
});

describe("GlobalUSDAQuota durable object", () => {
  it("stores only epoch hour counters and rejects over budget", async () => {
    const store = new Map<string, unknown>();
    const state = {
      storage: {
        async get<T>(key: string) {
          return store.get(key) as T | undefined;
        },
        async put(key: string, value: unknown) {
          store.set(key, value);
        },
      },
    } as unknown as DurableObjectState;

    const quota = new GlobalUSDAQuota(state);
    const first = await quota.fetch(new Request("https://quota/reserve", { method: "POST" }));
    expect(first.status).toBe(200);
    const firstBody = (await first.json()) as QuotaResponse;
    expect(firstBody.allowed).toBe(true);
    expect(firstBody.remaining).toBe(899);

    store.set("quota", { epochHour: Math.floor(Date.now() / 3_600_000), count: 900 });
    const blocked = await quota.fetch(new Request("https://quota/reserve", { method: "POST" }));
    expect(blocked.status).toBe(429);
    const blockedBody = (await blocked.json()) as QuotaResponse;
    expect(blockedBody.allowed).toBe(false);
    expect(blockedBody.remaining).toBe(0);
    expect(blockedBody.retryAfterSeconds).toBeGreaterThan(0);

    const stored = store.get("quota") as { epochHour: number; count: number };
    expect(Object.keys(stored).sort()).toEqual(["count", "epochHour"]);
  });
});
