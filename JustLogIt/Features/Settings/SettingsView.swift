import JustLogItCore
import SwiftUI

@MainActor
@Observable
final class HealthSyncSettingsModel {
  private let writer: any HealthNutritionWriting
  private let defaults: UserDefaults

  private(set) var isEnabled: Bool
  private(set) var isRequestingAccess = false
  private(set) var message: String?

  var isAvailable: Bool { writer.isAvailable }

  init(
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared,
    defaults: UserDefaults = .standard
  ) {
    self.writer = writer
    self.defaults = defaults
    isEnabled = defaults.bool(forKey: HealthSyncCoordinator.preferenceKey)
  }

  func setEnabled(_ enabled: Bool) async {
    guard !isRequestingAccess else { return }

    guard enabled else {
      defaults.set(false, forKey: HealthSyncCoordinator.preferenceKey)
      isEnabled = false
      message = "New entries will stay in JustLogIt only. Existing Health data is unchanged."
      return
    }

    guard writer.isAvailable else {
      message = "Apple Health isn’t available on this device."
      return
    }

    // Keep the durable preference off until the explicit authorization request succeeds.
    isRequestingAccess = true
    message = nil
    defer { isRequestingAccess = false }

    do {
      let summary = try await writer.requestAuthorization()
      guard summary.canWrite else {
        defaults.set(false, forKey: HealthSyncCoordinator.preferenceKey)
        isEnabled = false
        message = "Write access wasn’t granted. You can review access in Settings."
        return
      }

      defaults.set(true, forKey: HealthSyncCoordinator.preferenceKey)
      isEnabled = true
      message =
        summary.authorizedNutrientCount == summary.requestedNutrientCount
        ? "Ready to save supported nutrition from new entries."
        : "Ready. Apple Health will save the nutrient types you allowed."
    } catch {
      defaults.set(false, forKey: HealthSyncCoordinator.preferenceKey)
      isEnabled = false
      message =
        (error as? LocalizedError)?.errorDescription
        ?? "Apple Health access couldn’t be requested."
    }
  }
}

struct SettingsView: View {
  private let configuration = AppConfiguration.current

  @State private var confirmsCacheClear = false
  @State private var confirmsRememberedClear = false
  @State private var cacheResultMessage: String?
  @State private var foodCacheSizeDescription = "Empty"
  @State private var rememberedResultMessage: String?
  @State private var rememberedSelections: [RememberedFoodSelection] = []
  @State private var healthSettings = HealthSyncSettingsModel()
  private let rememberedFoods = UserDefaultsRememberedFoodStore()

