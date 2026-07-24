import Foundation
import OSLog

/// Marker for the closed set of values permitted at the observability boundary.
/// `String`, identifiers, URLs, request/response values, and arbitrary model text
/// deliberately do not conform.
protocol PrivacySafeObservationValue: Sendable {}

/// Content-free local diagnostics. Every public-to-the-module entry point accepts
/// only closed enums, bounded counts, or durations; there is no arbitrary-text API.
enum AppObservability {
  enum Operation: PrivacySafeObservationValue {
    case bootstrapContainerOpen
    case healthReconciliation
    case parserAvailability
    case parserPrewarm
    case parserSessionAcquisition
    case parserResponse
    case parserMapping
    case deterministicExtraction
    case routeDecision
    case semanticGroundingAndMerge
    case hybridPipeline
    case hybridSessionAcquisition
    case hybridSemanticPrewarm
    case hybridSemanticResponse
    case usdaSearchPipeline
    case usdaSearchNetwork
    case usdaSearchDecode
    case usdaRanking
    case usdaDetailPipeline
    case usdaDetailNetwork
    case usdaDetailDecode

    fileprivate var label: String {
      switch self {
      case .bootstrapContainerOpen: "bootstrap_container_open"
      case .healthReconciliation: "health_reconciliation"
      case .parserAvailability: "parser_availability"
      case .parserPrewarm: "parser_prewarm"
      case .parserSessionAcquisition: "parser_session_acquisition"
      case .parserResponse: "parser_response"
      case .parserMapping: "parser_mapping"
      case .deterministicExtraction: "deterministic_extraction"
      case .routeDecision: "route_decision"
      case .semanticGroundingAndMerge: "semantic_grounding_and_merge"
      case .hybridPipeline: "hybrid_pipeline"
      case .hybridSessionAcquisition: "hybrid_session_acquisition"
      case .hybridSemanticPrewarm: "hybrid_semantic_prewarm"
      case .hybridSemanticResponse: "hybrid_semantic_response"
      case .usdaSearchPipeline: "usda_search_pipeline"
      case .usdaSearchNetwork: "usda_search_network"
      case .usdaSearchDecode: "usda_search_decode"
      case .usdaRanking: "usda_ranking"
      case .usdaDetailPipeline: "usda_detail_pipeline"
      case .usdaDetailNetwork: "usda_detail_network"
      case .usdaDetailDecode: "usda_detail_decode"
      }
    }
  }

  enum Outcome: PrivacySafeObservationValue, Equatable {
    case success
    case failure
    case cancelled

    fileprivate var label: String {
      switch self {
      case .success: "success"
      case .failure: "failure"
      case .cancelled: "cancelled"
      }
    }
  }

  enum BootstrapStoreCategory: PrivacySafeObservationValue {
    case persistent
    case testingMemory
    case forcedVolatile
    case fallbackVolatile
    case emergencyVolatile
    case failed

    fileprivate var label: String {
      switch self {
      case .persistent: "persistent"
      case .testingMemory: "testing_memory"
      case .forcedVolatile: "forced_volatile"
      case .fallbackVolatile: "fallback_volatile"
      case .emergencyVolatile: "emergency_volatile"
      case .failed: "failed"
      }
    }
  }

  /// One-shot launch milestones relative to BootstrapRootView creation.
  /// Durations are wall-clock from that origin; they are not Instruments frame timestamps.
  enum BootstrapMilestone: PrivacySafeObservationValue {
    case firstFrame
    case interactive

    fileprivate var label: String {
      switch self {
      case .firstFrame: "bootstrap_first_frame"
      case .interactive: "bootstrap_interactive"
      }
    }
  }

  enum ParserAvailability: PrivacySafeObservationValue {
    case available
    case deviceNotEligible
    case intelligenceDisabled
    case modelNotReady
    case otherUnavailable

    fileprivate var label: String {
      switch self {
      case .available: "available"
      case .deviceNotEligible: "device_not_eligible"
      case .intelligenceDisabled: "intelligence_disabled"
      case .modelNotReady: "model_not_ready"
      case .otherUnavailable: "other_unavailable"
      }
    }
  }

  enum ParserRoute: PrivacySafeObservationValue {
    case searchReady
    case clarification
    case composite
    case manualSearch
    case pccCandidate

