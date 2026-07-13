# Architecture

JustLogIt separates probabilistic interpretation from deterministic nutrition work.

```text
SwiftUI feature state
        ↓
Application workflow
        ↓
Domain types and deterministic services
        ↓
Protocols
        ↓
Foundation Models / USDA / SwiftData implementations
```

The Foundation Model may identify food, brand, descriptors, and quantity language. It never supplies nutrition, ranks USDA records, selects a record, or performs persisted arithmetic.

`Packages/JustLogItCore` has no SwiftUI, SwiftData, FoundationModels, or HealthKit dependency and can be tested from Command Line Tools.
