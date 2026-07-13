import Foundation

struct AppConfiguration: Sendable {
  let proxyBaseURL: URL?
  let debugUSDAAPIKey: String?

  static var current: AppConfiguration {
    let dictionary = Bundle.main.infoDictionary ?? [:]
    let proxyString = sanitized(dictionary["ProxyBaseURL"] as? String)
    let key = sanitized(dictionary["USDADebugAPIKey"] as? String)
    return AppConfiguration(
      proxyBaseURL: proxyString.flatMap(URL.init(string:)),
      debugUSDAAPIKey: key
    )
  }

  var providerDescription: String {
    if proxyBaseURL != nil { return "Privacy proxy" }
    #if DEBUG
      if debugUSDAAPIKey != nil { return "Direct USDA (Debug)" }
    #endif
    return "Not configured"
  }

  private static func sanitized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
    return trimmed
  }
}
