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
  @State private var cacheResultMessage: String?
  @State private var healthSettings = HealthSyncSettingsModel()

  var body: some View {
    List {
      Section("Food data") {
        LabeledContent("Provider", value: providerDisplayDescription)

        if configuration.providerDescription == "Not configured" {
          Label {
            Text("USDA search is unavailable. Manual nutrition entry still works.")
          } icon: {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }

        Button("Clear downloaded food cache", systemImage: "trash") {
          confirmsCacheClear = true
        }

        Text(
          "Clearing the cache does not delete logged entries. Food details will be downloaded again when needed."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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
          "Optional and off by default. JustLogIt requests write-only access and saves each supported nutrient from a confirmed food entry. Added sugar remains in JustLogIt because Apple Health has no separate added-sugar field."
        )
      }

      Section("Privacy") {
        Label("No accounts, analytics, or advertising", systemImage: "hand.raised")
        Text(
          "Food descriptions are interpreted on device. Your saved food log and nutrition history stay on this device."
        )
        Text(
          "When you search FoodData Central, only derived food search terms are sent to the configured USDA service. JustLogIt does not intentionally retain those searches on a server."
        )
      }

      Section("About") {
        LabeledContent("Version", value: versionDescription)
        LabeledContent("Food data", value: "USDA FoodData Central")
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

  private func clearCache() {
    let fileManager = FileManager.default
    let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    guard let directory = base?.appending(path: "JustLogItFoodData", directoryHint: .isDirectory)
    else {
      cacheResultMessage = "The food cache could not be located."
      return
    }

    guard fileManager.fileExists(atPath: directory.path()) else {
      cacheResultMessage = "The food cache is already empty."
      return
    }

    do {
      try fileManager.removeItem(at: directory)
      cacheResultMessage = "The downloaded food cache was cleared."
    } catch {
      cacheResultMessage = "The food cache could not be cleared. Please try again."
    }
  }

}
