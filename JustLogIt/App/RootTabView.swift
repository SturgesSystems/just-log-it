import SwiftData
import SwiftUI

struct RootTabView: View {
  private enum AppTab: Hashable {
    case log
    case entries
    case settings
  }

  @State private var selection: AppTab = .log
  @State private var healthLifecycleMessage: String?
  @State private var isReconcilingHealth = false
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.usesVolatileStore) private var usesVolatileStore

  var body: some View {
    TabView(selection: $selection) {
      Tab("Log", systemImage: "plus.circle.fill", value: .log) {
        NavigationStack {
          LogView()
        }
      }

      Tab("Entries", systemImage: "list.bullet.rectangle", value: .entries) {
        NavigationStack {
          EntriesView { selection = .log }
        }
      }

      Tab("Settings", systemImage: "gearshape", value: .settings) {
        NavigationStack {
          SettingsView()
        }
      }
    }
    .task { await reconcileHealthIfActive() }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await reconcileHealthIfActive() }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      VStack(spacing: 0) {
        if usesVolatileStore {
          Label(
            "Entries can’t be stored permanently right now.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.orange)
        }

        if let healthLifecycleMessage {
          HStack(spacing: 10) {
            Image(systemName: "heart.text.clipboard")
            Text(healthLifecycleMessage)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark") {
              self.healthLifecycleMessage = nil
            }
            .labelStyle(.iconOnly)
          }
          .font(.caption)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.regularMaterial)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func reconcileHealthIfActive() async {
    guard scenePhase == .active, !isReconcilingHealth else { return }
    isReconcilingHealth = true
    let summary = await HealthSyncCoordinator.reconcile(modelContext: modelContext)
    if let message = summary.message { healthLifecycleMessage = message }
    isReconcilingHealth = false
  }
}
