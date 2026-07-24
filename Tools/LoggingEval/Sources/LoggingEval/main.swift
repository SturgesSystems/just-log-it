import Foundation
import JustLogItCore

@available(macOS 27.0, *)
@main
enum LoggingEvalMain {
  static func main() async {
    do {
      try await run()
    } catch {
      fputs("error: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return
    }

    let corpusPath = value(for: "--corpus", in: args)
    let parsedJSONPath = value(for: "--parsed-json", in: args)
    let forceFake = args.contains("--fake-parse")
    let includeInput = args.contains("--include-input")
    let promptProfile = try parsePromptProfile(value(for: "--prompt-profile", in: args))
    let modelUseCase = try parseModelUseCase(value(for: "--model-use-case", in: args))
    let reasoningPolicy = try parseReasoningPolicy(value(for: "--reasoning-policy", in: args))
    let warmState = try parseWarmState(value(for: "--warm-state", in: args))
    let parserCandidate = try parseParserCandidate(value(for: "--parser-candidate", in: args))
    let freeArgs = positionalFoods(from: args)

    var cases: [EvalCaseInput] = []

    if let corpusPath {
      let url = URL(fileURLWithPath: corpusPath)
      let text = try String(contentsOf: url, encoding: .utf8)
      for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
        let description = line.trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty, !description.hasPrefix("#") else { continue }
        cases.append(
          EvalCaseInput(
            id: "corpus-\(index + 1)",
            description: description,
            parsedOverride: nil
          )
        )
      }
    }

    if let parsedJSONPath {
      let url = URL(fileURLWithPath: parsedJSONPath)
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      // Accept either a single ParsedFoodRequest, an array, or wrapped { "cases": [...] }.
      if let wrapped = try? decoder.decode(ParsedJSONFile.self, from: data) {
        for (index, item) in wrapped.cases.enumerated() {
          cases.append(
            EvalCaseInput(
              id: item.id ?? "json-\(index + 1)",
              description: item.input ?? item.parsed.productName,
              parsedOverride: item.parsed
            )
          )
        }
      } else if let many = try? decoder.decode([ParsedFoodRequest].self, from: data) {
        for (index, parsed) in many.enumerated() {
          cases.append(
            EvalCaseInput(
              id: "json-\(index + 1)",
              description: parsed.productName,
              parsedOverride: parsed
            )
          )
        }
      } else {
        let parsed = try decoder.decode(ParsedFoodRequest.self, from: data)
        cases.append(
          EvalCaseInput(
            id: "json-1",
            description: parsed.productName,
            parsedOverride: parsed
          )
        )
      }
    }

    for (index, food) in freeArgs.enumerated() {
      cases.append(
        EvalCaseInput(
          id: "arg-\(index + 1)",
          description: food,
          parsedOverride: nil
        )
      )
    }

    if cases.isEmpty {
      fputs("error: provide food strings, --corpus <file>, or --parsed-json <file>\n", stderr)
      fputs(usage, stderr)
      exit(2)
    }

    let client = try USDAClient.fromEnvironment()
    let modelAvailable = MacFoundationModelsFoodParser.isAvailable(for: modelUseCase)
    let parseMode: ParseMode =
      forceFake
      ? .fake
      : (modelAvailable ? .foundationModels : .foundationModelsOrFake)
    fputs(
      "logging-eval: Foundation Models availability = \(MacFoundationModelsFoodParser.availabilityDescription(for: modelUseCase)); parseMode = \(parseMode.rawValue); parserCandidate = \(parserCandidate.rawValue); promptProfile = \(promptProfile.rawValue); modelUseCase = \(modelUseCase.rawValue); reasoningPolicy = \(reasoningPolicy.rawValue); warmState = \(warmState.rawValue)\n",
      stderr
    )
    if parseMode == .foundationModelsOrFake && !modelAvailable {
      fputs(
        "logging-eval: warning: Foundation Models unavailable; falling back to deterministicFake\n",
        stderr
      )
    }
    let runner = EvalRunner(
      provider: client,
      parseMode: parseMode,
      promptProfile: promptProfile,
      modelUseCase: modelUseCase,
      reasoningPolicy: reasoningPolicy,
      warmState: warmState,
      parserCandidate: parserCandidate,
      includeInput: includeInput
    )
    let report = await runner.run(cases: cases)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    if let json = String(data: data, encoding: .utf8) {
      print(json)
    }

    if report.failCount > 0 {
      exit(1)
    }
  }

