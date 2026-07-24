#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "tempfile"
require "time"

def fail!(message)
  warn "error: #{message}"
  exit 2
end

def require_hash!(value, label)
  fail!("#{label} must be an object") unless value.is_a?(Hash)
  value
end

def require_array!(value, label)
  fail!("#{label} must be an array") unless value.is_a?(Array)
  value
end

def require_string!(value, label)
  fail!("#{label} must be a nonempty string") unless value.is_a?(String) && !value.empty?
  value
end

def require_boolean!(value, label)
  fail!("#{label} must be boolean") unless value == true || value == false
  value
end

def require_nullable_boolean!(value, label)
  return value if value.nil?

  require_boolean!(value, label)
end

def require_integer!(value, label, range: nil)
  fail!("#{label} must be an integer") unless value.is_a?(Integer)
  fail!("#{label} is outside its supported range") if range && !range.cover?(value)
  value
end

def require_nonnegative_number!(value, label)
  valid = value.is_a?(Numeric) && value.finite? && value >= 0
  fail!("#{label} must be a finite nonnegative number") unless valid
  value
end

def require_nullable_nonnegative_integer!(value, label)
  return value if value.nil?

  require_integer!(value, label)
  fail!("#{label} must be nonnegative") if value.negative?
  value
end

def require_member!(value, allowed, label)
  fail!("#{label} is unsupported") unless allowed.include?(value)
  value
end

def parse_json!(contents, label)
  JSON.parse(contents)
rescue JSON::ParserError
  fail!("#{label} is not valid JSON")
end

def rate(values)
  return nil if values.empty?

  values.count(true).to_f / values.length
end

def average(values)
  return nil if values.empty?

  values.sum.to_f / values.length
end

def percentile(values, fraction)
  return nil if values.empty?

  sorted = values.sort
  sorted[[((sorted.length * fraction).ceil - 1), 0].max]
end

def comparison_snapshot(item)
  {
    "outcome" => item.fetch("outcome"),
    "sourceGrounded" => item["sourceGrounded"],
    "requiredFieldsCorrect" => item["requiredFieldsCorrect"],
    "unsupportedInventedFacts" => item.fetch("unsupportedInventedFacts"),
    "behaviorCorrect" => item["behaviorCorrect"],
    "usdaTerminal" => item.fetch("usdaRouting"),
    "routeCorrect" => item["routeCorrect"],
    "interpretationRoute" => item["interpretationRoute"]
  }
end

