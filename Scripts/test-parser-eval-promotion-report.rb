#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class ParserEvalPromotionReportTest < Minitest::Test
  SCRIPT = File.expand_path("parser-eval-promotion-report.rb", __dir__)
  CASE_IDS = %w[simple.one safety.one].freeze
  PROFILES = {
    "baseline22Field" => %w[production leanCandidate],
    "deterministicFirst" => %w[production],
    "hybrid" => %w[minimal]
  }.freeze

  def setup
    @directory = Dir.mktmpdir("justlogit-promotion-report-")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_aggregates_false_values_and_writes_a_verified_redacted_report
    fixture = build_fixture(
      filters: { "caseIDs" => [], "families" => [], "privateNote" => "private food text" }
    )
    deterministic_report = fixture.fetch(:reports).fetch(["deterministicFirst", "cold", "general"])
    mutate_report(fixture, deterministic_report) do |report|
      item = report.fetch("observations").find do |observation|
        observation.fetch("caseID") == "simple.one" && observation.fetch("run") == 1
      end
      item["sourceGrounded"] = false
      item["requiredFieldsCorrect"] = false
      item["behaviorCorrect"] = false
      item["routeCorrect"] = false
      item["interpretationRoute"] = "manualSearch"
      item["stableWithFirstRun"] = false
      item["modelInvoked"] = false
      item["deterministicFastPathUsed"] = false
    end

    output, stdout, stderr, status = run_report(fixture)
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"
    report = JSON.parse(File.read(output))
    configuration = report.fetch("configurations").find do |item|
      item.fetch("candidate") == "deterministicFirst" && item.fetch("warmState") == "cold"
    end
    assert_in_delta 0.75, configuration.fetch("sourceGroundingRate")
    assert_in_delta 0.75, configuration.fetch("requiredFieldRate")
    assert_in_delta 0.75, configuration.fetch("behaviorRate")
    assert_in_delta 0.75, configuration.fetch("routeAccuracy")
    assert_in_delta 2.0 / 3.0, configuration.fetch("stabilityRate")
    assert_in_delta 0.75, configuration.fetch("modelInvocationRate")
    assert_in_delta 0.75, configuration.fetch("deterministicFastPathRate")
    assert_equal true, report.fetch("promotionScopeComplete")
    assert_equal true, report.fetch("pairedComparisonComplete")
    assert_equal false, configuration.fetch("absoluteGatePassed")
    assert_equal "failed", report.fetch("automatedSafetyGateStatus")
    assert_equal "not_eligible_unsafe_disagreement", report.fetch("promotionDecision")
    assert_operator report.fetch("unsafeCandidateDisagreementCount"), :>, 0
    assert_includes report.fetch("unsafeCandidateDisagreements").map { |item| item.fetch("candidate") },
                    "deterministicFirst"
    assert_equal false, report.fetch("includesInputText")
    refute_includes File.read(output), "private food text"

    checksum_line = File.read("#{output}.sha256")
    assert_equal "#{Digest::SHA256.file(output).hexdigest}  #{File.basename(output)}\n", checksum_line
    assert_equal 0o600, File.stat(output).mode & 0o777
    assert_equal 0o600, File.stat("#{output}.sha256").mode & 0o777
  end

  def test_complete_safe_automated_evidence_still_requires_external_review
    fixture = build_fixture

    output, _stdout, stderr, status = run_report(fixture)
    assert status.success?, stderr
    report = JSON.parse(File.read(output))
    assert report.fetch("configurations").all? { |item| item.fetch("absoluteGatePassed") }
    assert_equal "passed", report.fetch("automatedSafetyGateStatus")
    assert_equal "requires_external_device_review", report.fetch("promotionDecision")
    assert_includes report.fetch("requiredExternalEvidence"), "energy"
  end

  def test_reasoning_policy_is_a_first_class_configuration_and_comparison_dimension
    fixture = build_fixture(reasoning_policies: %w[capabilityAwareLight disabled])

    output, _stdout, stderr, status = run_report(fixture)
    assert status.success?, stderr
    report = JSON.parse(File.read(output))
    assert_equal %w[capabilityAwareLight disabled],
                 report.fetch("resolvedReasoningPolicyOrder")
    assert_equal %w[capabilityAwareLight disabled],
                 report.fetch("configurations").map { |item| item.fetch("reasoningPolicy") }.uniq
    assert_equal %w[capabilityAwareLight disabled],
                 report.fetch("caseComparisons").map { |item| item.fetch("reasoningPolicy") }.uniq
    assert_equal true, report.fetch("promotionScopeComplete")
  end

  def test_marks_a_paired_safety_regression_ineligible
    fixture = build_fixture
    hybrid_report = fixture.fetch(:reports).fetch(["hybrid", "prewarmed", "general"])
    mutate_report(fixture, hybrid_report) do |report|
      item = report.fetch("observations").find do |observation|
        observation.fetch("caseID") == "safety.one" && observation.fetch("run") == 2
      end
      item["sourceGrounded"] = false
      item["unsupportedInventedFacts"] = true
      item["routeCorrect"] = false
      item["interpretationRoute"] = "manualSearch"
    end

    output, _stdout, stderr, status = run_report(fixture)
    assert status.success?, stderr
    report = JSON.parse(File.read(output))
    assert_equal "failed", report.fetch("automatedSafetyGateStatus")
    assert_equal "not_eligible_unsafe_disagreement", report.fetch("promotionDecision")
    assert_equal 1, report.fetch("unsafeHybridDisagreementCount")
    assert_equal %w[
      candidate_lost_source_grounding candidate_unsupported_invented_fact candidate_wrong_route
    ], report.fetch("unsafeHybridDisagreements").first.dig("comparison", "unsafeReasons")
  end

  def test_classifies_both_candidates_with_only_closed_privacy_safe_dimensions
    fixture = build_fixture
    baseline_path = fixture.fetch(:reports).fetch(["baseline22Field", "cold", "general"])
    mutate_report(fixture, baseline_path) do |report|
      item = find_observation(report, "production", "simple.one", 1)
      item["requiredFieldsCorrect"] = false
    end
    deterministic_path = fixture.fetch(:reports).fetch(["deterministicFirst", "cold", "general"])
    mutate_report(fixture, deterministic_path) do |report|
      find_observation(report, "production", "simple.one", 2)["requiredFieldsCorrect"] = false
      find_observation(report, "production", "safety.one", 1)["usdaRouting"] =
        "compositeHandoff"
    end

    output, _stdout, stderr, status = run_report(fixture)
    assert status.success?, stderr
    report = JSON.parse(File.read(output))
    comparisons = report.fetch("candidateComparisons")
    assert_equal 16, comparisons.length
    assert_equal %w[deterministicFirst hybrid], comparisons.map { |item| item.fetch("candidate") }.uniq

    candidate_win = find_comparison(comparisons, "deterministicFirst", "simple.one", 1)
    assert_equal "candidate_improvement", candidate_win.dig("comparison", "classification")
    assert_equal ["requiredFieldsCorrect"],
                 candidate_win.dig("comparison", "candidateImprovementDimensions")
    production_win = find_comparison(comparisons, "deterministicFirst", "simple.one", 2)
    assert_equal "production_improvement", production_win.dig("comparison", "classification")
    assert_equal ["requiredFieldsCorrect"],
                 production_win.dig("comparison", "productionImprovementDimensions")
    both_acceptable = find_comparison(comparisons, "deterministicFirst", "safety.one", 1)
    assert_equal "both_acceptable", both_acceptable.dig("comparison", "classification")
    assert_equal ["usdaTerminal"], both_acceptable.dig("comparison", "changedDimensions")
    assert_equal false, both_acceptable.dig("comparison", "contentEquivalenceEvaluated")
    assert_equal true, both_acceptable.dig("comparison", "privateHumanReviewRequired")
    serialized = JSON.generate(report.fetch("meaningfulCandidateDisagreements"))
    refute_match(/input|query|clarification(text|prompt)|fdc|fingerprint|digest|hash/i, serialized)
  end

  def test_focused_or_unpaired_evidence_cannot_look_promotion_ready
    fixture = build_fixture(
      candidates: %w[hybrid],
      warm_states: %w[cold],
      filters: { "caseIDs" => ["simple.one"], "families" => [] }
    )

    output, _stdout, stderr, status = run_report(fixture)
    assert status.success?, stderr
    report = JSON.parse(File.read(output))
    assert_equal false, report.fetch("promotionScopeComplete")
    assert_equal false, report.fetch("pairedComparisonComplete")
    assert_operator report.fetch("missingComparisonCount"), :>, 0
    assert_equal "incomplete", report.fetch("automatedSafetyGateStatus")
    assert_equal "not_eligible_incomplete_evaluation_scope", report.fetch("promotionDecision")
  end

  def test_rejects_missing_observation_from_an_otherwise_complete_block
    fixture = build_fixture
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) { |report| report.fetch("observations").pop }

    assert_rejected(fixture, "observation coverage mismatch")
  end

  def test_rejects_non_boolean_score_instead_of_treating_it_as_truthy
    fixture = build_fixture
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) do |report|
      report.fetch("observations").first["sourceGrounded"] = "false"
    end

    assert_rejected(fixture, "sourceGrounded must be boolean")
  end

  def test_rejects_raw_input_without_echoing_it
    fixture = build_fixture
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) do |report|
      report.fetch("observations").first["input"] = "private food text"
    end

    _output, _stdout, stderr, status = run_report(fixture)
    refute status.success?
    assert_includes stderr, "leaked raw input"
    refute_includes stderr, "private food text"
  end

  def test_rejects_negative_latency_and_report_checksum_mismatch
    fixture = build_fixture
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) do |report|
      report.fetch("observations").first["latencyMilliseconds"] = -1
    end
    assert_rejected(fixture, "finite nonnegative number")

    fixture = build_fixture(suffix: "checksum")
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    File.open(report_path, "a") { |file| file.write(" \n") }
    assert_rejected(fixture, "checksum mismatch")
  end

  def test_rejects_open_ended_usda_terminal_and_inconsistent_typed_route
    fixture = build_fixture(suffix: "usda-terminal")
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) do |report|
      report.fetch("observations").first["usdaRouting"] = "query=private food text"
    end
    assert_rejected(fixture, "usdaRouting is unsupported")

    fixture = build_fixture(suffix: "route-consistency")
    report_path = fixture.fetch(:reports).fetch(["hybrid", "cold", "general"])
    mutate_report(fixture, report_path) do |report|
      report.fetch("observations").first["routeCorrect"] = false
    end
    assert_rejected(fixture, "route correctness is inconsistent")
  end

  def test_rejects_incomplete_and_probe_manifests
    fixture = build_fixture
    manifest = JSON.parse(File.read(fixture.fetch(:manifest)))
    manifest.fetch("blocks").first["status"] = "interrupted"
    write_json(fixture.fetch(:manifest), manifest)
    assert_rejected(fixture, "incomplete blocks")

    fixture = build_fixture(suffix: "probe")
    manifest = JSON.parse(File.read(fixture.fetch(:manifest)))
    manifest["configurationProbeOnly"] = true
    write_json(fixture.fetch(:manifest), manifest)
    assert_rejected(fixture, "configuration probes do not produce promotion reports")
  end

  def test_runner_keeps_configuration_probe_out_of_the_promotion_aggregator
    runner = File.read(File.expand_path("run-on-device-parser-eval.sh", __dir__))
    finalization_source = runner[runner.rindex('echo "All checksum-validated parser evaluation blocks are complete."')..-1]
    finalization = finalization_source[/if \[\[ "\$PROBE_ONLY" == "1" \]\]; then.*?^fi$/m]
    refute_nil finalization
    probe_branch, corpus_branch = finalization.split(/^else$/, 2)
    refute_includes probe_branch, "parser-eval-promotion-report.rb"
    assert_includes corpus_branch, "parser-eval-promotion-report.rb"
  end

  private

  def build_fixture(
    candidates: %w[baseline22Field deterministicFirst hybrid],
    warm_states: %w[cold prewarmed],
    model_use_cases: %w[general],
    reasoning_policies: %w[capabilityAwareLight],
    filters: { "caseIDs" => [], "families" => [] },
    suffix: "default"
  )
    fixture_directory = File.join(@directory, suffix)
    FileUtils.mkdir_p(fixture_directory)
    blocks = []
    reports = {}
    candidates.product(warm_states, model_use_cases, reasoning_policies).each_with_index do |dimensions, index|
      candidate, warm_state, model_use_case, reasoning_policy = dimensions
      id = format(
        "%02d-%s-%s-%s-%s",
        index + 1, candidate, warm_state, model_use_case, reasoning_policy
      )
      report_path = File.join(fixture_directory, "#{id}.json")
      observations = PROFILES.fetch(candidate).flat_map do |profile|
        CASE_IDS.flat_map do |case_id|
          (1..2).map do |run|
            observation(
              candidate, warm_state, model_use_case, reasoning_policy, profile, case_id, run
            )
          end
        end
      end
      write_json(report_path, {
        "corpusVersion" => "1.3.0",
        "repeats" => 2,
        "includesInputText" => false,
        "warmStates" => [warm_state],
        "reasoningPolicies" => [reasoning_policy],
        "observations" => observations
      })
      blocks << {
        "id" => id,
        "candidate" => candidate,
        "warmState" => warm_state,
        "modelUseCase" => model_use_case,
        "reasoningPolicy" => reasoning_policy,
        "status" => "complete",
        "artifacts" => { "report" => report_path },
        "checksums" => { "reportSHA256" => Digest::SHA256.file(report_path).hexdigest }
      }
      reports[dimensions] = report_path
      reports[[candidate, warm_state, model_use_case]] ||= report_path
    end
    manifest_path = File.join(fixture_directory, "run-manifest.json")
    write_json(manifest_path, {
      "schemaVersion" => 1,
      "corpusVersion" => "1.3.0",
      "repeats" => 2,
      "includesInputText" => false,
      "configurationProbeOnly" => false,
      "orderSeed" => 42,
      "filters" => filters,
      "resolvedCaseOrder" => CASE_IDS,
      "resolvedCandidateOrder" => candidates,
      "resolvedReasoningPolicyOrder" => reasoning_policies,
      "revision" => { "commit" => "test", "patchHash" => "test" },
      "toolchain" => { "xcode" => "test", "sdk" => "27.0" },
      "blocks" => blocks
    })
    { manifest: manifest_path, reports: reports }
  end

  def observation(candidate, warm_state, model_use_case, reasoning_policy, profile, case_id, run)
    {
      "corpusVersion" => "1.3.0",
      "promptProfile" => profile,
      "modelUseCase" => model_use_case,
      "reasoningPolicy" => reasoning_policy,
      "warmState" => warm_state,
      "caseID" => case_id,
      "run" => run,
      "outcome" => "parsed",
      "latencyMilliseconds" => run == 1 ? 10.0 : 20.0,
      "sourceGrounded" => true,
      "requiredFieldsCorrect" => true,
      "unsupportedInventedFacts" => false,
      "behaviorCorrect" => true,
      "usdaRouting" => "directSearch",
      "stableWithFirstRun" => run == 1 ? nil : true,
      "inputTokenCount" => nil,
      "outputTokenCount" => nil,
      "reasoningTokenCount" => nil,
      "humanReviewRequired" => false,
      "input" => nil,
      "candidate" => candidate,
      "expectedRoute" => "deterministicSearch",
      "routeCorrect" => candidate == "baseline22Field" ? nil : true,
      "interpretationRoute" => candidate == "baseline22Field" ? nil : "deterministicSearch",
      "modelInvoked" => true,
      "deterministicFastPathUsed" => candidate == "deterministicFirst" ? true : nil
    }
  end

  def mutate_report(fixture, path)
    report = JSON.parse(File.read(path))
    yield report
    write_json(path, report)
    manifest = JSON.parse(File.read(fixture.fetch(:manifest)))
    block = manifest.fetch("blocks").find { |item| item.dig("artifacts", "report") == path }
    block.fetch("checksums")["reportSHA256"] = Digest::SHA256.file(path).hexdigest
    write_json(fixture.fetch(:manifest), manifest)
  end

  def find_observation(report, profile, case_id, run)
    report.fetch("observations").find do |item|
      item.fetch("promptProfile") == profile && item.fetch("caseID") == case_id &&
        item.fetch("run") == run
    end
  end

  def find_comparison(comparisons, candidate, case_id, run)
    comparisons.find do |item|
      item.fetch("candidate") == candidate && item.fetch("warmState") == "cold" &&
        item.fetch("caseID") == case_id && item.fetch("run") == run
    end
  end

  def run_report(fixture)
    output = File.join(File.dirname(fixture.fetch(:manifest)), "promotion-report.json")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, SCRIPT, "--manifest", fixture.fetch(:manifest), "--output", output
    )
    [output, stdout, stderr, status]
  end

  def assert_rejected(fixture, message)
    output, _stdout, stderr, status = run_report(fixture)
    refute status.success?
    assert_equal 2, status.exitstatus, stderr
    assert_includes stderr, message
    refute File.exist?(output), "a rejected artifact must not produce an output report"
  end

  def write_json(path, value)
    File.write(path, JSON.pretty_generate(value) << "\n")
  end
end