    fileprivate var label: String {
      switch self {
      case .searchReady: "search_ready"
      case .clarification: "clarification"
      case .composite: "composite"
      case .manualSearch: "manual_search"
      case .pccCandidate: "pcc_candidate"
      }
    }
  }

  enum ParserArchitecture: PrivacySafeObservationValue {
    case baseline22Field
    case deterministicFastPath
    case fullHybrid

    fileprivate var label: String {
      switch self {
      case .baseline22Field: "baseline_22_field"
      case .deterministicFastPath: "deterministic_fast_path"
      case .fullHybrid: "full_hybrid"
      }
    }
  }

  enum DeterministicSelection: PrivacySafeObservationValue {
    case baselineFallback
    case identityOnly
    case countedItem
    case massMeasured
    case volumeMeasured
    case fractionOfWhole
    case fractionOfSizedContainer

    fileprivate var label: String {
      switch self {
      case .baselineFallback: "baseline_fallback"
      case .identityOnly: "identity_only"
      case .countedItem: "counted_item"
      case .massMeasured: "mass_measured"
      case .volumeMeasured: "volume_measured"
      case .fractionOfWhole: "fraction_of_whole"
      case .fractionOfSizedContainer: "fraction_of_sized_container"
      }
    }
  }

  enum SemanticOutcome: PrivacySafeObservationValue, Equatable {
    case accepted
    case unavailable
    case refused
    case invalid

    fileprivate var label: String {
      switch self {
      case .accepted: "accepted"
      case .unavailable: "unavailable"
      case .refused: "refused"
      case .invalid: "invalid"
      }
    }
  }

  enum SemanticInvocation: PrivacySafeObservationValue {
    case skipped
    case invoked

    fileprivate var label: String {
      switch self {
      case .skipped: "skipped"
      case .invoked: "invoked"
      }
    }
  }

  enum SemanticSessionSource: PrivacySafeObservationValue, Equatable {
    case prewarmed
    case fresh

    fileprivate var label: String {
      switch self {
      case .prewarmed: "prewarmed"
      case .fresh: "fresh"
      }
    }
  }

  enum CacheResource: PrivacySafeObservationValue, Equatable {
    case search
    case details

    fileprivate var label: String {
      switch self {
      case .search: "search"
      case .details: "details"
      }
    }
  }

  enum CacheOutcome: PrivacySafeObservationValue, Equatable {
    case hit
    case missing
    case expired
    /// Expired envelope returned after upstream failure (offline / transport error).
    case stale
    case corrupt
    case readIO
    case writeIO
    case pruneIO

    fileprivate var label: String {
      switch self {
      case .hit: "hit"
      case .missing: "missing"
      case .expired: "expired"
      case .stale: "stale"
      case .corrupt: "corrupt"
      case .readIO: "read_io"
      case .writeIO: "write_io"
      case .pruneIO: "prune_io"
      }
    }
  }

  enum USDATransportOutcome: PrivacySafeObservationValue, Equatable {
    case offline
    case timedOut
    case cancelled
    case other

    fileprivate var label: String {
      switch self {
      case .offline: "offline"
      case .timedOut: "timed_out"
      case .cancelled: "cancelled"
      case .other: "other"
      }
    }
  }

  /// The only injectable USDA diagnostics boundary. Associated values are themselves closed,
  /// privacy-safe enums, so callers cannot attach a query, URL, path, identifier, response body,
  /// or arbitrary error description.
  enum USDAEvent: PrivacySafeObservationValue, Equatable {
    case cache(resource: CacheResource, outcome: CacheOutcome)
    case transport(resource: CacheResource, outcome: USDATransportOutcome)
  }

  typealias USDAObserver = @Sendable (USDAEvent) -> Void

  enum USDAStatusCategory: PrivacySafeObservationValue {
    case success
    case invalidRequest
    case unauthorized
    case notFound
    case rateLimited
    case serverError
    case otherHTTP
    case nonHTTP

    fileprivate var label: String {
      switch self {
      case .success: "success"
      case .invalidRequest: "invalid_request"
      case .unauthorized: "unauthorized"
      case .notFound: "not_found"
      case .rateLimited: "rate_limited"
      case .serverError: "server_error"
      case .otherHTTP: "other_http"
      case .nonHTTP: "non_http"
      }
    }
  }

  enum CountCategory: PrivacySafeObservationValue {
    case parserInputTokens
    case parserCachedInputTokens
    case parserOutputTokens
    case parserReasoningTokens
    case decodedSearchResults
    case rankedSearchResults