def classify_candidate_comparison(production, candidate)
  production_snapshot = comparison_snapshot(production)
  candidate_snapshot = comparison_snapshot(candidate)
  comparable_fields = %w[
    outcome sourceGrounded requiredFieldsCorrect unsupportedInventedFacts behaviorCorrect
    usdaTerminal
  ]
  changed_dimensions = comparable_fields.select do |field|
    production_snapshot[field] != candidate_snapshot[field]
  end
  changed_dimensions << "candidateRoute" if candidate_snapshot["routeCorrect"] == false
  changed_dimensions.uniq!
  return nil if changed_dimensions.empty?

  unsafe_reasons = []
  if production_snapshot["sourceGrounded"] == true && candidate_snapshot["sourceGrounded"] != true
    unsafe_reasons << "candidate_lost_source_grounding"
  elsif candidate_snapshot["sourceGrounded"] == false
    unsafe_reasons << "candidate_not_source_grounded"
  end
  if candidate_snapshot["unsupportedInventedFacts"]
    unsafe_reasons << "candidate_unsupported_invented_fact"
  end
  unsafe_reasons << "candidate_wrong_route" if candidate_snapshot["routeCorrect"] == false
  if production_snapshot["behaviorCorrect"] == true && candidate_snapshot["behaviorCorrect"] != true
    unsafe_reasons << "candidate_behavior_regression"
  elsif candidate_snapshot["behaviorCorrect"] == false
    unsafe_reasons << "candidate_behavior_incorrect"
  end
  if production_snapshot["usdaTerminal"] != candidate_snapshot["usdaTerminal"] &&
     production_snapshot["behaviorCorrect"] != false && candidate_snapshot["behaviorCorrect"] == false
    unsafe_reasons << "candidate_unsafe_usda_terminal"
  end

  candidate_improvements = []
  production_improvements = []
  %w[sourceGrounded requiredFieldsCorrect behaviorCorrect].each do |field|
    production_value = production_snapshot[field]
    candidate_value = candidate_snapshot[field]
    candidate_improvements << field if production_value == false && candidate_value == true
    production_improvements << field if production_value == true && candidate_value == false
  end
  if production_snapshot["unsupportedInventedFacts"] && !candidate_snapshot["unsupportedInventedFacts"]
    candidate_improvements << "unsupportedInventedFacts"
  end
  if !production_snapshot["unsupportedInventedFacts"] && candidate_snapshot["unsupportedInventedFacts"]
    production_improvements << "unsupportedInventedFacts"
  end
  if unsafe_reasons.empty? && !candidate_improvements.empty? && !production_improvements.empty?
    unsafe_reasons << "mixed_correctness_tradeoff"
  end

  classification =
    if !unsafe_reasons.empty?
      "unsafe"
    elsif !candidate_improvements.empty?
      "candidate_improvement"
    elsif !production_improvements.empty?
      "production_improvement"
    else
      "both_acceptable"
    end
  {
    "classification" => classification,
    "changedDimensions" => changed_dimensions,
    "candidateImprovementDimensions" => candidate_improvements,
    "productionImprovementDimensions" => production_improvements,
    "unsafeReasons" => unsafe_reasons,
    "production" => production_snapshot,
    "candidate" => candidate_snapshot,
    "contentEquivalenceEvaluated" => false,
    "privateHumanReviewRequired" => true
  }
end

def atomic_write(path, contents)
  directory = File.dirname(path)
  Dir.mkdir(directory, 0o700) unless Dir.exist?(directory)
  Tempfile.create(["promotion-report", ".tmp"], directory, mode: File::RDWR, perm: 0o600) do |file|
    file.write(contents)
    file.flush
    file.fsync
    File.rename(file.path, path)
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: parser-eval-promotion-report.rb --manifest PATH --output PATH"
  parser.on("--manifest PATH") { |value| options[:manifest] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!

manifest_path = options[:manifest] || fail!("--manifest is required")
output_path = options[:output] || fail!("--output is required")
manifest_contents = File.binread(manifest_path)
manifest = require_hash!(parse_json!(manifest_contents, "manifest"), "manifest")
fail!("unsupported manifest schema") unless manifest.fetch("schemaVersion") == 1
configuration_probe_only = require_boolean!(
  manifest.fetch("configurationProbeOnly", false), "manifest configurationProbeOnly"
)
includes_input = require_boolean!(manifest.fetch("includesInputText"), "manifest includesInputText")
fail!("configuration probes do not produce promotion reports") if configuration_probe_only
fail!("promotion reports require redacted source reports") if includes_input

case_order = require_array!(manifest.fetch("resolvedCaseOrder"), "manifest resolvedCaseOrder")
case_order.each_with_index do |case_id, index|
  require_string!(case_id, "manifest resolvedCaseOrder[#{index}]")
  fail!("manifest resolvedCaseOrder[#{index}] is malformed") unless case_id.match?(/\A[A-Za-z0-9._-]+\z/)
end
fail!("manifest has no resolved cases") if case_order.empty?
fail!("manifest contains duplicate case IDs") unless case_order.uniq.length == case_order.length
repeats = require_integer!(manifest.fetch("repeats"), "manifest repeats", range: 2..5)
corpus_version = require_string!(manifest.fetch("corpusVersion"), "manifest corpusVersion")
fail!("manifest corpusVersion is malformed") unless corpus_version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/)
blocks = require_array!(manifest.fetch("blocks"), "manifest blocks")
fail!("manifest has no evaluation blocks") if blocks.empty?
blocks.each_with_index { |block, index| require_hash!(block, "manifest block #{index}") }
block_ids = blocks.map do |block|
  block_id = require_string!(block.fetch("id"), "block id")
  fail!("block id is malformed") unless block_id.match?(/\A[A-Za-z0-9._-]+\z/)
  block_id
