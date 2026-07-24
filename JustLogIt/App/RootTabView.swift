import SwiftData
import SwiftUI

struct RootTabView: View {
  /// Shared with App Intents / Siri / deep links so pending handoffs survive bootstrap.
  @ObservedObject private var navigation = AppNavigation.shared
  @State private var healthLifecycleMessage: String?
  /// When true, the Health banner uses warning chrome (partial/full sync attention).
  @State private var healthLifecycleNeedsAttention = false
  @State private var isReconcilingHealth = false
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.usesVolatileStore) private var usesVolatileStore

  var body: some View {
    TabView(selection: $navigation.tab) {
      // Outline symbols so the system can apply the filled variant when selected.
      Tab("Log", systemImage: "fork.knife", value: AppNavigation.Tab.log) {
        NavigationStack {
          LogView(
            onOpenEntry: { navigation.openEntry($0) },
            onOpenFood: { navigation.openFood($0) }
          )
          .toolbarBackground(.bar, for: .navigationBar)
          .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
      }

      Tab("Entries", systemImage: "list.bullet.rectangle", value: AppNavigation.Tab.entries) {
        // EntriesView owns its NavigationStack + path for deep links.
        EntriesView(onLogFood: { navigation.tab = .log })
      }

      Tab("Settings", systemImage: "gearshape", value: AppNavigation.Tab.settings) {
        NavigationStack {
          SettingsView()
            .toolbarBackground(.bar, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
      }
    }
    // Liquid glass–friendly bar materials + minimize on scroll (iOS 27).
    // Tab values remain log / entries / settings for App Intents / deep links.
    .tabBarMinimizeBehavior(.onScrollDown)
    .toolbarBackground(.bar, for: .tabBar)
    .toolbarBackgroundVisibility(.visible, for: .tabBar)
    // Brand chrome; LaunchAccent is set on the window too for continuity.
    .tint(Color("LaunchAccent"))
    .environmentObject(navigation)
    .task {
      // Let the first interactive frame paint before Health reconciliation work.
      try? await Task.sleep(for: .milliseconds(300))
      await AppObservability.measure(.healthReconciliation) {
        await reconcileHealthIfActive()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await reconcileHealthIfActive() }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      VStack(spacing: 0) {
        if usesVolatileStore {
          Label(
            "Saving is unavailable because local storage couldn’t open. Fix storage and relaunch JustLogIt.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.black)
          .symbolRenderingMode(.hierarchical)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background {
            ZStack {
              Rectangle().fill(.ultraThinMaterial)
              Rectangle().fill(Color.orange.opacity(0.88))
            }
          }
          .accessibilityIdentifier("volatile-store-warning")
        }

        if let lifecycleMessage = healthLifecycleMessage {
          HStack(alignment: .top, spacing: 10) {
            Image(
              systemName: healthLifecycleNeedsAttention
                ? "exclamationmark.triangle.fill"
                : "checkmark.heart.fill"
            )
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(healthLifecycleNeedsAttention ? Color.orange : Color.pink)
            .accessibilityHidden(true)

            Text(lifecycleMessage)
              .font(.caption)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss", systemImage: "xmark") {
              healthLifecycleMessage = nil
              healthLifecycleNeedsAttention = false
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityHint("Hides this Apple Health status message")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background {
            ZStack {
              Rectangle().fill(.regularMaterial)
              if healthLifecycleNeedsAttention {
                Rectangle().fill(Color.orange.opacity(0.14))
              }
            }
          }
          .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("health-lifecycle-banner")
        }
      }
    }
  }

  private func reconcileHealthIfActive() async {
    guard scenePhase == .active, !isReconcilingHealth else { return }
    isReconcilingHealth = true
    let summary = await HealthSyncCoordinator.reconcile(modelContext: modelContext)
    if let message = summary.message {
      healthLifecycleMessage = message
      healthLifecycleNeedsAttention = summary.needsAttention
    }
    isReconcilingHealth = false
  }
}
