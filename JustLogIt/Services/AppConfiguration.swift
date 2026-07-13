import Foundation

struct AppConfiguration: Sendable {
  let proxyBaseURL: URL?
  #if DEBUG
    let debugUSDAAPIKey: String?
  #endif

  static var current: AppConfiguration {
    let dictionary = Bundle.main.infoDictionary ?? [:]
    let proxyString = sanitized(dictionary["ProxyBaseURL"] as? String)
    let allowedHost = sanitized(dictionary["ProxyAllowedHost"] as? String)
    let proxyURL = validatedProxyURL(
      proxyString,
      allowedHost: allowedHost,
      requirePinnedHost: releaseRequiresPinnedHost
    )
    #if DEBUG
      let key = sanitized(dictionary["USDADebugAPIKey"] as? String)
      return AppConfiguration(proxyBaseURL: proxyURL, debugUSDAAPIKey: key)
    #else
      return AppConfiguration(proxyBaseURL: proxyURL)
    #endif
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

  static func validatedProxyURL(
    _ value: String?,
    allowedHost: String?,
    requirePinnedHost: Bool
  ) -> URL? {
    guard let value = sanitized(value),
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      let host = components.host, !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
      validHost(host)
    else { return nil }

    let pin = sanitized(allowedHost)
    if requirePinnedHost, pin == nil { return nil }
    if let pin, !validHost(pin) || host.caseInsensitiveCompare(pin) != .orderedSame { return nil }

    guard let url = components.url, url.baseURL == nil else { return nil }
    return url
  }

  private static func validHost(_ host: String) -> Bool {
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }
    return labels.allSatisfy { label in
      guard !label.isEmpty, label.count <= 63,
        label.first?.isLetter == true || label.first?.isNumber == true,
        label.last?.isLetter == true || label.last?.isNumber == true
      else { return false }
      return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }

  private static var releaseRequiresPinnedHost: Bool {
    #if DEBUG
      false
    #else
      true
    #endif
  }
}