  var body: some View {
    List {
      Section {
        LabeledContent {
          Text(providerDisplayDescription)
        } label: {
          Label("Provider", systemImage: "leaf")
        }

        if configuration.providerDescription == "Not configured" {
          Label {
            Text("USDA search is unavailable. Manual nutrition entry still works.")
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
        }

        LabeledContent {
          Text(foodCacheSizeDescription)
            .foregroundStyle(.secondary)
        } label: {
          Label("Downloaded food cache", systemImage: "externaldrive")
        }
        .accessibilityIdentifier("food-cache-size")

        Button("Clear downloaded food cache", systemImage: "externaldrive.badge.minus") {
          confirmsCacheClear = true
        }

        Button("Clear remembered food matches", systemImage: "clock.arrow.circlepath") {
          confirmsRememberedClear = true
        }
        .accessibilityIdentifier("clear-remembered-foods")
      } header: {
        Text("Food data")
      } footer: {
        Text(
          "Cache size is approximate. Clearing the cache does not delete logged entries; food details download again when needed. Remembered matches only reorder USDA results after you confirm a food — they never auto-select nutrition. Offline, previously downloaded foods may still match."
        )
      }

      if !rememberedSelections.isEmpty {
        Section {
          ForEach(rememberedSelections) { selection in
            VStack(alignment: .leading, spacing: 4) {
              Text(selection.displayName)
                .font(.body.weight(.medium))
              if let brand = selection.brand, !brand.isEmpty {
                Text(brand)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text("Lookup “\(selection.signature)” · FDC \(selection.fdcID)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rememberedAccessibilityLabel(selection))
            .accessibilityIdentifier("remembered-food-\(selection.fdcID)")
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button("Forget", role: .destructive) {
                forgetRemembered(selection)
              }
            }
          }
        } header: {
          Label("Remembered matches", systemImage: "bookmark")
        } footer: {
          Text("Swipe to forget a match. This does not delete log entries.")
        }
      }

      Section {
        Toggle(isOn: healthSyncBinding) {
          Label("Save nutrition to Apple Health", systemImage: "heart.fill")
        }
        .disabled(!healthSettings.isAvailable || healthSettings.isRequestingAccess)
        .accessibilityIdentifier("health-sync-toggle")

        if healthSettings.isRequestingAccess {
          HStack {
            ProgressView()
            Text("Requesting access…")
          }
        } else if !healthSettings.isAvailable {
          Label("Apple Health isn’t available on this device.", systemImage: "info.circle")
            .foregroundStyle(.secondary)
        } else if let message = healthSettings.message {
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Apple Health")
      } footer: {
        Text(
          "Optional and off by default. JustLogIt asks to write dietary nutrients, then saves each confirmed entry as one Food item in Apple Health (grouped calories, protein, carbs, fat, and related types you allow). Added sugar stays in JustLogIt only — Health has no separate field for it."
        )
      }

      Section {
        Label {
          Text("Say “Log food in JustLogIt”")
        } icon: {
          Image(systemName: "mic.fill")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Say Log food in JustLogIt")
        .accessibilityHint("Siri asks what you ate before opening JustLogIt for review")

        Label {
          Text("Opens JustLogIt for review — never auto-saves")
        } icon: {
          Image(systemName: "checkmark.shield")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opens JustLogIt for review — never auto-saves")
        .accessibilityHint("Siri only starts a log; you always confirm before nutrition is saved")

        Label {
          Text("Shortcuts lists “Log Food” after install")
        } icon: {
          Image(systemName: "square.grid.2x2")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shortcuts lists Log Food after install")
        .accessibilityHint("The Shortcuts app shows JustLogIt’s Log Food action after install")
      } header: {
        Text("Siri & Shortcuts")
      } footer: {
        Text(
          "Siri only supplies the spoken phrase and an optional time. Food interpretation stays on this device. JustLogIt opens so you can review before anything is saved — nutrition is never written without your confirmation. After install, the Shortcuts app shows JustLogIt’s “Log Food” action."
        )
      }

      Section {
        Label("No accounts, analytics, or advertising", systemImage: "hand.raised.fill")
        Label {
          Text(
            "Food descriptions are interpreted on device. Your saved food log and nutrition history stay on this device."
          )
        } icon: {
          Image(systemName: "iphone")
            .foregroundStyle(.secondary)
        }
        Label {
          Text(
            "When you search FoodData Central, only derived food search terms are sent to the configured USDA service. JustLogIt does not intentionally retain those searches on a server."
          )
        } icon: {
          Image(systemName: "network")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Privacy")
      } footer: {
        Text(
          "Siri and Shortcuts may pass a food phrase and optional time into JustLogIt. They do not choose foods or write nutrition for you."
        )
      }

      Section {
        LabeledContent {
          Text(versionDescription)
        } label: {
          Label("Version", systemImage: "info.circle")
        }
        LabeledContent {
          Text("USDA FoodData Central")
        } label: {
          Label("Food data", systemImage: "building.columns")
        }
      } header: {
        Text("About")
      }
    }
    .navigationTitle("Settings")
    .alert("Clear food cache?", isPresented: $confirmsCacheClear) {
      Button("Clear Cache", role: .destructive, action: clearCache)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your logged entries will not be affected.")
    }
    .alert("Food cache", isPresented: cacheResultPresented) {
      Button("OK", role: .cancel) { cacheResultMessage = nil }
    } message: {
      Text(cacheResultMessage ?? "")
    }
    .alert("Clear remembered matches?", isPresented: $confirmsRememberedClear) {
      Button("Clear Matches", role: .destructive, action: clearRememberedFoods)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Prior USDA ranking boosts will be forgotten. Logged entries stay on this device.")
    }
    .alert("Remembered matches", isPresented: rememberedResultPresented) {
      Button("OK", role: .cancel) { rememberedResultMessage = nil }
    } message: {
      Text(rememberedResultMessage ?? "")
    }
    .onAppear {
      reloadRememberedSelections()
      refreshFoodCacheSize()
    }
  }

  private var providerDisplayDescription: String {
    switch configuration.providerDescription {
    case "Privacy proxy":
      "USDA search (private connection)"
    case "Direct USDA (Debug)":
      "USDA search (debug)"
    default:
      configuration.providerDescription
    }
  }

  private var healthSyncBinding: Binding<Bool> {
    Binding(
      get: { healthSettings.isEnabled },
      set: { enabled in
        Task { await healthSettings.setEnabled(enabled) }
      }
    )
  }

  private var versionDescription: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    guard let build, !build.isEmpty else { return version }
    return "\(version) (\(build))"
  }

  private var cacheResultPresented: Binding<Bool> {
    Binding(
      get: { cacheResultMessage != nil },
      set: { if !$0 { cacheResultMessage = nil } }
    )
  }

  private var rememberedResultPresented: Binding<Bool> {
    Binding(
      get: { rememberedResultMessage != nil },
      set: { if !$0 { rememberedResultMessage = nil } }
    )
  }

  private func clearRememberedFoods() {
    rememberedFoods.clear()
    rememberedSelections = []
    rememberedResultMessage = "Remembered food matches were cleared."
  }

  private func reloadRememberedSelections() {
    rememberedSelections = rememberedFoods.load().rankedForDisplay()
  }

  private func forgetRemembered(_ selection: RememberedFoodSelection) {
    var catalog = rememberedFoods.load()
    catalog.remove(signature: selection.signature, fdcID: selection.fdcID)
    rememberedFoods.save(catalog)
    reloadRememberedSelections()
  }

  private func rememberedAccessibilityLabel(_ selection: RememberedFoodSelection) -> String {
    var parts = [selection.displayName]
    if let brand = selection.brand, !brand.isEmpty {
      parts.append(brand)
    }
    parts.append("lookup \(selection.signature)")
    parts.append("FDC \(selection.fdcID)")
    return parts.joined(separator: ", ")
  }

  private func refreshFoodCacheSize() {
    foodCacheSizeDescription = DiskCachedFoodDataProvider.approximateCacheSizeDescription()
  }

  private func clearCache() {
    let fileManager = FileManager.default
    let directory = DiskCachedFoodDataProvider.defaultCacheDirectory

    guard fileManager.fileExists(atPath: directory.path()) else {
      cacheResultMessage = "The food cache is already empty."
      refreshFoodCacheSize()
      return
    }

    do {
      try fileManager.removeItem(at: directory)
      cacheResultMessage = "The downloaded food cache was cleared."
    } catch {
      cacheResultMessage = "The food cache could not be cleared. Please try again."
    }
    refreshFoodCacheSize()
  }

}
