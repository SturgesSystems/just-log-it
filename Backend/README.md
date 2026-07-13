# JustLogIt USDA proxy

This Cloudflare Worker exposes the two FoodData Central operations used by JustLogIt while keeping the USDA API key out of the iOS application.

It is deliberately stateless: there is no database, cache, analytics integration, user identifier, or custom logging. Search request bodies are used only to service the current request. Worker observability and invocation logs are disabled in `wrangler.jsonc`.

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

Only `Retry-After` and standard `X-RateLimit-*` headers are copied from USDA. Upstream error bodies and unrelated headers are not returned.

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

The Worker constructs each USDA subrequest from scratch with only `Accept` and, for searches, `Content-Type` headers. It never forwards incoming client headers or identifiers. If the Worker is attached to a custom zone, also review that zone's Cloudflare Managed Transforms and privacy configuration before production release.