end
fail!("manifest contains duplicate block IDs") unless block_ids.uniq.length == block_ids.length
incomplete = blocks.reject { |block| block.fetch("status") == "complete" }
fail!("incomplete blocks: #{incomplete.map { |block| block.fetch("id") }.join(",")}") unless incomplete.empty?

observations = []
source_reports = []
block_dimensions = []
blocks.each do |block|
  block_id = block.fetch("id")
  candidate = require_member!(
    require_string!(block.fetch("candidate"), "block #{block_id} candidate"),
    %w[baseline22Field deterministicFirst hybrid],
    "block #{block_id} candidate"
  )
  warm_state = require_member!(
    require_string!(block.fetch("warmState"), "block #{block_id} warmState"),
    %w[cold prewarmed],
    "block #{block_id} warmState"
  )
  model_use_case = require_member!(
    require_string!(block.fetch("modelUseCase"), "block #{block_id} modelUseCase"),
    %w[general contentTagging],
    "block #{block_id} modelUseCase"
  )
  reasoning_policy = require_member!(
    require_string!(block.fetch("reasoningPolicy"), "block #{block_id} reasoningPolicy"),
    %w[capabilityAwareLight disabled],
    "block #{block_id} reasoningPolicy"
  )
  block_dimensions << [candidate, warm_state, model_use_case, reasoning_policy]
  report_path = block.dig("artifacts", "report") || fail!("block #{block_id} has no report")
  checksum = block.dig("checksums", "reportSHA256") || fail!("block #{block_id} has no report checksum")
  require_string!(report_path, "block #{block_id} report path")
  fail!("block #{block_id} report checksum is malformed") unless checksum.is_a?(String) && checksum.match?(/\A[0-9a-f]{64}\z/)
  fail!("block #{block_id} report is missing") unless File.file?(report_path)
  report_contents = File.binread(report_path)
  actual_checksum = Digest::SHA256.hexdigest(report_contents)
  fail!("block #{block_id} report checksum mismatch") unless actual_checksum == checksum
  report = require_hash!(parse_json!(report_contents, "block #{block_id} report"), "block #{block_id} report")
  fail!("block #{block_id} corpus mismatch") unless report.fetch("corpusVersion") == corpus_version
  fail!("block #{block_id} repeat mismatch") unless report.fetch("repeats") == repeats
  report_includes_input = require_boolean!(
    report.fetch("includesInputText"), "block #{block_id} includesInputText"
  )
  fail!("block #{block_id} contains raw input") if report_includes_input
  fail!("block #{block_id} warm-state mismatch") unless report.fetch("warmStates") == [block.fetch("warmState")]
  fail!("block #{block_id} reasoning-policy mismatch") unless
    report.fetch("reasoningPolicies") == [reasoning_policy]
  block_observations = require_array!(report.fetch("observations"), "block #{block_id} observations")
  fail!("block #{block_id} has no observations") if block_observations.empty?
  expected_profiles =
    case candidate
    when "baseline22Field" then %w[production leanCandidate]
    when "deterministicFirst" then %w[production]
    when "hybrid" then %w[minimal]
    end
  block_observations.each_with_index do |item, index|
    label = "block #{block_id} observation #{index}"
    require_hash!(item, label)
    fail!("#{label} corpus mismatch") unless item.fetch("corpusVersion") == corpus_version
    fail!("#{label} candidate mismatch") unless item.fetch("candidate") == candidate
    fail!("#{label} use-case mismatch") unless item.fetch("modelUseCase") == model_use_case
    fail!("#{label} reasoning-policy mismatch") unless
      item.fetch("reasoningPolicy") == reasoning_policy
    fail!("#{label} warm-state mismatch") unless item.fetch("warmState") == warm_state
    require_member!(item.fetch("promptProfile"), expected_profiles, "#{label} promptProfile")
    require_member!(item.fetch("caseID"), case_order, "#{label} caseID")
    require_integer!(item.fetch("run"), "#{label} run", range: 1..repeats)
    require_member!(item.fetch("outcome"), %w[parsed error], "#{label} outcome")
    require_member!(
      item.fetch("usdaRouting"),
      %w[directSearch compositeHandoff blocked blockedByParserError],
      "#{label} usdaRouting"
    )
    require_member!(
      item.fetch("expectedRoute"),
      %w[deterministicSearch onDeviceSemantic clarification composite manualSearch pccCandidate],
      "#{label} expectedRoute"
    )
    unless item["interpretationRoute"].nil?
      require_member!(
        item["interpretationRoute"],
        %w[deterministicSearch onDeviceSemantic clarification composite manualSearch pccCandidate],
        "#{label} interpretationRoute"
      )
    end
    require_nonnegative_number!(item.fetch("latencyMilliseconds"), "#{label} latencyMilliseconds")
    %w[sourceGrounded requiredFieldsCorrect behaviorCorrect routeCorrect stableWithFirstRun
       deterministicFastPathUsed modelInvoked].each do |field|
      require_nullable_boolean!(item[field], "#{label} #{field}")
    end
    require_boolean!(item.fetch("unsupportedInventedFacts"), "#{label} unsupportedInventedFacts")
    require_boolean!(item.fetch("humanReviewRequired"), "#{label} humanReviewRequired")
    %w[inputTokenCount outputTokenCount reasoningTokenCount].each do |field|
      require_nullable_nonnegative_integer!(item[field], "#{label} #{field}")
    end
    fail!("#{label} leaked raw input") unless item["input"].nil?
    if item.fetch("outcome") == "parsed"
      %w[sourceGrounded requiredFieldsCorrect behaviorCorrect].each do |field|
        fail!("#{label} parsed outcome is missing #{field}") if item[field].nil?
      end
    end
    if candidate != "baseline22Field"
      fail!("#{label} typed candidate is missing routeCorrect") if item["routeCorrect"].nil?
      fail!("#{label} typed candidate is missing modelInvoked") if item["modelInvoked"].nil?
      fail!("#{label} typed candidate is missing interpretationRoute") if
        item["interpretationRoute"].nil?
      fail!("#{label} route correctness is inconsistent") unless
        item["routeCorrect"] == (item["interpretationRoute"] == item.fetch("expectedRoute"))
    end
  end
  expected_keys = expected_profiles.product(case_order, (1..repeats).to_a).map do |profile, case_id, run|
    [profile, case_id, run]
  end
  actual_keys = block_observations.map do |item|
    [item.fetch("promptProfile"), item.fetch("caseID"), item.fetch("run")]
  end
  fail!("block #{block_id} observation coverage mismatch") unless actual_keys.sort == expected_keys.sort
  expected_profiles.each do |profile|
    actual_case_order = block_observations
      .select { |item| item.fetch("promptProfile") == profile }
      .map { |item| item.fetch("caseID") }.uniq
    fail!("block #{block_id} case order mismatch for #{profile}") unless actual_case_order == case_order
  end
  observations.concat(block_observations)
  source_reports << { "blockID" => block_id, "reportSHA256" => checksum }
