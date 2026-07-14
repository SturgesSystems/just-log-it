import Testing

@testable import JustLogItCore

@Test func clarificationPromptIncludesAllFactsAndGuardrail() {
  let prompt = ClarificationPromptBuilder.parseInput(
    sourceText: "  three eggs  ",
    priorProduct: "eggs",
    question: "How were they cooked?",
    answer: "scrambled"
  )
  #expect(prompt.contains("Original user message: three eggs"))
  #expect(prompt.contains("Current food candidate (may be wrong or empty): eggs"))
  #expect(prompt.contains("Assistant asked: How were they cooked?"))
  #expect(prompt.contains("User replied: scrambled"))
  #expect(prompt.contains("who cares"))  // dismissive-reply guardrail is present
}

@Test func clarificationPromptOmitsEmptyOptionalFacts() {
  let prompt = ClarificationPromptBuilder.parseInput(
    sourceText: "",
    priorProduct: "   ",
    question: "",
    answer: "an apple"
  )
  #expect(!prompt.contains("Original user message:"))
  #expect(!prompt.contains("Current food candidate"))
  #expect(!prompt.contains("Assistant asked:"))
  #expect(prompt.contains("User replied: an apple"))
}
