import SwiftUI
import UIKit

enum ChatPalette {
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
        }

        if !trimmedText.isEmpty {
          Text(trimmedText)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              isEditing ? Color.accentColor.opacity(0.55) : Color.accentColor,
              in: ChatBubbleShape(isUser: true)
            )
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
        .frame(maxWidth: 320, alignment: .leading)
      Spacer(minLength: 56)
    }
    .accessibilityLabel(text)
  }
}

struct ChatTypingBubble: View {
  let label: String
  var onStop: (() -> Void)?

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text(label)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(ChatPalette.assistantFill, in: ChatBubbleShape(isUser: false))

      if let onStop {
        Button(action: onStop) {
          Image(systemName: "stop.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
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
    let radius: CGFloat = 18
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
