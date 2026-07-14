import Foundation

/// A single turn in the logging conversation transcript.
enum ConversationTurn: Identifiable, Equatable {
  /// User text, optionally with a photo (bytes stay on-device for the session only).
  case user(id: UUID, text: String, imageData: Data?)
  case system(id: UUID, text: String)

  var id: UUID {
    switch self {
    case .user(let id, _, _), .system(let id, _):
      return id
    }
  }

  var isUser: Bool {
    if case .user = self { return true }
    return false
  }

  var text: String {
    switch self {
    case .user(_, let text, _), .system(_, let text):
      return text
    }
  }

  var imageData: Data? {
    if case .user(_, _, let data) = self { return data }
    return nil
  }
}
