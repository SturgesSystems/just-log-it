import JustLogItCore
import SwiftData
import SwiftUI

struct EntriesView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \FoodLogEntryRecord.consumedAt, order: .reverse)
  private var entries: [FoodLogEntryRecord]

  @State private var searchText = ""
  @State private var entryPendingDeletion: FoodLogEntryRecord?
  @State private var deletionError: String?
  let onLogFood: () -> Void

  init(onLogFood: @escaping () -> Void = {}) {
    self.onLogFood = onLogFood
  }

  private var filteredEntries: [FoodLogEntryRecord] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return entries }

    return entries.filter { entry in
      entry.displayName.localizedCaseInsensitiveContains(query)
        || entry.originalText.localizedCaseInsensitiveContains(query)
        || entry.brand?.localizedCaseInsensitiveContains(query) == true
    }
  }

  private var groupedEntries: [(date: Date, entries: [FoodLogEntryRecord])] {
    let calendar = Calendar.current
    return Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.consumedAt) }
      .map { (date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    Group {
      if entries.isEmpty {
        ContentUnavailableView {
          Label("No entries yet", systemImage: "fork.knife")
        } description: {
          Text("Foods you log will appear here, with their saved nutrition snapshots.")
        } actions: {
          Button("Log food", systemImage: "plus", action: onLogFood)
            .buttonStyle(.borderedProminent)
        }
      } else if filteredEntries.isEmpty {
        ContentUnavailableView {
          Label("No matching entries", systemImage: "magnifyingglass")
        } description: {
          Text("No foods match “\(searchText)”.")
        } actions: {
          Button("Clear search") { searchText = "" }
            .buttonStyle(.bordered)
        }
      } else {
        List {
          ForEach(groupedEntries, id: \.date) { group in
            Section(sectionTitle(for: group.date)) {
              ForEach(group.entries) { entry in
                NavigationLink {
                  EntryDetailView(entry: entry)
                } label: {
                  EntryRow(entry: entry)
                }
                .accessibilityIdentifier("entry-\(entry.id.uuidString)")
                .swipeActions {
                  Button("Delete", systemImage: "trash", role: .destructive) {
                    entryPendingDeletion = entry
                  }
                }
              }
            }
          }
        }
        .listStyle(.insetGrouped)
      }
    }
    .navigationTitle("Entries")
    .searchable(text: $searchText, prompt: "Food, brand, or description")
    .scrollDismissesKeyboard(.interactively)
    .alert(
      "Delete entry?", isPresented: deletionConfirmationPresented, presenting: entryPendingDeletion
    ) { entry in
      Button("Delete", role: .destructive) {
        Task { await delete(entry) }
      }
      Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
    } message: { entry in
      Text(
        "\u{201c}\(entry.displayName)\u{201d} will be removed from JustLogIt and, if applicable, Apple Health. This cannot be undone."
      )
    }
    .alert("Couldn\u{2019}t delete entry", isPresented: deletionErrorPresented) {
      Button("OK", role: .cancel) { deletionError = nil }
    } message: {
      Text(deletionError ?? "The entry could not be deleted.")
    }
  }

  private func sectionTitle(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
  }

  private var deletionConfirmationPresented: Binding<Bool> {
    Binding(
      get: { entryPendingDeletion != nil },
      set: { if !$0 { entryPendingDeletion = nil } }
    )
  }

  private var deletionErrorPresented: Binding<Bool> {
    Binding(
      get: { deletionError != nil },
      set: { if !$0 { deletionError = nil } }
    )
  }

  private func delete(_ entry: FoodLogEntryRecord) async {
    entryPendingDeletion = nil
    let outcome = await HealthSyncCoordinator.deleteEntry(entry, modelContext: modelContext)
    switch outcome {
    case .deleted:
      break
    case .pending(let message), .failed(let message):
      deletionError = message
    }
  }
}

private struct EntryRow: View {
  let entry: FoodLogEntryRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.displayName)
            .font(.headline)
            .lineLimit(2)
          if let brand = entry.brand, !brand.isEmpty {
            Text(brand)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 12)
        if let calories = entry.calories {
          VStack(alignment: .trailing, spacing: 0) {
            Text(calories.formatted(.number.precision(.fractionLength(0))))
              .font(.headline.monospacedDigit())
            Text("cal")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          metadata
          Spacer()
        }
        VStack(alignment: .leading, spacing: 3) { metadata }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text(entry.consumedAt, format: .dateTime.hour().minute())
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel)
  }

  private var rowAccessibilityLabel: String {
    var parts = [entry.displayName]
    if let brand = entry.brand, !brand.isEmpty {
      parts.append(brand)
    }
    if let calories = entry.calories {
      parts.append(
        "\(calories.formatted(.number.precision(.fractionLength(0)))) calories"
      )
    }
    parts.append(entry.quantityDisplay)
    if let protein = entry.protein {
      parts.append(
        "\(protein.formatted(.number.precision(.fractionLength(0...1)))) g protein"
      )
    }
    parts.append(entry.source.rawValue)
    parts.append(entry.consumedAt.formatted(.dateTime.hour().minute()))
    return parts.joined(separator: ", ")
  }

  @ViewBuilder
  private var metadata: some View {
    Text(entry.quantityDisplay)
    if let protein = entry.protein {
      Text("\(protein.formatted(.number.precision(.fractionLength(0...1)))) g protein")
    }
    Text(entry.source.rawValue)
  }
}

private struct EntryDetailView: View {
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
        if entry.isApproximate {
          Label("Quantity is approximate", systemImage: "tilde")
            .foregroundStyle(.secondary)
        }
      }

      Section("Original input") {
        Text(entry.originalText)
      }

      Section("Nutrition") {
        NutrientSummaryView(nutrients: entry.nutrients)
          .padding(.vertical, 4)
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

      if entry.source == .usda {
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
