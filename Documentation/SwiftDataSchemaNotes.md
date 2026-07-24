# SwiftData schema notes

Audit of JustLogIt persistence models, open/recovery policy, and migration stance.
Source of truth: `JustLogIt/Persistence/` (not historical checkpoints or handoff bullets).

## Models in the active schema

`ModelContainerFactory.schema` includes three `@Model` types:

| Model | File | Role |
| --- | --- | --- |
| `FoodLogEntryRecord` | `FoodLogEntryRecord.swift` | Confirmed food log entry (single or composite) |
| `HealthDeletionTombstone` | `FoodLogEntryRecord.swift` | Pending Apple Health deletion for a removed entry |
| `RecognizedFoodRecord` | `RecognizedFoodRecord.swift` | Reusable food identity independent of entry history |

Store location (persistent path):

- Directory: Application Support / `JustLogIt`
- File: `default.store`
- CloudKit: `.none`

There is **no** `VersionedSchema`, **no** `SchemaMigrationPlan`, and **no** schema-epoch wipe in the current tree.

---

## `FoodLogEntryRecord`

Stable identity: `@Attribute(.unique) var id: UUID`.

### Fields

| Property | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique entry identity |
| `createdAt` | `Date` | Insert time |
| `consumedAt` | `Date` | When eaten (drives Entries grouping) |
| `modifiedAt` | `Date` | Last local edit |
| `originalText` | `String` | User-authored input |
| `displayName` | `String` | UI title |
| `brand` | `String?` | Optional |
| `quantityDisplay` | `String` | Human amount string |
| `isApproximate` | `Bool` | Approximate quantity flag |
| `sourceRawValue` | `String` | `EntrySource` raw (`USDA` / `Manual`); unknown → `.manual` |
| `fdcID` | `Int?` | USDA FDC id when grounded |
| `usdaDescription` | `String?` | USDA description |
| `usdaDataType` | `String?` | USDA data type label |
| `calculationBasisRawValue` | `String` | `CalculationBasis` raw; unknown → `.manual` |
| `servingMultiplier` | `Double?` | Servings logged |
| `consumedGrams` | `Double?` | Grams when basis is grams |
| `nutrientsData` | `Data` | JSON `[NutrientAmount]`; corrupt → `[]` |
| `healthSyncStatusRawValue` | `String` | Default `.notRequested` |
| `healthSyncVersion` | `Int` | Default `1` |
| `healthSyncedAt` | `Date?` | |
| `healthSyncError` | `String?` | |
| `healthSyncRetryCount` | `Int` | Default `0` |
| `healthSyncNextRetryAt` | `Date?` | |
| `recognizedFoodID` | `UUID?` | Soft link to `RecognizedFoodRecord.id` (not a SwiftData relationship) |
| `isComposite` | `Bool?` | **Optional** for lightweight migration from pre-composite stores |
| `componentPayload` | `Data?` | JSON `[CompositeComponentSnapshot]`; corrupt → `[]` |

### Computed / helpers

- `isCompositeEntry`: `isComposite == true || !components.isEmpty`
- `source`, `calculationBasis`, `healthSyncStatus`: raw-value bridges with safe defaults
- `nutrients`, `components`: decode fail-closed
- `calories` / `protein`: convenience from nutrients

### Composite payload shape

`CompositeComponentSnapshot` (JustLogItCore): `displayName`, `brand?`, `fdcID?`, `quantityDisplay`, `nutrients`, `isApproximate`.

Root entry stores **aggregated** `nutrientsData` plus optional per-component snapshots. Single-food entries leave composite fields inactive (`isComposite` false / nil, empty components).

### Health deletion tombstone

| Property | Type |
| --- | --- |
| `entryID` | `UUID` (unique) |
| `healthSyncVersion` | `Int` |
| `createdAt` | `Date` |
| `retryCount` | `Int` |
| `nextRetryAt` | `Date?` |
| `lastError` | `String?` |

---

## `RecognizedFoodRecord`

Stable identity: `@Attribute(.unique) var id: UUID`.

Independent of entry history: deleting an entry does not remove the food; forgetting a food does not erase entries.

| Property | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique food identity |
| `displayName` | `String` | |
| `brand` | `String?` | |
| `fdcID` | `Int?` | Preferred upsert key when `> 0` |
| `usdaDataType` | `String?` | |
| `lastUsedAt` | `Date` | |
| `useCount` | `Int` | Clamped to ≥ 1 on init |
| `servingHint` | `String?` | Last quantity display |
| `nutrientsData` | `Data?` | Optional last nutrition snapshot (not authoritative for new logs) |
| `normalizedName` | `String` | Lookup key via `FoodLookupSignature.normalize` |

Upsert: match by FDC ID, else by `normalizedName`. Linked from the entry via `recognizedFoodID` inside `FoodLogRepository.commit` / `FoodLogSaveTransaction`.

---

## UI field assumptions (checked)

Entries / detail / recent foods only use fields that exist on the models:

- List rows: name, brand, calories/macros from nutrients, quantity, composite badge, source, time
- Entry detail: quantity, times, source, composite sections, original text, Health section, USDA section (non-composite)
- Food detail: name, brand, FDC, data type, use count, last used, serving hint, optional nutrients
- Recent foods bar: `displayName` / `brand` from recognized rows

