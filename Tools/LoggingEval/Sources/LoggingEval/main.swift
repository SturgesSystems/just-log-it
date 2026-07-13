import Foundation
import JustLogItCore

@available(macOS 26.4, *)
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
    let parseMode: ParseMode =
      forceFake
      ? .fake
      : (MacFoundationModelsFoodParser.isAvailable ? .foundationModels : .foundationModelsOrFake)
    fputs(
      "logging-eval: Foundation Models availability = \(MacFoundationModelsFoodParser.availabilityDescription); parseMode = \(parseMode.rawValue)\n",
      stderr
    )
    if parseMode == .foundationModelsOrFake && !MacFoundationModelsFoodParser.isAvailable {
      fputs(
        "logging-eval: warning: Foundation Models unavailable; falling back to deterministicFake\n",
        stderr
      )
    }
    let runner = EvalRunner(provider: client, parseMode: parseMode)
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
      if arg == "--corpus" || arg == "--parsed-json" {
        skipNext = true
        continue
      }
      if arg == "--fake-parse" { continue }
      if arg.hasPrefix("-") { continue }
      result.append(arg)
    }
    return result
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