end
fail!("manifest contains duplicate evaluation blocks") unless block_dimensions.uniq.length == block_dimensions.length

observation_keys = observations.map do |item|
  [item.fetch("candidate"), item.fetch("modelUseCase"), item.fetch("promptProfile"),
   item.fetch("reasoningPolicy"), item.fetch("warmState"), item.fetch("caseID"),
   item.fetch("run")].join("|")
end
fail!("duplicate observations across blocks") unless observation_keys.uniq.length == observation_keys.length

configuration_groups = observations.group_by do |item|
  [item.fetch("candidate"), item.fetch("modelUseCase"), item.fetch("promptProfile"),
   item.fetch("reasoningPolicy"), item.fetch("warmState")]
end
configurations = configuration_groups.sort.map do |key, items|
  latencies = items.map { |item| item.fetch("latencyMilliseconds").to_f }
  outcomes = items.group_by { |item| item.fetch("outcome") }.transform_values(&:length).sort.to_h
  configuration = {
    "candidate" => key[0],
    "modelUseCase" => key[1],
    "promptProfile" => key[2],
    "reasoningPolicy" => key[3],
    "warmState" => key[4],
    "observationCount" => items.length,
    "sourceGroundingRate" => rate(items.map { |item| item["sourceGrounded"] }.compact),
    "requiredFieldRate" => rate(items.map { |item| item["requiredFieldsCorrect"] }.compact),
    "behaviorRate" => rate(items.map { |item| item["behaviorCorrect"] }.compact),
    "routeAccuracy" => rate(items.map { |item| item["routeCorrect"] }.compact),
    "stabilityRate" => rate(items.map { |item| item["stableWithFirstRun"] }.compact),
    "unsupportedInventedFactCount" => items.count { |item| item.fetch("unsupportedInventedFacts") },
    "humanReviewRequiredCount" => items.count { |item| item.fetch("humanReviewRequired") },
    "p50LatencyMilliseconds" => percentile(latencies, 0.50),
    "p95LatencyMilliseconds" => percentile(latencies, 0.95),
    "maximumLatencyMilliseconds" => latencies.max,
    "averageInputTokenCount" => average(items.map { |item| item["inputTokenCount"] }.compact),
    "averageOutputTokenCount" => average(items.map { |item| item["outputTokenCount"] }.compact),
    "averageReasoningTokenCount" => average(items.map { |item| item["reasoningTokenCount"] }.compact),
    "deterministicFastPathRate" => rate(items.map { |item| item["deterministicFastPathUsed"] }.compact),
    "modelInvocationRate" => rate(items.map { |item| item["modelInvoked"] }.compact),
    "outcomeCounts" => outcomes
  }
  gate_failures = []
  gate_failures << "source_grounding" unless configuration["sourceGroundingRate"] == 1.0
  gate_failures << "unsupported_invented_facts" unless
    configuration["unsupportedInventedFactCount"].zero?
  required_field_rate = configuration["requiredFieldRate"]
  gate_failures << "required_fields" unless required_field_rate && required_field_rate >= 0.90
  behavior_rate = configuration["behaviorRate"]
  gate_failures << "behavior" unless behavior_rate && behavior_rate >= 0.85
  stability_rate = configuration["stabilityRate"]
  gate_failures << "stability" unless stability_rate && stability_rate >= 0.90
  gate_failures << "p95_latency" unless configuration["p95LatencyMilliseconds"] <= 15_000
  if key[0] != "baseline22Field"
    gate_failures << "typed_route_accuracy" unless configuration["routeAccuracy"] == 1.0
  end
  configuration["absoluteGatePassed"] = gate_failures.empty?
  configuration["absoluteGateFailures"] = gate_failures
  configuration