No missing schema field was found that UI already assumes. Decode and enum bridges fail closed so corrupt payloads do not crash.

---

## Store open policy (no wipe)

`ModelContainerFactory.make` order:

1. **`forceVolatileStore`** (DEBUG UI: `-ui-testing` + `-ui-testing-volatile-store`)
   In-memory container; `usesVolatileStore = true`.

2. **`isUITesting`** (DEBUG UI: `-ui-testing` alone)
   In-memory container; `usesVolatileStore = false` so tests do not show the volatile banner unless forced.

3. **Persistent open** at Application Support / `JustLogIt` / `default.store` (or injected `persistentStoreURL`).
   Parent directory is created first.

4. **On persistent open failure**
   - **Does not delete** the failed store.
   - Falls back to in-memory; `usesVolatileStore = true`.
   - Original bytes remain for a future migration or recovery.

5. **`makeEmergencyVolatile`**
   Used only when the bootstrap builder’s normal path throws (including fallback construction). In-memory; category `emergencyVolatile`.

### What is *not* present (historical contrast)

An earlier checkpoint (`ModelContainerFactory` epoch 2) implemented:

- UserDefaults key `justlogit.swiftdata.schemaEpoch` with `schemaEpoch = 2` (RecognizedFood + composites)
- One-time **destroy** of Application Support store files when the epoch advanced
- On open failure: **wipe and retry**, then volatile

That path was **removed**. Current policy matches quality-hardening intent: a failed open must preserve store bytes and surface non-durable mode. Do not reintroduce epoch wipe or destroy-on-failure without an explicit, tested recovery plan.

Handoff line “Schema epoch wipe for RecognizedFood + composites if needed” in `CONTINUATION_HANDOFF.md` is **stale** relative to the current factory.

### Volatile UX

When `usesVolatileStore` is true:

- Orange banner in `RootTabView` (`volatile-store-warning`)
- Confirm and manual save paths refuse durable save (`guard !usesVolatileStore`)
- Warnings on confirmation / manual entry cards

Bootstrap categories (observability only): `persistent`, `testingMemory`, `forcedVolatile`, `fallbackVolatile`, `emergencyVolatile`, `failed`.

---

## Migration stance

### Lightweight (current)

New **optional** columns and new entity types rely on SwiftData lightweight migration when the store can open:

- `recognizedFoodID`, `isComposite`, `componentPayload` on entries
- Health sync fields with property defaults where non-optional
- Entire `RecognizedFoodRecord` entity for older entry-only stores

`isComposite` is intentionally `Bool?` so pre-composite rows read as non-composite via `isCompositeEntry`.

### Explicit versioned migrations (deferred)

Do **not** invent a nominal `SchemaMigrationPlan` (V1→V4 style) over the present model types:

- Historical commits changed the persisted shape while retaining SwiftData’s default schema version `1.0.0`
- A conventional version chain may not match real on-device store checksums and can strand data

Before shipping to external users who already hold data, capture real store fixtures per shipped shape, then design migration only against those fixtures. See `QUALITY_HARDENING_HANDOFF.md` §6.

### Disk close/reopen coverage (present)

`FoodLogEntryRecordTests` reopen through a fresh `ModelContainerFactory` disk fixture for:

- Confirmed USDA entry + recognized food + Health fields
- Manual-equivalent entry + recognized food
- Two-component composite + payload + recognized food

Open-failure preservation: `AppConfigurationTests.testPersistentStoreOpenFailurePreservesOriginalPathAndUsesVolatileStore`.

---

## Save boundary

`FoodLogRepository.save` / `FoodLogSaveTransaction.save`:

1. Insert entry
2. Upsert `RecognizedFoodRecord`
3. Set `entry.recognizedFoodID`
4. `context.save()`

On any failure: `context.rollback()` so partial inserts do not linger.

HealthKit writes are **post-save** (`HealthSyncCoordinator`); Health failure never rolls back the local entry.

---

## Recommendations (no code change required from this audit)

1. **Keep** preserve-on-failure + visible volatile mode; do not restore schema-epoch wipe.
2. **Keep** optional composite fields and fail-closed JSON decoding.
3. **Do not** add `VersionedSchema` / `SchemaMigrationPlan` until real legacy store fixtures exist.
4. When adding model properties: prefer optionals or property defaults; never add required columns without a proven migration.
5. Treat USDA disk cache versioning (`DiskCachedFoodDataProvider.cacheSchemaVersion`) as separate from SwiftData entry history (disposable acceleration only).

---

## File map

| Path | Purpose |
| --- | --- |
| `JustLogIt/Persistence/FoodLogEntryRecord.swift` | Entry + Health tombstone + `EntrySource` / `HealthSyncStatus` |
| `JustLogIt/Persistence/RecognizedFoodRecord.swift` | Food identity + upsert |
| `JustLogIt/Persistence/FoodLogRepository.swift` | Transactional save |
| `JustLogIt/Persistence/ModelContainerFactory.swift` | Schema, open, volatile fallback, bootstrap builder |
| `JustLogIt/App/JustLogItApp.swift` | Bootstrap root, `usesVolatileStore` environment |
| `Packages/JustLogItCore/.../CompositeFoods.swift` | Component snapshot + aggregation |
