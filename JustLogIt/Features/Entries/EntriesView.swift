import JustLogItCore
import SwiftData
import SwiftUI

struct EntriesView: View {
  private enum Pane: String, CaseIterable, Identifiable {
    case logs = "Logs"
    case foods = "Foods"

    var id: Self { self }
  }

  @Environment(\.modelContext) private var modelContext
  @Query(sort: \FoodLogEntryRecord.consumedAt, order: .reverse)
  private var entries: [FoodLogEntryRecord]
  @Query(sort: \RecognizedFoodRecord.lastUsedAt, order: .reverse)
  private var recognizedFoods: [RecognizedFoodRecord]

  @State private var pane: Pane = .logs
  @State private var searchText = ""
  @State private var entryPendingDeletion: FoodLogEntryRecord?
  @State private var deletionError: String?
  @State private var navigationPath = NavigationPath()
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

  private var filteredFoods: [RecognizedFoodRecord] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return recognizedFoods }

    return recognizedFoods.filter { food in
      food.displayName.localizedCaseInsensitiveContains(query)
        || food.brand?.localizedCaseInsensitiveContains(query) == true
        || food.servingHint?.localizedCaseInsensitiveContains(query) == true
        || (food.fdcID.map { String($0).contains(query) } ?? false)
    }
  }

  private var groupedEntries: [(date: Date, entries: [FoodLogEntryRecord])] {
    let calendar = Calendar.current
    return Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.consumedAt) }
      .map { (date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack(spacing: 0) {
        Picker("Entries pane", selection: $pane) {
          ForEach(Pane.allCases) { pane in
            Text(pane.rawValue).tag(pane)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("entries-pane-picker")

        Group {
          switch pane {
          case .logs:
            logsContent
          case .foods:
            foodsContent
          }
        }
      }
      .navigationTitle("Entries")
      .navigationDestination(for: EntryRoute.self) { route in
        switch route {
        case .entry(let id):
          if let entry = entries.first(where: { $0.id == id }) {
            EntryDetailView(entry: entry)
          } else {
            ContentUnavailableView("Entry unavailable", systemImage: "questionmark.circle")
          }
        case .food(let id):
          if let food = recognizedFoods.first(where: { $0.id == id }) {
            FoodDetailView(food: food)
          } else {
            ContentUnavailableView("Food unavailable", systemImage: "questionmark.circle")
          }
        }
      }
      .searchable(
        text: $searchText,
        prompt: pane == .logs ? "Food, brand, or description" : "Name, brand, or FDC ID"
      )
      .scrollDismissesKeyboard(.interactively)
      .alert(
        "Delete entry?", isPresented: deletionConfirmationPresented,
        presenting: entryPendingDeletion
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
    .onReceive(NotificationCenter.default.publisher(for: AppNavigation.openEntry)) { note in
      guard let id = AppNavigation.entryID(from: note) else { return }
      pane = .logs
      navigationPath.append(EntryRoute.entry(id))
    }
    .onReceive(NotificationCenter.default.publisher(for: AppNavigation.openFood)) { note in
      guard let id = AppNavigation.foodID(from: note) else { return }
      pane = .foods
      navigationPath.append(EntryRoute.food(id))
    }
  }

  @ViewBuilder
  private var logsContent: some View {
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
              NavigationLink(value: EntryRoute.entry(entry.id)) {
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

  @ViewBuilder
  private var foodsContent: some View {
    if recognizedFoods.isEmpty {
      ContentUnavailableView {
        Label("No recognized foods yet", systemImage: "leaf")
      } description: {
        Text("Foods you confirm while logging are remembered here for quick reference.")
      } actions: {
        Button("Log food", systemImage: "plus", action: onLogFood)
          .buttonStyle(.borderedProminent)
      }
    } else if filteredFoods.isEmpty {
      ContentUnavailableView {
        Label("No matching foods", systemImage: "magnifyingglass")
      } description: {
        Text("No recognized foods match “\(searchText)”.")
      } actions: {
        Button("Clear search") { searchText = "" }
          .buttonStyle(.bordered)
      }
    } else {
      List {
        ForEach(filteredFoods) { food in
          NavigationLink(value: EntryRoute.food(food.id)) {
            RecognizedFoodRow(food: food)
          }
          .accessibilityIdentifier("recognized-food-\(food.id.uuidString)")
        }
      }
      .listStyle(.insetGrouped)
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

private enum EntryRoute: Hashable {
  case entry(UUID)
  case food(UUID)
}
