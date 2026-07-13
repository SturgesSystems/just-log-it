import Foundation
import SwiftUI

/// Cross-tab navigation for opening a saved entry or recognized food from the log completion card.
@MainActor
final class AppNavigation: ObservableObject {
  enum Tab: Hashable {
    case log
    case entries
    case settings
  }

  @Published var tab: Tab = .log
  @Published var selectedEntryID: UUID?
  @Published var selectedFoodID: UUID?

  static let openEntry = Notification.Name("JustLogItOpenEntry")
  static let openFood = Notification.Name("JustLogItOpenFood")

  private static let idKey = "id"

  func openEntry(_ id: UUID) {
    selectedEntryID = id
    tab = .entries
    NotificationCenter.default.post(
      name: Self.openEntry,
      object: nil,
      userInfo: [Self.idKey: id]
    )
  }

  func openFood(_ id: UUID) {
    selectedFoodID = id
    tab = .entries
    NotificationCenter.default.post(
      name: Self.openFood,
      object: nil,
      userInfo: [Self.idKey: id]
    )
  }

  static func entryID(from note: Notification) -> UUID? {
    note.userInfo?[idKey] as? UUID
  }

  static func foodID(from note: Notification) -> UUID? {
    note.userInfo?[idKey] as? UUID
  }
}
