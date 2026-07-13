import Foundation
import JustLogItCore

/// Persistence boundary for remembered USDA selections. Implementations must not invent nutrition.
protocol RememberedFoodStoring: AnyObject, Sendable {
  func load() -> RememberedFoodCatalog
  func save(_ catalog: RememberedFoodCatalog)
}

/// UserDefaults-backed catalog. Fail-open: corrupt data yields an empty catalog.
final class UserDefaultsRememberedFoodStore: RememberedFoodStoring, @unchecked Sendable {
  static let storageKey = "justlogit.rememberedFoods.v1"

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> RememberedFoodCatalog {
    guard let data = defaults.data(forKey: Self.storageKey) else {
      return RememberedFoodCatalog()
    }
    return (try? decoder.decode(RememberedFoodCatalog.self, from: data)) ?? RememberedFoodCatalog()
  }

  func save(_ catalog: RememberedFoodCatalog) {
    guard let data = try? encoder.encode(catalog) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }

  func clear() {
    defaults.removeObject(forKey: Self.storageKey)
  }
}