end

comparison_groups = observations.group_by do |item|
  [item.fetch("modelUseCase"), item.fetch("reasoningPolicy"), item.fetch("warmState"),
   item.fetch("caseID"), item.fetch("run")]
end
comparison_groups.each do |key, items|
  fail!("comparison group #{key.join("|")} has inconsistent expected routes") unless
    items.map { |item| item.fetch("expectedRoute") }.uniq.length == 1
  fail!("comparison group #{key.join("|")} has inconsistent human-review policy") unless
    items.map { |item| item.fetch("humanReviewRequired") }.uniq.length == 1
end
comparison_candidate_names = block_dimensions.map(&:first).uniq & %w[deterministicFirst hybrid]
case_comparisons = comparison_groups.sort.map do |key, items|
  production = items.find do |item|
    item.fetch("candidate") == "baseline22Field" && item.fetch("promptProfile") == "production"
  end
  candidate_results = comparison_candidate_names.map do |candidate_name|
    candidate = items.find { |item| item.fetch("candidate") == candidate_name }
    classification = production && candidate ? classify_candidate_comparison(production, candidate) : nil
    {
      "candidate" => candidate_name,
      "productionPresent" => !production.nil?,
      "candidatePresent" => !candidate.nil?,
      "meaningfulDisagreement" => !classification.nil?,
      "comparison" => classification
    }
  end
  hybrid_result = candidate_results.find { |item| item.fetch("candidate") == "hybrid" }
  hybrid_unsafe_reasons = hybrid_result&.dig("comparison", "unsafeReasons") || []
  {
    "modelUseCase" => key[0],
    "reasoningPolicy" => key[1],
    "warmState" => key[2],
    "caseID" => key[3],
    "run" => key[4],
    "baselinePresent" => !production.nil?,
    "deterministicFirstPresent" => items.any? { |item| item.fetch("candidate") == "deterministicFirst" },
    "hybridPresent" => !hybrid_result.nil? && hybrid_result.fetch("candidatePresent"),
    "candidateComparisons" => candidate_results,
    "unsafeHybridDisagreement" => hybrid_result&.dig("comparison", "classification") == "unsafe",
    "unsafeReasons" => hybrid_unsafe_reasons
  }
