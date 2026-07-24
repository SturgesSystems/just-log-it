#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

def fail_resolution(message)
  warn "error: #{message}"
  exit 2
end

simctl_path = ARGV.fetch(0) { fail_resolution("missing simctl JSON path") }
destinations_path = ARGV.fetch(1) { fail_resolution("missing xcodebuild destinations path") }

begin
  runtimes = JSON.parse(File.read(simctl_path)).fetch("devices")
rescue Errno::ENOENT => error
  fail_resolution("could not read simulator input (#{error.message})")
rescue JSON::ParserError => error
  fail_resolution("simctl returned invalid JSON (#{error.message})")
rescue KeyError
  fail_resolution("simctl JSON did not contain devices")
end

begin
  destinations = File.read(destinations_path)
rescue Errno::ENOENT => error
  fail_resolution("could not read Xcode destinations (#{error.message})")
end
compatible_section = destinations.split(/Destinations incompatible/, 2).first
compatible_ids = compatible_section.scan(/\{[^\n]*platform:iOS Simulator,[^\n]*\bid:([^, }]+)/).flatten.to_h { |id| [id, true] }

candidates = runtimes.each_with_object([]) do |(runtime, devices), eligible|
  next unless runtime.include?("SimRuntime.iOS-")
  next unless devices.is_a?(Array)

  version = runtime[/SimRuntime\.iOS-(.+)\z/, 1].to_s.split("-").map(&:to_i)
  devices.each do |device|
    udid = device["udid"]
    next unless device["isAvailable"] != false
    next unless device["deviceTypeIdentifier"].to_s.include?("SimDeviceType.iPhone-")
    next unless udid.is_a?(String) && compatible_ids[udid]

    eligible << {
      udid: udid,
      name: device["name"].to_s,
      booted_priority: device["state"] == "Booted" ? 0 : 1,
      version_priority: version.map { |part| -part }
    }
  end
end

fail_resolution("no available, scheme-compatible iPhone Simulator was found") if candidates.empty?

# Prefer a booted phone to avoid unnecessary boot work. Within each state,
# prefer the newest runtime and then stable name/UDID ordering.
selected = candidates.min_by do |candidate|
  [candidate.fetch(:booted_priority), candidate.fetch(:version_priority), candidate.fetch(:name), candidate.fetch(:udid)]
end
puts selected.fetch(:udid)
