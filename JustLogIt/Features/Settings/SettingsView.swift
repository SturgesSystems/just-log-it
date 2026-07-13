import SwiftUI

struct SettingsView: View {
  private let configuration = AppConfiguration.current

  @State private var confirmsCacheClear = false
  @State private var cacheResultMessage: String?

  var body: some View {
    List {
      Section("Food data") {
        LabeledContent("Provider", value: configuration.providerDescription)

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
