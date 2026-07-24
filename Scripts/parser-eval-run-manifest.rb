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

def atomic_write(path, value)
  directory = File.dirname(path)
  Dir.mkdir(directory, 0o700) unless Dir.exist?(directory)
  Tempfile.create(["manifest", ".tmp"], directory, mode: File::RDWR, perm: 0o600) do |file|
    file.write(JSON.pretty_generate(value) << "\n")
    file.flush
    file.fsync
    File.rename(file.path, path)
  end
end

def load_manifest(path)
  JSON.parse(File.read(path))
rescue Errno::ENOENT, JSON::ParserError => error
  fail!("cannot read run manifest: #{error.message}")
end

def save_manifest(path, manifest)
  manifest["updatedAt"] = Time.now.utc.iso8601
  atomic_write(path, manifest)
end

def find_block(manifest, block_id)
  manifest.fetch("blocks").find { |block| block.fetch("id") == block_id } ||
    fail!("unknown block: #{block_id}")
end

def csv(value)
  value.to_s.split(",").map(&:strip).reject(&:empty?).uniq
end

def seeded_key(seed, value)
  hash = 1_469_598_103_934_665_603 ^ seed
  value.bytes.each do |byte|
    hash ^= byte
    hash = (hash * 1_099_511_628_211) & 0xffff_ffff_ffff_ffff
  end
  hash
end

