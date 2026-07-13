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
      Button("Delete", role: .destructive) { delete(entry) }
      Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
    } message: { entry in
      Text(
        "\u{201c}\(entry.displayName)\u{201d} will be removed from this device. This cannot be undone."
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

  private func delete(_ entry: FoodLogEntryRecord) {
    entryPendingDeletion = nil
    modelContext.delete(entry)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      deletionError = "Your entry is still saved. Please try again."
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

  let entry: FoodLogEntryRecord

  @State private var confirmsDeletion = false
  @State private var deletionError: String?

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
          if entry.healthSyncStatus == .failed {
            Button("Try Apple Health Again", systemImage: "arrow.clockwise") {
              Task {
                await HealthSyncCoordinator.syncIfEnabled(entry, modelContext: modelContext)
              }
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
            LabeledContent("Data type", value: dataType)
          }
          if let fdcID = entry.fdcID {
            LabeledContent("FDC ID", value: String(fdcID))
          }
          LabeledContent("Calculation", value: calculationDescription)
          if let grams = entry.consumedGrams {
            LabeledContent(
              "Consumed mass",
              value: "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g"
            )
          }
          if let multiplier = entry.servingMultiplier {
            LabeledContent(
              "Serving multiplier",
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
      Text("This entry will be removed from this device. This cannot be undone.")
    }
    .alert("Couldn\u{2019}t delete entry", isPresented: deletionErrorPresented) {
      Button("OK", role: .cancel) { deletionError = nil }
    } message: {
      Text(deletionError ?? "The entry could not be deleted.")
    }
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
    }
  }

  private var deletionErrorPresented: Binding<Bool> {
    Binding(
      get: { deletionError != nil },
      set: { if !$0 { deletionError = nil } }
    )
  }

  private func deleteEntry() {
    modelContext.delete(entry)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.rollback()
      deletionError = "Your entry is still saved. Please try again."
    }
  }
}
