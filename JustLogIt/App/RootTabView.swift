import SwiftUI

struct RootTabView: View {
  var body: some View {
    TabView {
      Tab("Log", systemImage: "plus.circle.fill") {
        NavigationStack {
          LogView()
        }
      }

      Tab("Entries", systemImage: "list.bullet.rectangle") {
        NavigationStack {
          EntriesView()
        }
      }

      Tab("Settings", systemImage: "gearshape") {
        NavigationStack {
          SettingsView()
        }
      }
    }
  }
}
