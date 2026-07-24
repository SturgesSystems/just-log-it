#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

def fail_resolution(message)
  warn "error: #{message}"
  exit 2
end

json_path = ARGV.fetch(0) { fail_resolution("missing devicectl JSON path") }
requested_identifier = ARGV[1]&.strip
requested_identifier = nil if requested_identifier&.empty?

begin
  document = JSON.parse(File.read(json_path))
rescue Errno::ENOENT
  fail_resolution("devicectl did not create its JSON result")
rescue JSON::ParserError => error
  fail_resolution("devicectl returned invalid JSON (#{error.message})")
end

unless document.dig("info", "outcome") == "success"
  fail_resolution("devicectl did not successfully enumerate devices")
end

devices = document.dig("result", "devices")
fail_resolution("devicectl JSON did not contain a device list") unless devices.is_a?(Array)

iphones = devices.each_with_object([]) do |device, eligible|
  properties = device.fetch("properties", {})
  connection = properties.fetch("connection", {})
  hardware = properties.fetch("hardware", {})

  next unless connection["state"] == "connected"
  next unless hardware["platform"] == "iOS"
  next unless hardware["reality"] == "physical"
  next unless hardware["deviceType"] == "iPhone"

  core_device_identifier = device["identifier"]
  hardware_udid = hardware["udid"]
  next unless core_device_identifier.is_a?(String) && !core_device_identifier.empty?
  next unless hardware_udid.is_a?(String) && !hardware_udid.empty?

  eligible << {
    core_device_identifier: core_device_identifier,
    hardware_udid: hardware_udid
  }
end

selected = if requested_identifier
  iphones.select do |device|
    device.fetch(:core_device_identifier).casecmp?(requested_identifier) ||
      device.fetch(:hardware_udid).casecmp?(requested_identifier)
  end
else
  iphones
end

if selected.empty?
  if requested_identifier
    fail_resolution("#{requested_identifier} is not a connected physical iPhone (hardware UDID or CoreDevice identifier)")
  end
  fail_resolution("no connected physical iPhone was found; connect, unlock, trust, and enable Developer Mode on the device")
end

if selected.length > 1
  warn "Connected physical iPhones:"
  selected.each do |device|
    warn "  UDID=#{device.fetch(:hardware_udid)} CoreDevice=#{device.fetch(:core_device_identifier)}"
  end
  fail_resolution("more than one iPhone is connected; pass --device-id <hardware-UDID-or-CoreDevice-identifier>")
end

device = selected.fetch(0)
puts device.fetch(:core_device_identifier)
puts device.fetch(:hardware_udid)
