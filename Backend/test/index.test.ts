import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const env = { USDA_API_KEY: "test-secret" };
function request(path: string, init?: RequestInit): Request {
  return new Request(`https://proxy.example${path}`, init);
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("routing and validation", () => {
  it("rejects unknown routes", async () => {
    const response = await worker.fetch(request("/nope"), env);
    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: { code: "not_found", message: "Route not found." },
    });
  });

  it("requires POST for search", async () => {
    const response = await worker.fetch(request("/v1/foods/search"), env);
    expect(response.status).toBe(405);
    expect(response.headers.get("Allow")).toBe("POST");
  });

  it("rejects unknown fields and oversized page sizes without calling USDA", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    for (const body of [
      { query: "apple", unexpected: true },
      { query: "apple", pageSize: 26 },
      { query: "apple", dataTypes: ["Not real"] },
    ]) {
      const response = await worker.fetch(
        request("/v1/foods/search", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }),
        env,
      );
      expect(response.status).toBe(400);
      expect((await response.json()) as object).toHaveProperty("error.code", "invalid_request");
    }
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects query strings on public routes", async () => {
    const response = await worker.fetch(
      request("/v1/foods/123?format=abridged"),
      env,
    );
    expect(response.status).toBe(400);
  });
});

describe("USDA proxying", () => {
  it("normalizes and forwards an allowlisted search", async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ foods: [{ fdcId: 123 }] }), {
        headers: { "X-RateLimit-Remaining": "999" },
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
          pageSize: 25,
        }),
      }),
      env,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("X-RateLimit-Remaining")).toBe("999");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    const [url, init] = upstream.mock.calls[0] as [URL, RequestInit];
    expect(url.origin + url.pathname).toBe("https://api.nal.usda.gov/fdc/v1/foods/search");
    expect(url.searchParams.get("api_key")).toBe("test-secret");
    expect(JSON.parse(init.body as string)).toEqual({
      query: "greek yogurt",
      pageNumber: 2,
      pageSize: 25,
      dataType: ["Branded", "Foundation"],
    });
    expect(init.headers).toEqual({ Accept: "application/json", "Content-Type": "application/json" });
  });

  it("proxies food details with only controlled request headers", async () => {
    const upstream = vi.fn().mockResolvedValue(new Response(JSON.stringify({ fdcId: 123 })));
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(request("/v1/foods/123"), env);

    expect(response.status).toBe(200);
    const [url, init] = upstream.mock.calls[0] as [URL, RequestInit];
    expect(url.pathname).toBe("/fdc/v1/food/123");
    expect(init.headers).toEqual({ Accept: "application/json" });
  });

  it("normalizes upstream errors without forwarding their body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("upstream secret diagnostic", {
          status: 429,
          headers: { "Retry-After": "60", "X-Unrelated": "discard-me" },
        }),
      ),
    );

    const response = await worker.fetch(request("/v1/foods/123"), env);

    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(response.headers.get("X-Unrelated")).toBeNull();
    expect(await response.text()).not.toContain("upstream secret diagnostic");
  });

  it("returns a stable error when the secret is missing", async () => {
    const response = await worker.fetch(request("/v1/foods/123"), { USDA_API_KEY: "" });
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toHaveProperty("error.code", "server_misconfigured");
  });
});