end
candidate_comparisons = case_comparisons.flat_map do |item|
  item.fetch("candidateComparisons").map do |candidate_result|
    {
      "modelUseCase" => item.fetch("modelUseCase"),
      "reasoningPolicy" => item.fetch("reasoningPolicy"),
      "warmState" => item.fetch("warmState"),
      "caseID" => item.fetch("caseID"),
      "run" => item.fetch("run")
    }.merge(candidate_result)
  end
end
missing_comparisons = candidate_comparisons.reject do |item|
  item.fetch("productionPresent") && item.fetch("candidatePresent")
end

meaningful_comparisons = candidate_comparisons.select { |item| item.fetch("meaningfulDisagreement") }
unsafe_comparisons = meaningful_comparisons.select do |item|
  item.dig("comparison", "classification") == "unsafe"
end
unsafe_hybrid_comparisons = unsafe_comparisons.select { |item| item.fetch("candidate") == "hybrid" }
filters = require_hash!(manifest.fetch("filters"), "manifest filters")
filter_case_ids = require_array!(filters.fetch("caseIDs"), "manifest filters caseIDs")
filter_families = require_array!(filters.fetch("families"), "manifest filters families")
filter_case_ids.each do |case_id|
  fail!("manifest filter caseID is malformed") unless case_id.is_a?(String) && case_id.match?(/\A[A-Za-z0-9._-]+\z/)
end
filter_families.each do |family|
  fail!("manifest filter family is malformed") unless family.is_a?(String) && family.match?(/\A[A-Za-z0-9]+\z/)
end
sanitized_filters = { "caseIDs" => filter_case_ids, "families" => filter_families }
required_promotion_dimensions = %w[baseline22Field deterministicFirst hybrid].product(
  %w[cold prewarmed], ["general"], ["capabilityAwareLight"]
)
promotion_scope_complete =
  (required_promotion_dimensions - block_dimensions).empty? &&
  filter_case_ids.empty? && filter_families.empty?
required_configuration_keys = required_promotion_dimensions.map do |candidate, warm_state, model_use_case, reasoning_policy|
  profile = candidate == "hybrid" ? "minimal" : "production"
  [candidate, model_use_case, profile, reasoning_policy, warm_state]
end
required_configurations = required_configuration_keys.map do |required_key|
  configurations.find do |configuration|
    [configuration.fetch("candidate"), configuration.fetch("modelUseCase"),
     configuration.fetch("promptProfile"), configuration.fetch("reasoningPolicy"),
     configuration.fetch("warmState")] == required_key
  end
end
required_automated_gates_pass = required_configurations.all? do |configuration|
  configuration && configuration.fetch("absoluteGatePassed")
end
automated_gate_status =
  if !unsafe_comparisons.empty?
    "failed"
  elsif !promotion_scope_complete || !missing_comparisons.empty?
    "incomplete"
  elsif !required_automated_gates_pass
    "failed"
  else
    "passed"
  end
promotion_decision =
  if !unsafe_comparisons.empty?
    "not_eligible_unsafe_disagreement"
  elsif automated_gate_status == "incomplete"
    "not_eligible_incomplete_evaluation_scope"
  elsif automated_gate_status == "failed"
    "not_eligible_automated_quality_gate"
  else
    "requires_external_device_review"
  end
