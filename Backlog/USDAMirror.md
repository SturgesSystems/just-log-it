# P3 — Cloud USDA mirror

## Trigger

Start only if live quota, upstream availability, search privacy, or offline-pack generation justifies the additional data pipeline.

## Feasibility spike

- Transform current USDA downloads into a minimal normalized schema
- Store raw release artifacts in R2
- Benchmark D1 FTS5 database and index size against the 10 GB limit
- Compare representative search quality with the USDA API
- Measure D1 rows read and p95 latency
- Prove blue/green database activation and rollback
- Document freshness differences between downloads and the live API

## Production work

- Signed/versioned release manifest
- Automated download, integrity, transform, and evaluation pipeline
- Atomic binding/version switch
- Previous-release rollback
- No request-derived storage or search logging
