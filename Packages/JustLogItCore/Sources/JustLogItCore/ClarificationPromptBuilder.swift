import Foundation

/// Builds the on-device model input for a clarification turn: it assembles the
/// facts (original message, current candidate, the question, the reply) rather
/// than stuffing the reply into a fake food name.
public enum ClarificationPromptBuilder {
  public static func parseInput(
    sourceText: String,
    priorProduct: String,
    question: String,
    answer: String
  ) -> String {
    let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    let product = priorProduct.trimmingCharacters(in: .whitespacesAndNewlines)
    let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = ["Food log conversation for USDA lookup:"]
    if !source.isEmpty {
      lines.append("Original user message: \(source)")
    }
    if !product.isEmpty {
      lines.append("Current food candidate (may be wrong or empty): \(product)")
    }
    if !asked.isEmpty {
      lines.append("Assistant asked: \(asked)")
    }
    lines.append("User replied: \(reply)")
    lines.append(
      "Use the original message plus the reply. If the reply does not name or refine a real food (dismissive, off-topic, or empty of food facts), leave productName empty and write clarificationPrompt asking for the food. Do not treat phrases like \"who cares\", \"idk\", \"whatever\", or \"n/a\" as food names."
    )
    return lines.joined(separator: "\n")
  }
}
