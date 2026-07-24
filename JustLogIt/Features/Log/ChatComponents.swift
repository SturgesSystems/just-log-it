import SwiftUI
import UIKit

enum ChatPalette {
  static let cardCornerRadius: CGFloat = 20
  static let bubbleCornerRadius: CGFloat = 18
  static let chipCornerRadius: CGFloat = 16

  static var canvas: Color {
    Color(.systemGroupedBackground)
  }

  static var assistantFill: Color {
    Color(.secondarySystemGroupedBackground)
  }

  static var chipFill: Color {
    Color(.tertiarySystemFill)
  }

  static var composerField: Color {
    Color(.secondarySystemGroupedBackground)
  }

  /// Card/bubble borders. Separator alone is already faint in dark mode; extra
  /// opacity must stay high enough that chrome does not disappear.
  static var hairline: Color {
    Color(uiColor: UIColor { traits in
      let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.55 : 0.35
      return UIColor.separator.withAlphaComponent(alpha)
    })
  }

  /// Soft canvas wash — layered under grouped background for depth without busy chrome.
  static func canvasGradient(for colorScheme: ColorScheme) -> LinearGradient {
    if colorScheme == .dark {
      return LinearGradient(
        colors: [
          Color(.systemGroupedBackground),
          Color.accentColor.opacity(0.06),
          Color(.systemGroupedBackground),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    return LinearGradient(
      colors: [
        Color(.systemGroupedBackground),
        Color.accentColor.opacity(0.05),
        Color(.secondarySystemGroupedBackground).opacity(0.55),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// Brand fill for user bubbles. Always solid enough for white labels —
  /// never wash out with low opacity (that fails contrast in light mode).
  static var userBubbleGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color.accentColor,
        Color.accentColor.opacity(0.82),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  static func cardShadow(colorScheme: ColorScheme, reduceMotion: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
    if reduceMotion {
      return (.clear, 0, 0)
    }
    if colorScheme == .dark {
      return (Color.black.opacity(0.35), 10, 4)
    }
    return (Color.black.opacity(0.08), 12, 4)
  }
}

/// Shared chrome for assistant-side cards and dense widgets.
struct ChatCardChrome: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  var cornerRadius: CGFloat = ChatPalette.cardCornerRadius
  var padded: Bool = false

  func body(content: Content) -> some View {
    let shadow = ChatPalette.cardShadow(colorScheme: colorScheme, reduceMotion: reduceMotion)
    content
      .padding(padded ? 14 : 0)
      .background(
        ChatPalette.assistantFill,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
      }
      .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
  }
}

extension View {
  func chatCardChrome(cornerRadius: CGFloat = ChatPalette.cardCornerRadius, padded: Bool = false) -> some View {
    modifier(ChatCardChrome(cornerRadius: cornerRadius, padded: padded))
  }
}

struct ChatUserBubble: View {
  let text: String
  var imageData: Data? = nil
  var isEditing: Bool = false
  var onEdit: (() -> Void)?

  @State private var decodedImage: UIImage?

  private var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    HStack {
      Spacer(minLength: 56)
      VStack(alignment: .trailing, spacing: 6) {
        if let decodedImage {
          Image(uiImage: decodedImage)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 220, maxHeight: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ChatPalette.bubbleCornerRadius, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: ChatPalette.bubbleCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
        }

        if !trimmedText.isEmpty {
          Text(trimmedText)
            .font(.body)
            // White on solid brand accent — not `.primary` (which flips to black
            // in light mode and would vanish on the teal bubble).
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              ChatPalette.userBubbleGradient,
              in: ChatBubbleShape(isUser: true)
            )
            .overlay {
              // Editing is signaled with a ring, not a washed-out fill.
              if isEditing {
                ChatBubbleShape(isUser: true)
                  .stroke(Color.white.opacity(0.65), lineWidth: 1.5)
              }
            }
        }
      }
      .contextMenu {
        if onEdit != nil {
          Button("Edit", systemImage: "pencil") { onEdit?() }
        }
      }
    }
    // Decode the photo once per image, off the render path — not on every
    // transcript re-render (a session photo can be several megabytes).
    .task(id: imageData) {
      decodedImage = imageData.flatMap { UIImage(data: $0) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabelText)
    .accessibilityHint(onEdit == nil ? "" : "Edits this message and restarts from here")
    .accessibilityAction(named: "Edit") { onEdit?() }
  }

  private var accessibilityLabelText: String {
    if imageData != nil {
      return trimmedText.isEmpty ? "You shared a photo" : "You shared a photo: \(trimmedText)"
    }
    return "You said, \(trimmedText)"
  }
}

struct ChatAssistantBubble: View {
  let text: String

  var body: some View {
    HStack {
      Text(text)
        .font(.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ChatPalette.assistantFill, in: ChatBubbleShape(isUser: false))
        .overlay {
          ChatBubbleShape(isUser: false)
            .stroke(ChatPalette.hairline, lineWidth: 0.5)
        }
        .frame(maxWidth: 320, alignment: .leading)
      Spacer(minLength: 56)
    }
    .accessibilityLabel(text)
  }
}

struct ChatTypingBubble: View {
  let label: String
  var onStop: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = false

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
        Text(label)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(ChatPalette.assistantFill, in: ChatBubbleShape(isUser: false))
      .overlay {
        ChatBubbleShape(isUser: false)
          .stroke(ChatPalette.hairline, lineWidth: 0.5)
      }
      .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.78))
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
        value: pulse
      )
      .onAppear {
        guard !reduceMotion else { return }
        pulse = true
      }
      .onChange(of: reduceMotion) { _, reduced in
        pulse = reduced ? false : true
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(label)

      if let onStop {
        Button(action: onStop) {
          Image(systemName: "stop.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityHint("Cancels the current operation")
        .accessibilityIdentifier("cancel-operation")
      }

      Spacer(minLength: 40)
    }
    .accessibilityElement(children: .contain)
  }
}

struct ChatBubbleShape: Shape {
  var isUser: Bool

  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = ChatPalette.bubbleCornerRadius
    let corners: UIRectCorner =
      isUser
      ? [.topLeft, .topRight, .bottomLeft]
      : [.topLeft, .topRight, .bottomRight]
    let path = UIBezierPath(
      roundedRect: rect,
      byRoundingCorners: corners,
      cornerRadii: CGSize(width: radius, height: radius)
    )
    return Path(path.cgPath)
  }
}

/// Simple wrapping chip row without external deps.
struct FlowChips<Item: Hashable, Content: View>: View {
  let items: [Item]
  @ViewBuilder var content: (Item) -> Content

  var body: some View {
    // Vertical stack is more reliable than custom layout for a11y + tests.
    VStack(alignment: .leading, spacing: 8) {
      ForEach(items, id: \.self) { item in
        content(item)
      }
    }
  }
}
