import SwiftData
import SwiftUI

struct RootTabView: View {
  @StateObject private var navigation = AppNavigation()
  @State private var healthLifecycleMessage: String?
  @State private var isReconcilingHealth = false
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.usesVolatileStore) private var usesVolatileStore

  var body: some View {
    TabView(selection: $navigation.tab) {
      Tab("Log", systemImage: "plus.circle.fill", value: AppNavigation.Tab.log) {
        NavigationStack {
          LogView(
            onOpenEntry: { navigation.openEntry($0) },
            onOpenFood: { navigation.openFood($0) }
          )
        }
      }

      Tab("Entries", systemImage: "list.bullet.rectangle", value: AppNavigation.Tab.entries) {
        // EntriesView owns its NavigationStack + path for deep links.
        EntriesView(onLogFood: { navigation.tab = .log })
      }

      Tab("Settings", systemImage: "gearshape", value: AppNavigation.Tab.settings) {
        NavigationStack {
          SettingsView()
        }
      }
    }
    // Force non-black chrome on first paint before tab content settles.
    .tint(.accentColor)
    .environmentObject(navigation)
    .task {
      // Let the first frame paint before Health reconciliation work.
      try? await Task.sleep(for: .milliseconds(300))
      await reconcileHealthIfActive()
    }
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
