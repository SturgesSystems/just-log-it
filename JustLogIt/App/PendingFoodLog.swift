import Foundation

/// Typed handoff for a reviewed food log started outside (or inside) the Log tab.
struct PendingFoodLog: Sendable, Equatable {
  let description: String
  let consumedAt: Date?
  let source: Source

  enum Source: Sendable, Equatable {
    case siri, shortcut, inApp
  }
}