command = ARGV.shift || fail!("a command is required")
options = {}
OptionParser.new do |parser|
  parser.on("--manifest PATH") { |value| options[:manifest] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--corpus-source PATH") { |value| options[:corpus_source] = value }
  parser.on("--corpus-version VALUE") { |value| options[:corpus_version] = value }
  parser.on("--candidates CSV") { |value| options[:candidates] = value }
  parser.on("--warm-states CSV") { |value| options[:warm_states] = value }
  parser.on("--model-use-cases CSV") { |value| options[:model_use_cases] = value }
  parser.on("--reasoning-policies CSV") { |value| options[:reasoning_policies] = value }
  parser.on("--case-ids CSV") { |value| options[:case_ids] = value }
  parser.on("--families CSV") { |value| options[:families] = value }
  parser.on("--order-seed INTEGER") { |value| options[:order_seed] = value }
  parser.on("--repeats INTEGER") { |value| options[:repeats] = value }
  parser.on("--include-input VALUE") { |value| options[:include_input] = value }
  parser.on("--probe VALUE") { |value| options[:probe] = value }
  parser.on("--commit VALUE") { |value| options[:commit] = value }
  parser.on("--patch-hash VALUE") { |value| options[:patch_hash] = value }
  parser.on("--xcode-version VALUE") { |value| options[:xcode_version] = value }
  parser.on("--sdk-version VALUE") { |value| options[:sdk_version] = value }
  parser.on("--block ID") { |value| options[:block] = value }
  parser.on("--report PATH") { |value| options[:report] = value }
  parser.on("--result PATH") { |value| options[:result] = value }
  parser.on("--reason CODE") { |value| options[:reason] = value }
  parser.on("--field NAME") { |value| options[:field] = value }
end.parse!(ARGV)

if command == "revision-hash"
  root = options[:root] || fail!("--root is required")
  digest = Digest::SHA256.new
  digest << IO.popen(["git", "-C", root, "diff", "--binary", "HEAD"], &:read)
  status = IO.popen(
    ["git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all"],
    &:read
  )
  digest << status
  status.split("\0").grep(/^\?\? /).map { |line| line.delete_prefix("?? ") }.sort.each do |path|
    full_path = File.join(root, path)
    digest << path
    digest << File.binread(full_path) if File.file?(full_path)
  end
  puts digest.hexdigest
  exit 0
end

manifest_path = options[:manifest] || fail!("--manifest is required")

case command
when "create"
  fail!("manifest already exists: #{manifest_path}") if File.exist?(manifest_path)
  source_path = options[:corpus_source] || fail!("--corpus-source is required")
  source = File.read(source_path)
  corpus_cases = source.scan(/\.init\(\s*id:\s*"([^"]+)"\s*,\s*category:\s*\.([A-Za-z]+)/m)
  fail!("could not resolve corpus cases") if corpus_cases.empty?
  all_ids = corpus_cases.map(&:first)
  all_families = corpus_cases.map(&:last).uniq
  requested_ids = csv(options[:case_ids])
  requested_families = csv(options[:families])
  unknown_ids = requested_ids - all_ids
  unknown_families = requested_families - all_families
  fail!("unknown case IDs: #{unknown_ids.join(",")}") unless unknown_ids.empty?
  fail!("unknown families: #{unknown_families.join(",")}") unless unknown_families.empty?
  selected = corpus_cases.select do |id, family|
    (requested_ids.empty? && requested_families.empty?) || requested_ids.include?(id) || requested_families.include?(family)
  end
  fail!("filters selected no corpus cases") if selected.empty?
  seed = Integer(options[:order_seed] || "0", 10)
  fail!("--order-seed must be nonnegative") if seed.negative?
  case_order = selected.map(&:first).sort_by { |id| [seeded_key(seed, id), id] }
  candidates = csv(options[:candidates])
  warm_states = csv(options[:warm_states])
  model_use_cases = csv(options[:model_use_cases])
  reasoning_policies = csv(options[:reasoning_policies])
  fail!("candidate, warm-state, model-use-case, and reasoning-policy matrices must not be empty") if
    candidates.empty? || warm_states.empty? || model_use_cases.empty? || reasoning_policies.empty?
  unknown_reasoning_policies = reasoning_policies - %w[capabilityAwareLight disabled]
  fail!("unknown reasoning policies: #{unknown_reasoning_policies.join(",")}") unless
    unknown_reasoning_policies.empty?
  candidate_order = candidates.shuffle(random: Random.new(seed))
  blocks = []
  candidate_order.each_with_index do |candidate, candidate_index|
    warm_order = warm_states.shuffle(random: Random.new(seed ^ ((candidate_index + 1) * 0x9e37_79b9)))
    warm_order.each do |warm_state|
      model_use_cases.each do |model_use_case|
        reasoning_policies.each do |reasoning_policy|
          number = blocks.length + 1
          blocks << {
            "id" => format(
              "%02d-%s-%s-%s-%s",
              number, candidate, warm_state, model_use_case, reasoning_policy
            ),
            "candidate" => candidate,
            "warmState" => warm_state,
            "modelUseCase" => model_use_case,
            "reasoningPolicy" => reasoning_policy,
            "status" => "planned",
            "attempts" => 0
          }
        end
      end
    end
  end
  now = Time.now.utc.iso8601
  atomic_write(manifest_path, {
    "schemaVersion" => 1,
    "createdAt" => now,
    "updatedAt" => now,
    "corpusVersion" => options[:corpus_version],
    "repeats" => Integer(options[:repeats], 10),
    "includesInputText" => options[:include_input] == "1",
    "configurationProbeOnly" => options[:probe] == "1",
    "orderSeed" => seed,
    "filters" => { "caseIDs" => requested_ids, "families" => requested_families },
    "resolvedCaseOrder" => case_order,
    "resolvedCandidateOrder" => candidate_order,
    "resolvedReasoningPolicyOrder" => reasoning_policies,
    "revision" => { "commit" => options[:commit], "patchHash" => options[:patch_hash] },
    "toolchain" => { "xcode" => options[:xcode_version], "sdk" => options[:sdk_version] },
    "blocks" => blocks
  })
when "reset-running"
  manifest = load_manifest(manifest_path)
  manifest.fetch("blocks").each do |block|
    next unless block.fetch("status") == "running"
    block["status"] = "interrupted"
    block["interruptionReason"] = "runner_exit"
    block["interruptedAt"] = Time.now.utc.iso8601
  end
  save_manifest(manifest_path, manifest)
when "next"
  manifest = load_manifest(manifest_path)
  manifest.fetch("blocks").each do |block|
    next unless block.fetch("status") == "complete"
    report = block.dig("artifacts", "report")
    checksum = block.dig("checksums", "reportSHA256")
    fail!("complete block #{block.fetch("id")} has no validated report") unless
      report && checksum && File.file?(report) && Digest::SHA256.file(report).hexdigest == checksum
  end
  block = manifest.fetch("blocks").find { |item| item.fetch("status") != "complete" }
  if block
    puts [block.fetch("id"), block.fetch("candidate"), block.fetch("warmState"),
          block.fetch("modelUseCase"), block.fetch("reasoningPolicy")].join("\t")
  end
when "running"
  manifest = load_manifest(manifest_path)
  block = find_block(manifest, options[:block] || fail!("--block is required"))
  fail!("cannot run complete block #{block.fetch("id")}") if block.fetch("status") == "complete"
  block["status"] = "running"
  block["attempts"] = block.fetch("attempts", 0) + 1
  block["startedAt"] = Time.now.utc.iso8601
  block.delete("interruptionReason")
  save_manifest(manifest_path, manifest)
when "complete"
  manifest = load_manifest(manifest_path)
  block = find_block(manifest, options[:block] || fail!("--block is required"))
  fail!("block is not running: #{block.fetch("id")}") unless block.fetch("status") == "running"
  report = options[:report] || fail!("--report is required")
  result = options[:result] || fail!("--result is required")
  fail!("report does not exist: #{report}") unless File.file?(report)
  fail!("result bundle does not exist: #{result}") unless File.directory?(result)
  block["status"] = "complete"
  block["completedAt"] = Time.now.utc.iso8601
  block["artifacts"] = { "report" => File.expand_path(report), "resultBundle" => File.expand_path(result) }
  block["checksums"] = {
    "reportSHA256" => Digest::SHA256.file(report).hexdigest,
    "resultMarkerSHA256" => Digest::SHA256.hexdigest(Dir.glob(File.join(result, "**", "*")).sort.join("\n"))
  }
  save_manifest(manifest_path, manifest)
when "interrupted"
  manifest = load_manifest(manifest_path)
  block = find_block(manifest, options[:block] || fail!("--block is required"))
  unless block.fetch("status") == "complete"
    block["status"] = "interrupted"
    block["interruptedAt"] = Time.now.utc.iso8601
    block["interruptionReason"] = options[:reason] || "runner_exit"
    save_manifest(manifest_path, manifest)
  end
when "config"
  manifest = load_manifest(manifest_path)
  values = {
    "repeats" => manifest.fetch("repeats"),
    "includeInput" => manifest.fetch("includesInputText") ? 1 : 0,
    "orderSeed" => manifest.fetch("orderSeed"),
    "caseIDs" => manifest.dig("filters", "caseIDs").join(","),
    "families" => manifest.dig("filters", "families").join(","),
    "reasoningPolicies" => manifest.fetch("resolvedReasoningPolicyOrder").join(","),
    "probe" => manifest.fetch("configurationProbeOnly", false) ? 1 : 0
  }
  field = options[:field] || fail!("--field is required")
  fail!("unknown config field: #{field}") unless values.key?(field)
  puts values.fetch(field)
when "verify-revision"
  manifest = load_manifest(manifest_path)
  fail!("run commit differs from the current commit; start a new run") unless
    manifest.dig("revision", "commit") == options[:commit]
  fail!("worktree patch differs from the planned run; start a new run") unless
    manifest.dig("revision", "patchHash") == options[:patch_hash]
else
  fail!("unknown command: #{command}")
end
