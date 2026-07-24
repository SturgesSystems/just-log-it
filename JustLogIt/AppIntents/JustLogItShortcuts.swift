import AppIntents

struct JustLogItShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartFoodLogIntent(),
      phrases: [
        "Log food in \(.applicationName)",
        "Add food to \(.applicationName)",
        "Log what I ate in \(.applicationName)",
        "Start a food log in \(.applicationName)",
      ],
      shortTitle: "Log Food",
      systemImageName: "fork.knife.circle"
    )
    AppShortcut(
      intent: GetTodayNutritionSummaryIntent(),
      phrases: [
        "How much have I eaten today in \(.applicationName)",
        "Today's nutrition in \(.applicationName)",
        "Show today's nutrition summary in \(.applicationName)",
        "What are my calories today in \(.applicationName)",
      ],
      shortTitle: "Today's Nutrition",
      systemImageName: "chart.bar.doc.horizontal"
    )
  }
}