    fileprivate var label: String {
      switch self {
      case .parserInputTokens: "parser_input_tokens"
      case .parserCachedInputTokens: "parser_cached_input_tokens"
      case .parserOutputTokens: "parser_output_tokens"
      case .parserReasoningTokens: "parser_reasoning_tokens"
      case .decodedSearchResults: "decoded_search_results"
      case .rankedSearchResults: "ranked_search_results"
      }
    }
  }

  enum InteractionMilestone: PrivacySafeObservationValue, Equatable {
    case usdaRequestDispatch
    case firstActionableUI

    fileprivate var label: String {
      switch self {
      case .usdaRequestDispatch: "usda_request_dispatch"
      case .firstActionableUI: "first_actionable_ui"
      }
    }
  }

  /// Clamps durations at the telemetry boundary. This prevents clock/test mistakes from creating
  /// negative or unbounded metrics while preserving `Duration` as the API used by implementation
  /// code. Ten minutes is intentionally above any useful interactive latency sample.
  struct BoundedDuration: PrivacySafeObservationValue, Equatable {
    static let maximum: Duration = .seconds(600)

    let value: Duration

    init(_ value: Duration) {
      self.value = min(max(value, .zero), Self.maximum)
    }
  }

  struct Count: PrivacySafeObservationValue, Equatable {
    let value: Int

    init(_ value: Int) {
      self.value = max(0, value)
    }
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "JustLogIt",
    category: "LocalObservability"
  )
  private static let signposter = OSSignposter(logger: logger)

  static func measure<Value>(
    _ operation: Operation,
    body: () throws -> Value
  ) rethrows -> Value {
    let started = ContinuousClock.now
    let state = begin(operation)
    do {
      let value = try body()
      finish(operation, state: state, started: started, outcome: .success)
      return value
    } catch {
      finish(operation, state: state, started: started, outcome: outcome(for: error))
      throw error
    }
  }

  static func measure<Value>(
    _ operation: Operation,
    isolation: isolated (any Actor)? = #isolation,
    body: () async throws -> Value
  ) async rethrows -> Value {
    let started = ContinuousClock.now
    let state = begin(operation)
    do {
      let value = try await body()
      finish(operation, state: state, started: started, outcome: .success)
      return value
    } catch {
      finish(operation, state: state, started: started, outcome: outcome(for: error))
      throw error
    }
  }

  static func recordBootstrap(_ category: BootstrapStoreCategory, duration: Duration) {
    logger.info(
      "bootstrap store_category=\(category.label, privacy: .public) duration_ms=\(milliseconds(duration), privacy: .public)"
    )
  }

  static func recordBootstrapMilestone(
    _ milestone: BootstrapMilestone,
    duration: Duration
  ) {
    logger.info(
      "bootstrap milestone=\(milestone.label, privacy: .public) duration_ms=\(milliseconds(BoundedDuration(duration).value), privacy: .public)"
    )
  }

  static func recordParserAvailability(_ availability: ParserAvailability) {
    logger.info("parser availability=\(availability.label, privacy: .public)")
  }

  static func recordParserRoute(_ route: ParserRoute) {
    logger.info("parser route=\(route.label, privacy: .public)")
  }

  static func recordParserArchitecture(_ architecture: ParserArchitecture) {
    logger.info("parser architecture=\(architecture.label, privacy: .public)")
  }

  static func recordDeterministicSelection(_ selection: DeterministicSelection) {
    logger.info("parser deterministic_selection=\(selection.label, privacy: .public)")
  }

  static func recordSemanticInvocation(_ invocation: SemanticInvocation) {
    logger.info("parser semantic_invocation=\(invocation.label, privacy: .public)")
  }

  static func recordSemanticOutcome(_ outcome: SemanticOutcome) {
    logger.info("parser semantic_outcome=\(outcome.label, privacy: .public)")
  }

  static func recordSemanticSessionSource(_ source: SemanticSessionSource) {
    logger.debug("parser semantic_session_source=\(source.label, privacy: .public)")
  }

  static func recordCache(resource: CacheResource, outcome: CacheOutcome) {
    logger.debug(
      "usda cache_resource=\(resource.label, privacy: .public) cache_outcome=\(outcome.label, privacy: .public)"
    )
  }