resolved_candidate_order = require_array!(
  manifest.fetch("resolvedCandidateOrder"), "manifest resolvedCandidateOrder"
)
resolved_candidate_order.each do |candidate|
  require_member!(candidate, %w[baseline22Field deterministicFirst hybrid], "resolved candidate")
end
fail!("manifest resolvedCandidateOrder contains duplicates") unless
  resolved_candidate_order.uniq.length == resolved_candidate_order.length
fail!("manifest resolvedCandidateOrder does not match evaluation blocks") unless
  resolved_candidate_order.sort == block_dimensions.map(&:first).uniq.sort
resolved_reasoning_policy_order = require_array!(
  manifest.fetch("resolvedReasoningPolicyOrder"), "manifest resolvedReasoningPolicyOrder"
)
resolved_reasoning_policy_order.each do |reasoning_policy|
  require_member!(reasoning_policy, %w[capabilityAwareLight disabled], "resolved reasoning policy")
end
fail!("manifest resolvedReasoningPolicyOrder contains duplicates") unless
  resolved_reasoning_policy_order.uniq.length == resolved_reasoning_policy_order.length
fail!("manifest resolvedReasoningPolicyOrder does not match evaluation blocks") unless
  resolved_reasoning_policy_order.sort == block_dimensions.map { |dimensions| dimensions[3] }.uniq.sort
order_seed = require_integer!(manifest.fetch("orderSeed"), "manifest orderSeed")
fail!("manifest orderSeed must be nonnegative") if order_seed.negative?
revision = require_hash!(manifest.fetch("revision"), "manifest revision")
sanitized_revision = {
  "commit" => require_string!(revision.fetch("commit"), "manifest revision commit"),
  "patchHash" => require_string!(revision.fetch("patchHash"), "manifest revision patchHash")
}
toolchain = require_hash!(manifest.fetch("toolchain"), "manifest toolchain")
sanitized_toolchain = {
  "xcode" => require_string!(toolchain.fetch("xcode"), "manifest toolchain xcode"),
  "sdk" => require_string!(toolchain.fetch("sdk"), "manifest toolchain sdk")
}
report = {
  "schemaVersion" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "sourceManifestSHA256" => Digest::SHA256.hexdigest(manifest_contents),
  "corpusVersion" => corpus_version,
  "repeats" => repeats,
  "includesInputText" => false,
  "orderSeed" => order_seed,
  "filters" => sanitized_filters,
  "resolvedCaseOrder" => case_order,
  "resolvedCandidateOrder" => resolved_candidate_order,
  "resolvedReasoningPolicyOrder" => resolved_reasoning_policy_order,
  "revision" => sanitized_revision,
  "toolchain" => sanitized_toolchain,
  "sourceReports" => source_reports,
  "configurations" => configurations,
  "caseComparisons" => case_comparisons,
  "candidateComparisons" => candidate_comparisons,
  "meaningfulCandidateDisagreementCount" => meaningful_comparisons.length,
  "meaningfulCandidateDisagreements" => meaningful_comparisons,
  "pairedComparisonComplete" => missing_comparisons.empty?,
  "missingComparisonCount" => missing_comparisons.length,
  "missingComparisons" => missing_comparisons,
  "unsafeCandidateDisagreementCount" => unsafe_comparisons.length,
  "unsafeCandidateDisagreements" => unsafe_comparisons,
  "unsafeHybridDisagreementCount" => unsafe_hybrid_comparisons.length,
  "unsafeHybridDisagreements" => unsafe_hybrid_comparisons,
  "promotionScopeComplete" => promotion_scope_complete,
  "automatedSafetyGateStatus" => automated_gate_status,
  "promotionDecision" => promotion_decision,
  "requiredExternalEvidence" => [
    "operator_confirmed_foreground_state",
    "end_to_end_actionable_ui_latency",
    "memory",
    "energy",
    "thermal",
    "background_and_interruption_recovery",
    "human_review_of_failures_and_disagreements"
  ]
}

encoded = JSON.pretty_generate(report) << "\n"
atomic_write(output_path, encoded)
checksum = Digest::SHA256.hexdigest(encoded)
atomic_write("#{output_path}.sha256", "#{checksum}  #{File.basename(output_path)}\n")
puts output_path