  private static var usage: String {
    """
    logging-eval — Mac-side JustLogIt logging evaluation harness

    Usage:
      logging-eval "2 large eggs" "1 cup rice"
      logging-eval --corpus path/to/foods.txt
      logging-eval --parsed-json path/to/parsed.json

    Environment:
      USDA_API_KEY   Required. USDA FoodData Central API key (never commit this).

    Flags:
      --fake-parse     Force deterministic fake parse (skip Foundation Models)
      --include-input  Include raw food descriptions in local JSON output
                       (default: redacted; never commit opt-in reports)
      --prompt-profile production|leanCandidate
                       Select the parser instruction profile (default: production)
      --parser-candidate baseline|deterministic-first|hybrid
                       Select exactly one interpretation architecture (default: baseline)
      --model-use-case general|contentTagging
                       Select the Foundation Models use case (default: general)
      --reasoning-policy capabilityAwareLight|disabled
                       Compare shipping capability-aware light reasoning with no
                       requested reasoning level (default: capabilityAwareLight)
      --warm-state cold|prewarmed
                       Measure a fresh cold session or production-style prewarm
                       immediately before generation (default: cold)
      --corpus PATH    Read one food description per line
      --parsed-json P  Skip parsing; use provided ParsedFoodRequest JSON

    Notes:
      Default path uses Apple Foundation Models on this Mac when availability is
      .available, then grounds the result with ParsedFoodRequestGrounder, queries
      USDA, ranks, and resolves servings — the same trust boundary as the iOS app.

    """
  }

  private static func value(for flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else {
      return nil
    }
    return args[args.index(after: index)]
  }

  private static func positionalFoods(from args: [String]) -> [String] {
    var result: [String] = []
    var skipNext = false
    for arg in args {
      if skipNext {
        skipNext = false
        continue
      }
      if arg == "--corpus" || arg == "--parsed-json" || arg == "--prompt-profile"
        || arg == "--model-use-case" || arg == "--reasoning-policy" || arg == "--warm-state"
        || arg == "--parser-candidate"
      {
        skipNext = true
        continue
      }
      if arg == "--fake-parse" { continue }
      if arg.hasPrefix("-") { continue }
      result.append(arg)
    }
    return result
  }

  private static func parsePromptProfile(
    _ rawValue: String?
  ) throws -> MacFoundationModelsFoodParser.PromptProfile {
    guard let rawValue else { return .production }
    guard let value = MacFoundationModelsFoodParser.PromptProfile(rawValue: rawValue) else {
      throw CLIError.invalidOption("--prompt-profile", rawValue)
    }
    return value
  }

  private static func parseModelUseCase(
    _ rawValue: String?
  ) throws -> MacFoundationModelsFoodParser.ModelUseCase {
    guard let rawValue else { return .general }
    guard let value = MacFoundationModelsFoodParser.ModelUseCase(rawValue: rawValue) else {
      throw CLIError.invalidOption("--model-use-case", rawValue)
    }
    return value
  }

  private static func parseWarmState(
    _ rawValue: String?
  ) throws -> ParserEvaluationWarmState {
    guard let rawValue else { return .cold }
    guard let value = ParserEvaluationWarmState(rawValue: rawValue) else {
      throw CLIError.invalidOption("--warm-state", rawValue)
    }
    return value
  }

  private static func parseReasoningPolicy(
    _ rawValue: String?
  ) throws -> MacFoundationModelsFoodParser.ReasoningPolicy {
    guard let rawValue else { return .capabilityAwareLight }
    guard let value = MacFoundationModelsFoodParser.ReasoningPolicy(rawValue: rawValue) else {
      throw CLIError.invalidOption("--reasoning-policy", rawValue)
    }
    return value
  }

  private static func parseParserCandidate(_ rawValue: String?) throws -> ParserCandidate {
    guard let rawValue else { return .baseline }
    guard let value = ParserCandidate(rawValue: rawValue) else {
      throw CLIError.invalidOption("--parser-candidate", rawValue)
    }
    return value
  }
}

private enum CLIError: LocalizedError {
  case invalidOption(String, String)

  var errorDescription: String? {
    switch self {
    case .invalidOption(let option, let value):
      "Invalid value '\(value)' for \(option). Run with --help for accepted values."
    }
  }
}

private struct ParsedJSONFile: Decodable {
  struct Item: Decodable {
    var id: String?
    var input: String?
    var parsed: ParsedFoodRequest
  }

  var cases: [Item]
}