  static func recordUSDAEvent(_ event: USDAEvent) {
    switch event {
    case .cache(let resource, let outcome):
      recordCache(resource: resource, outcome: outcome)
    case .transport(let resource, let outcome):
      logger.debug(
        "usda transport_resource=\(resource.label, privacy: .public) transport_outcome=\(outcome.label, privacy: .public)"
      )
    }
  }

  static func usdaTransportOutcome(for error: any Error) -> USDATransportOutcome {
    if error is CancellationError { return .cancelled }
    guard let urlError = error as? URLError else { return .other }
    switch urlError.code {
    case .cancelled: return .cancelled
    case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost,
      .cannotConnectToHost:
      return .offline
    case .timedOut: return .timedOut
    default: return .other
    }
  }

  static func recordUSDAStatus(_ status: USDAStatusCategory) {
    logger.debug("usda status_category=\(status.label, privacy: .public)")
  }

  static func recordCount(_ category: CountCategory, _ count: Count) {
    logger.debug(
      "metric count_category=\(category.label, privacy: .public) count=\(count.value, privacy: .public)"
    )
  }

  static func recordDuration(_ operation: Operation, _ duration: BoundedDuration) {
    logger.debug(
      "operation=\(operation.label, privacy: .public) outcome=\(Outcome.success.label, privacy: .public) duration_ms=\(milliseconds(duration.value), privacy: .public)"
    )
  }

  static func recordMilestone(
    _ milestone: InteractionMilestone,
    duration: BoundedDuration
  ) {
    logger.debug(
      "interaction milestone=\(milestone.label, privacy: .public) duration_ms=\(milliseconds(duration.value), privacy: .public)"
    )
  }

  private static func begin(_ operation: Operation) -> OSSignpostIntervalState {
    switch operation {
    case .bootstrapContainerOpen: signposter.beginInterval("bootstrap_container_open")
    case .healthReconciliation: signposter.beginInterval("health_reconciliation")
    case .parserAvailability: signposter.beginInterval("parser_availability")
    case .parserPrewarm: signposter.beginInterval("parser_prewarm")
    case .parserSessionAcquisition: signposter.beginInterval("parser_session_acquisition")
    case .parserResponse: signposter.beginInterval("parser_response")
    case .parserMapping: signposter.beginInterval("parser_mapping")
    case .deterministicExtraction: signposter.beginInterval("deterministic_extraction")
    case .routeDecision: signposter.beginInterval("route_decision")
    case .semanticGroundingAndMerge:
      signposter.beginInterval("semantic_grounding_and_merge")
    case .hybridPipeline: signposter.beginInterval("hybrid_pipeline")
    case .hybridSessionAcquisition: signposter.beginInterval("hybrid_session_acquisition")
    case .hybridSemanticPrewarm: signposter.beginInterval("hybrid_semantic_prewarm")
    case .hybridSemanticResponse: signposter.beginInterval("hybrid_semantic_response")
    case .usdaSearchPipeline: signposter.beginInterval("usda_search_pipeline")
    case .usdaSearchNetwork: signposter.beginInterval("usda_search_network")
    case .usdaSearchDecode: signposter.beginInterval("usda_search_decode")
    case .usdaRanking: signposter.beginInterval("usda_ranking")
    case .usdaDetailPipeline: signposter.beginInterval("usda_detail_pipeline")
    case .usdaDetailNetwork: signposter.beginInterval("usda_detail_network")
    case .usdaDetailDecode: signposter.beginInterval("usda_detail_decode")
    }
  }

  private static func finish(
    _ operation: Operation,
    state: OSSignpostIntervalState,
    started: ContinuousClock.Instant,
    outcome: Outcome
  ) {
    end(operation, state: state)
    logger.debug(
      "operation=\(operation.label, privacy: .public) outcome=\(outcome.label, privacy: .public) duration_ms=\(milliseconds(started.duration(to: .now)), privacy: .public)"
    )
  }

