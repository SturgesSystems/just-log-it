import JustLogItCore
import SwiftData
import SwiftUI

struct FoodDetailView: View {
  let food: RecognizedFoodRecord

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
          NutrientSummaryView(nutrients: nutrients)
            .padding(.vertical, 4)
        }
      }
    }
    .navigationTitle(food.displayName)
    .navigationBarTitleDisplayMode(.inline)
  }
}
