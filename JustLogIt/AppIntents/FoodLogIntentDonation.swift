import AppIntents
import Foundation

/// Best-effort App Intent donation after a successful local food-log save.
///
/// Teaches Siri / Apple Intelligence when and what the person tends to log.
/// Donation never writes nutrition data and must not affect save UX.
enum FoodLogIntentDonation {
  /// Donates a `StartFoodLogIntent` populated from a confirmed entry.
  ///
  /// Skips UI testing. Swallows donation failures so save completion stays snappy.
  static func donateSuccessfulLog(
    foodDescription: String,
    consumedAt: Date,
    isUITesting: Bool = AppLaunchArgumentPolicy.current.isUITesting
  ) async {
    guard !isUITesting else { return }
    let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let intent = StartFoodLogIntent()
    intent.foodDescription = trimmed
    intent.consumedAt = consumedAt
    _ = try? await intent.donate()
  }

  /// Convenience for a saved `FoodLogEntryRecord`. Uses user-authored `originalText`.
  static func donateSuccessfulLog(for entry: FoodLogEntryRecord) async {
    await donateSuccessfulLog(
      foodDescription: entry.originalText,
      consumedAt: entry.consumedAt
    )
  }
}
