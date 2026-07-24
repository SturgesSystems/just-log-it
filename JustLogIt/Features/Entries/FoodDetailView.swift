import JustLogItCore
import SwiftData
import SwiftUI

struct FoodDetailView: View {
  let food: RecognizedFoodRecord
  @EnvironmentObject private var appNavigation: AppNavigation

  var body: some View {
    List {
      Section {
        LabeledContent("Name", value: food.displayName)
        if let brand = food.brand, !brand.isEmpty {
          LabeledContent("Brand", value: brand)
        }
        if let fdcID = food.fdcID {
          LabeledContent("FDC ID", value: String(fdcID))
        }
        if let dataType = food.usdaDataType, !dataType.isEmpty {
          LabeledContent("USDA data type", value: dataType)
        }
      }

      Section("Usage") {
        LabeledContent("Times used", value: String(food.useCount))
        LabeledContent(
          "Last used",
          value: food.lastUsedAt.formatted(date: .abbreviated, time: .shortened)
        )
        if let hint = food.servingHint, !hint.isEmpty {
          LabeledContent("Serving hint", value: hint)
        }
      }

      if let nutrients = food.nutrients, !nutrients.isEmpty {
        Section("Last nutrition snapshot") {
          MacroSummaryView(nutrients: nutrients, showExtended: true)
            .padding(.vertical, 4)
        }
      }
    }
    .navigationTitle(food.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button {
        appNavigation.logAgain(food.displayName)
      } label: {
        Label("Log this food again", systemImage: "plus.circle.fill")
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.bar)
      .accessibilityIdentifier("log-food-again")
    }
  }
}
