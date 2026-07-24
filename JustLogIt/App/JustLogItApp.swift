import AppIntents
import SwiftData
import SwiftUI

@main
struct JustLogItApp: App {
  init() {
    // Register early so Siri / Shortcuts can resolve the handoff coordinator without
    // opening SwiftData or waiting for the first painted frame.
    registerJustLogItAppDependencies()
  }

  var body: some Scene {
    // Never open SwiftData inside `App.init` — a slow/stuck store open keeps the
    // system launch screen up forever. Bootstrap paints first, then loads the container.
    WindowGroup {
      BootstrapRootView()
        .background(Color(.systemBackground))
        .onOpenURL { url in
          // Buffer on AppNavigation.shared so cold-start survives SwiftData bootstrap.
          // No store open here — same PendingFoodLog path as Siri (source: .shortcut).
          guard let pending = DeepLinkRouter.parseFoodLog(from: url) else { return }
          AppNavigation.shared.beginPendingFoodLog(pending)
        }
    }
  }
}

/// First real frame after the launch screen. Builds the ModelContainer off the
/// critical path so a migration hiccup cannot pin the splash.
private struct BootstrapRootView: View {
  @StateObject private var bootstrap = ModelContainerBootstrap()
  @State private var launchTimeline = BootstrapLaunchTimeline()

  var body: some View {
    Group {
      if let container = bootstrap.container {
        RootTabView()
          .environment(\.usesVolatileStore, bootstrap.usesVolatileStore)
          .modelContainer(container)
          .onAppear(perform: recordInteractiveIfNeeded)
      } else if let bootError = bootstrap.bootError {
        ContentUnavailableView {
          Label("Couldn’t Start", systemImage: "exclamationmark.triangle")
        } description: {
          Text(bootError)
        } actions: {
          Button("Try Again") {
            bootstrap.retry(for: AppLaunchArgumentPolicy.current)
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        BootstrapLoadingView()
          .onAppear(perform: recordFirstFrameIfNeeded)
      }
    }
    // Start store open as soon as the root appears. Work is detached off MainActor;
    // this only schedules the Task after the loading chrome can paint.
    .task {
      bootstrap.startIfNeeded(for: AppLaunchArgumentPolicy.current)
    }
    .onAppear {
      // App Intent dependencies only — does not open SwiftData.
      registerJustLogItAppDependencies()
    }
  }

  private func recordFirstFrameIfNeeded() {
    guard let measurement = launchTimeline.markFirstFrame() else { return }
    AppObservability.recordBootstrapMilestone(
      measurement.milestone,
      duration: measurement.duration.value
    )
  }

  private func recordInteractiveIfNeeded() {
    guard let measurement = launchTimeline.markInteractive() else { return }
    AppObservability.recordBootstrapMilestone(
      measurement.milestone,
      duration: measurement.duration.value
    )
  }
}

/// Lightweight first frame while the store opens. Asset mark + quiet progress +
/// a short privacy line — no model, Health, parser, or store work on this path.
private struct BootstrapLoadingView: View {
  var body: some View {
    ZStack {
      Color(.systemBackground)
        .ignoresSafeArea()

      VStack(spacing: 20) {
        Image("LaunchMark")
          .resizable()
          .scaledToFit()
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .accessibilityHidden(true)

        VStack(spacing: 10) {
          ProgressView()
            .controlSize(.regular)
            .tint(Color("LaunchAccent"))

          Text("Starting…")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }

        Text("Your food log stays on this iPhone")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .padding(.top, 2)
      }
      .padding(.horizontal, 32)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Starting JustLogIt. Your food log stays on this iPhone.")
  }
}

/// Owns bootstrap publication on the main actor. A monotonically increasing
/// generation prevents a cancelled retry or a late, non-cooperative store open
/// from replacing a newer result.
@MainActor
final class ModelContainerBootstrap: ObservableObject {
  @Published private(set) var container: ModelContainer?
  @Published private(set) var usesVolatileStore = false
  @Published private(set) var bootError: String?

  private let builder: ModelContainerBootstrapBuilder
  private let clearRememberedFoods: @MainActor () -> Void
  private var generation: UInt = 0
  private var task: Task<Void, Never>?

  init(
    builder: ModelContainerBootstrapBuilder = ModelContainerBootstrapBuilder(),
    clearRememberedFoods: @escaping @MainActor () -> Void = {
      UserDefaultsRememberedFoodStore().clear()
    }
  ) {
    self.builder = builder
    self.clearRememberedFoods = clearRememberedFoods
  }

  func startIfNeeded(for mode: AppLaunchArgumentPolicy.Mode) {
    guard container == nil, bootError == nil, task == nil else { return }
    start(for: mode)
  }

  func retry(for mode: AppLaunchArgumentPolicy.Mode) {
    start(for: mode)
  }

  private func start(for mode: AppLaunchArgumentPolicy.Mode) {
    generation &+= 1
    let requestedGeneration = generation
    task?.cancel()
    task = nil
    container = nil
    // Drop any prior live-store handle so intents never read a half-torn-down container.
    TodayNutritionSnapshotSource.unbind()
    usesVolatileStore = false
    bootError = nil
    let started = ContinuousClock.now

    if mode.isUITesting {
      // UI tests reuse the simulator; start from a clean remembered-food store so
      // a pick saved by a prior run doesn't auto-select and skip the USDA picker.
      clearRememberedFoods()
      // Install Siri/deep-link-style pending food text before RootTabView mounts so
      // LogView.onAppear can consume it. No real Siri / App Intents required.
      installUITestingPendingFoodLogIfNeeded()
    }

    let builder = self.builder
    task = Task { [weak self] in
      do {
        let built = try await AppObservability.measure(.bootstrapContainerOpen) {
          try await builder.build(for: mode)
        }
        guard let self, requestedGeneration == self.generation, !Task.isCancelled else {
          return
        }
        self.container = built.container
        // Same process store only — intents may summarize without opening a second container.
        TodayNutritionSnapshotSource.bind(to: built.container)
        self.usesVolatileStore = built.usesVolatileStore
        self.task = nil
        AppObservability.recordBootstrap(
          built.category,
          duration: started.duration(to: .now)
        )
      } catch {
        guard let self, requestedGeneration == self.generation, !Task.isCancelled else {
          return
        }
        self.task = nil
        TodayNutritionSnapshotSource.unbind()
        AppObservability.recordBootstrap(.failed, duration: started.duration(to: .now))
        self.bootError =
          "Local storage couldn’t open. Delete and reinstall JustLogIt, or free some space and try again."
      }
    }
  }

  /// DEBUG / UI-testing only: seed `AppNavigation` with a pending food description so
  /// the Log composer shows Siri-style handoff without invoking App Intents.
  private func installUITestingPendingFoodLogIfNeeded() {
    #if DEBUG
      guard
        let description = AppLaunchArgumentPolicy.pendingFoodLogDescription(
          arguments: ProcessInfo.processInfo.arguments,
          environment: ProcessInfo.processInfo.environment,
          honorsDebugArguments: true
        )
      else { return }
      AppNavigation.shared.beginPendingFoodLog(
        PendingFoodLog(
          description: description,
          consumedAt: nil,
          source: .siri
        )
      )
    #endif
  }
}

private struct UsesVolatileStoreKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var usesVolatileStore: Bool {
    get { self[UsesVolatileStoreKey.self] }
    set { self[UsesVolatileStoreKey.self] = newValue }
  }
}
