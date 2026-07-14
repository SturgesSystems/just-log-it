import JustLogItCore
import SwiftData
import SwiftUI

struct EntryDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL

  let entry: FoodLogEntryRecord

  @State private var confirmsDeletion = false
  @State private var deletionError: String?
  @State private var healthRetryOutcome: HealthSyncOutcome?
  @State private var isRetryingHealthSync = false

  var body: some View {
    List {
      Section {
        LabeledContent("Amount", value: entry.quantityDisplay)
        LabeledContent(
          "Logged", value: entry.consumedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent("Source", value: entry.source.rawValue)
        if entry.isCompositeEntry {
          Label("Composite meal", systemImage: "square.stack.3d.up")
            .foregroundStyle(.secondary)
        }
        if entry.isApproximate {
          Label("Quantity is approximate", systemImage: "tilde")
            .foregroundStyle(.secondary)
        }
      }

      Section("Original input") {
        Text(entry.originalText)
      }

      if entry.isCompositeEntry, !entry.components.isEmpty {
        ForEach(Array(entry.components.enumerated()), id: \.offset) { index, component in
          Section {
            CompositeComponentNutritionView(component: component, showExtended: true)
              .padding(.vertical, 4)
            if let fdcID = component.fdcID {
              LabeledContent("FDC ID", value: String(fdcID))
            }
          } header: {
            Text(entry.components.count > 1 ? "Item \(index + 1)" : "Item")
          }
        }

        Section("Meal total") {
          MacroSummaryView(nutrients: entry.nutrients, showExtended: true)
            .padding(.vertical, 4)
          DisclosureGroup("All nutrients") {
            NutrientSummaryView(nutrients: entry.nutrients)
              .padding(.top, 8)
          }
        }
      } else {
        Section("Nutrition") {
          NutrientSummaryView(nutrients: entry.nutrients)
            .padding(.vertical, 4)
        }
      }

      if entry.healthSyncStatus != .notRequested {
        Section("Apple Health") {
          LabeledContent("Status", value: healthStatusDescription)
          if let syncedAt = entry.healthSyncedAt {
            LabeledContent(
              "Updated", value: syncedAt.formatted(date: .abbreviated, time: .shortened))
          }
          if let error = entry.healthSyncError, entry.healthSyncStatus != .synced {
            Text(error)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if entry.healthSyncStatus == .failed || entry.healthSyncStatus == .denied {
            Button("Try Apple Health Again", systemImage: "arrow.clockwise") {
              retryHealthSync()
            }
            .disabled(isRetryingHealthSync)

            if isRetryingHealthSync {
              HStack {
                ProgressView()
                Text("Checking Apple Health access…")
              }
              .foregroundStyle(.secondary)
            }
          }
        }
      }

      if entry.source == .usda, !entry.isCompositeEntry {
        Section("USDA FoodData Central") {
          if let description = entry.usdaDescription {
            LabeledContent("Food", value: description)
          }
          if let dataType = entry.usdaDataType {
            LabeledContent("Data type", value: humanizedDataType(dataType))
          }
          if let fdcID = entry.fdcID {
            LabeledContent("FDC ID", value: String(fdcID))
          }
          LabeledContent("Calculation", value: calculationDescription)
          if let grams = entry.consumedGrams {
            LabeledContent(
              "Amount (grams)",
              value: "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g"
            )
          }
          if let multiplier = entry.servingMultiplier {
            LabeledContent(
              "Servings logged",
              value: multiplier.formatted(.number.precision(.fractionLength(0...2)))
            )
          }
        }
      }
    }
    .navigationTitle(entry.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Delete", systemImage: "trash", role: .destructive) {
          confirmsDeletion = true
        }
      }
    }
    .alert("Delete entry?", isPresented: $confirmsDeletion) {
      Button("Delete", role: .destructive, action: deleteEntry)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This entry will be removed from JustLogIt and, if applicable, Apple Health. This cannot be undone."
      )
    }
    .alert("Couldn\u{2019}t delete entry", isPresented: deletionErrorPresented) {
      Button("OK", role: .cancel) { deletionError = nil }
    } message: {
      Text(deletionError ?? "The entry could not be deleted.")
    }
    .alert("Apple Health", isPresented: healthRetryOutcomePresented) {
      if healthRetryOutcome?.offersSettingsRecovery == true {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
          healthRetryOutcome = nil
        }
      }
      Button("OK", role: .cancel) { healthRetryOutcome = nil }
    } message: {
      Text(healthRetryOutcome?.message ?? "Apple Health couldn’t be updated.")
    }
  }

  private func humanizedDataType(_ dataType: String) -> String {
    let cleaned = dataType.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.localizedCaseInsensitiveContains("branded") { return "Branded" }
    if cleaned.localizedCaseInsensitiveContains("foundation") { return "Foundation food" }
    if cleaned.localizedCaseInsensitiveContains("survey") { return "Survey" }
    if cleaned.localizedCaseInsensitiveContains("sr legacy") { return "SR Legacy" }
    if cleaned.localizedCaseInsensitiveContains("experimental") { return "Experimental" }
    return cleaned
  }

  private var calculationDescription: String {
    switch entry.calculationBasis {
    case .grams:
      "Per 100 grams"
    case .servings:
      "Per USDA serving"
    case .manual:
      "Manual nutrition"
    }
  }

  private var healthStatusDescription: String {
    switch entry.healthSyncStatus {
    case .notRequested: "Not enabled"
    case .pending: "Waiting to sync"
    case .synced: "Saved"
    case .denied: "Access not granted"
    case .failed: "Needs attention"
    case .deletionPending: "Deletion pending"
    }
  }

  private var deletionErrorPresented: Binding<Bool> {
    Binding(
      get: { deletionError != nil },
      set: { if !$0 { deletionError = nil } }
    )
  }

  private var healthRetryOutcomePresented: Binding<Bool> {
    Binding(
      get: { healthRetryOutcome != nil },
      set: { if !$0 { healthRetryOutcome = nil } }
    )
  }

  private func retryHealthSync() {
    isRetryingHealthSync = true
    Task {
      healthRetryOutcome = await HealthSyncCoordinator.retry(
        entry, modelContext: modelContext)
      isRetryingHealthSync = false
    }
  }

  private func deleteEntry() {
    Task {
      let outcome = await HealthSyncCoordinator.deleteEntry(entry, modelContext: modelContext)
      switch outcome {
      case .deleted:
        dismiss()
      case .pending(let message), .failed(let message):
        deletionError = message
      }
    }
  }
}
