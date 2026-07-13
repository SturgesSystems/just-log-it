# JustLogIt USDA proxy

This Cloudflare Worker exposes the two FoodData Central operations used by JustLogIt while keeping the USDA API key out of the iOS application.

The Worker is intentionally narrow:

- No application database, cache, analytics SDK, or user identifier storage
- Search request bodies are used only to service the current request
- Worker observability and invocation logs are disabled in `wrangler.jsonc`
- USDA authentication is sent only as an `X-Api-Key` request header, never as a URL query parameter
- Upstream fetch uses `redirect: "error"` so a redirect cannot carry the credential
- Successful upstream responses must be `application/json` and are capped at 2 MiB
- The request/response timeout covers body consumption, not only headers
- A singleton Durable Object under the constant name `global` enforces a shared budget of 900 USDA requests per hour

The Durable Object stores only `{ epochHour, count }`. It does not store food queries, IP addresses, or user identifiers. If the quota binding is missing or unavailable, the Worker fails closed.

This repository state is not a deployed production system. Deployment, Cloudflare log/transform audit, route verification, and rollback drills remain launch gates.

## Routes

### `POST /v1/foods/search`

Requires `Content-Type: application/json` and accepts only:

```json
{
  "query": "greek yogurt",
  "dataTypes": ["Branded", "Foundation"],
  "page": 1,
  "pageSize": 20
}
```

`query` is limited to 200 characters, `page` to 1–100, and `pageSize` to 1–25. `dataTypes`, when present, is limited to FoodData Central's known data types. Unknown fields are rejected.

### `GET /v1/foods/:fdcId`

`fdcId` must be a positive integer. Query parameters are rejected on both routes.

Errors have a stable shape:

```json
{
  "error": {
    "code": "rate_limited",
    "message": "Food search is temporarily busy. Please try again later."
  }
}
```

Only `Retry-After` and standard `X-RateLimit-*` headers are copied from USDA. Upstream error bodies, credentials, URLs, and unrelated headers are not returned.

## Local development

Prerequisites: Node.js and a USDA FoodData Central API key.

```sh
npm install
cp .dev.vars.example .dev.vars
```

Set `USDA_API_KEY` in `.dev.vars`, then run:

```sh
npm run dev
```

The local secret file is ignored by Git. Run checks with:

```sh
npm run check
npm test
```

## Deploy

Authenticate Wrangler and create the encrypted secret binding:

```sh
npx wrangler login
npx wrangler secret put USDA_API_KEY
npm run deploy
```

Do not put the key in `wrangler.jsonc`, source control, an Xcode configuration, or the app binary.

After deployment, confirm in the Cloudflare dashboard that Workers Logs, Logpush, and any account-level request logging are disabled for this Worker. Do not add `console.log` calls containing URLs, request headers, bodies, or USDA responses. Cloudflare still transiently processes network metadata required to deliver requests; the product privacy policy should describe Cloudflare and USDA as service providers.

Also verify:

1. The Durable Object binding and migration applied.
2. Over-budget requests return the stable `rate_limited` error without calling USDA.
3. Rollback and secret rotation still work.
4. Zone Managed Transforms do not inject visitor identifiers into upstream requests.

The USDA public limit is 1,000 requests/hour per IP. Because Worker egress can share an IP, the global Durable Object budget is set to 900/hour to leave operational headroom. A per-colocation Rate Limit binding alone is not a global quota guarantee.
