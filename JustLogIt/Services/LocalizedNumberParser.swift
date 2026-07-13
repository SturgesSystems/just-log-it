import Foundation

struct LocalizedNumberParser: Sendable {
  enum Minimum: Sendable {
    case zero
    case greaterThanZero
  }

  private let decimalSeparator: String
  private let groupingSeparator: String?

  init(locale: Locale = .current) {
    decimalSeparator = locale.decimalSeparator ?? "."
    let grouping = locale.groupingSeparator
    groupingSeparator = grouping == decimalSeparator ? nil : grouping
  }

  func parse(_ text: String, minimum: Minimum) -> Double? {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    var sign = ""
    if value.hasPrefix("+") || value.hasPrefix("-") {
      sign = String(value.removeFirst())
    }
    guard !value.isEmpty else { return nil }

    let decimalParts = value.components(separatedBy: decimalSeparator)
    guard decimalParts.count <= 2 else { return nil }
    let integerPart = decimalParts[0]
    let fractionPart = decimalParts.count == 2 ? decimalParts[1] : nil
    guard !integerPart.isEmpty || !(fractionPart?.isEmpty ?? true) else { return nil }
    guard integerPart.isEmpty || isValidInteger(integerPart) else { return nil }
    guard fractionPart.map({ $0.isEmpty || isASCIIDigits($0) }) ?? true else { return nil }

    let ungroupedInteger =
      groupingSeparator.map {
        integerPart.replacingOccurrences(of: $0, with: "")
      } ?? integerPart
    let normalizedInteger = ungroupedInteger.isEmpty ? "0" : ungroupedInteger
    let normalized =
      sign + normalizedInteger + (fractionPart.map { ".\($0)" } ?? "")
    guard let result = Double(normalized), result.isFinite else { return nil }
    switch minimum {
    case .zero:
      return result >= 0 ? result : nil
    case .greaterThanZero:
      return result > 0 ? result : nil
    }
  }

  private func isValidInteger(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    guard let groupingSeparator, value.contains(groupingSeparator) else {
      return isASCIIDigits(value)
    }
    let groups = value.components(separatedBy: groupingSeparator)
    guard let first = groups.first, (1...3).contains(first.count), isASCIIDigits(first) else {
      return false
    }
    return groups.dropFirst().allSatisfy { $0.count == 3 && isASCIIDigits($0) }
  }

  private func isASCIIDigits(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
  }
}