  private static func end(_ operation: Operation, state: OSSignpostIntervalState) {
    switch operation {
    case .bootstrapContainerOpen: signposter.endInterval("bootstrap_container_open", state)
    case .healthReconciliation: signposter.endInterval("health_reconciliation", state)
    case .parserAvailability: signposter.endInterval("parser_availability", state)
    case .parserPrewarm: signposter.endInterval("parser_prewarm", state)
    case .parserSessionAcquisition: signposter.endInterval("parser_session_acquisition", state)
    case .parserResponse: signposter.endInterval("parser_response", state)
    case .parserMapping: signposter.endInterval("parser_mapping", state)
    case .deterministicExtraction: signposter.endInterval("deterministic_extraction", state)
    case .routeDecision: signposter.endInterval("route_decision", state)
    case .semanticGroundingAndMerge:
      signposter.endInterval("semantic_grounding_and_merge", state)
    case .hybridPipeline: signposter.endInterval("hybrid_pipeline", state)
    case .hybridSessionAcquisition: signposter.endInterval("hybrid_session_acquisition", state)
    case .hybridSemanticPrewarm: signposter.endInterval("hybrid_semantic_prewarm", state)
    case .hybridSemanticResponse: signposter.endInterval("hybrid_semantic_response", state)
    case .usdaSearchPipeline: signposter.endInterval("usda_search_pipeline", state)
    case .usdaSearchNetwork: signposter.endInterval("usda_search_network", state)
    case .usdaSearchDecode: signposter.endInterval("usda_search_decode", state)
    case .usdaRanking: signposter.endInterval("usda_ranking", state)
    case .usdaDetailPipeline: signposter.endInterval("usda_detail_pipeline", state)
    case .usdaDetailNetwork: signposter.endInterval("usda_detail_network", state)
    case .usdaDetailDecode: signposter.endInterval("usda_detail_decode", state)
    }
  }

  static func outcome(for error: any Error) -> Outcome {
    if error is CancellationError { return .cancelled }
    if (error as? URLError)?.code == .cancelled { return .cancelled }
    return .failure
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

/// One-shot launch milestones from BootstrapRootView creation to first interactive chrome.
/// Carries no user content; durations clamp at the observability boundary.
struct BootstrapLaunchTimeline: Sendable, Equatable {
  struct Measurement: Sendable, Equatable {
    let milestone: AppObservability.BootstrapMilestone
    let duration: AppObservability.BoundedDuration
  }

  private let startedAt: ContinuousClock.Instant
  private var didFirstFrame = false
  private var didInteractive = false

  init(startedAt: ContinuousClock.Instant = .now) {
    self.startedAt = startedAt
  }

  mutating func markFirstFrame(
    at instant: ContinuousClock.Instant = .now
  ) -> Measurement? {
    guard !didFirstFrame else { return nil }
    didFirstFrame = true
    return measurement(.firstFrame, at: instant)
  }

  mutating func markInteractive(
    at instant: ContinuousClock.Instant = .now
  ) -> Measurement? {
    guard !didInteractive else { return nil }
    didInteractive = true
    return measurement(.interactive, at: instant)
  }

  private func measurement(
    _ milestone: AppObservability.BootstrapMilestone,
    at instant: ContinuousClock.Instant
  ) -> Measurement {
    Measurement(
      milestone: milestone,
      duration: .init(startedAt.duration(to: instant))
    )
  }
}

/// One-shot timing state for a user-initiated logging interaction. It carries no food text,
/// query, identifiers, or model output and is deterministic under an injected clock instant.
struct FoodLogInteractionTimeline: Sendable, Equatable {
  struct Measurement: Sendable, Equatable {
    let milestone: AppObservability.InteractionMilestone
    let duration: AppObservability.BoundedDuration
  }

  private let startedAt: ContinuousClock.Instant
  private var didDispatchUSDA = false
  private var didPresentActionableUI = false

  init(startedAt: ContinuousClock.Instant = .now) {
    self.startedAt = startedAt
  }

  mutating func markUSDARequestDispatch(
    at instant: ContinuousClock.Instant = .now
  ) -> Measurement? {
    guard !didDispatchUSDA else { return nil }
    didDispatchUSDA = true
    return measurement(.usdaRequestDispatch, at: instant)
  }

  mutating func markFirstActionableUI(
    at instant: ContinuousClock.Instant = .now
  ) -> Measurement? {
    guard !didPresentActionableUI else { return nil }
    didPresentActionableUI = true
    return measurement(.firstActionableUI, at: instant)
  }

  private func measurement(
    _ milestone: AppObservability.InteractionMilestone,
    at instant: ContinuousClock.Instant
  ) -> Measurement {
    Measurement(
      milestone: milestone,
      duration: .init(startedAt.duration(to: instant))
    )
  }
}
