import AVFoundation
import Foundation
import Speech

/// Owns one user-initiated, on-device microphone transcription session.
///
/// Transcription only produces editable composer text. It never submits the composer.
@MainActor
final class VoiceInputController: ObservableObject {
  enum State: Equatable {
    case idle
    case preparing
    case listening
    case stopping

    var hasActiveSession: Bool { self != .idle }
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var transcript = ""
  @Published var errorMessage: String?

  private var analyzer: SpeechAnalyzer?
  private var captureSession: AVCaptureSession?
  private var resultTask: Task<Void, Never>?
  private var sessionTask: Task<Void, Never>?
  private var interruptionObserver: NSObjectProtocol?

  deinit {
    resultTask?.cancel()
    sessionTask?.cancel()
  }

  func start(locale requestedLocale: Locale = .autoupdatingCurrent) {
    guard state == .idle else { return }
    errorMessage = nil
    transcript = ""
    state = .preparing

    sessionTask = Task { [weak self] in
      guard let self else { return }
      do {
        guard await Self.requestMicrophoneAccess() else {
          throw VoiceInputError.microphoneDenied
        }
        try Task.checkCancellation()
        try await self.beginTranscription(locale: requestedLocale)
      } catch is CancellationError {
        await self.cleanUp()
      } catch {
        await self.fail(error)
      }
    }
  }

  /// Ends capture, asks the analyzer for its final result, and leaves the text for Send.
  func stop() {
    guard state == .preparing || state == .listening else { return }
    state = .stopping
    sessionTask?.cancel()
    sessionTask = Task { [weak self] in
      guard let self else { return }
      self.captureSession?.stopRunning()
      do {
        try await self.analyzer?.finalizeAndFinishThroughEndOfInput()
      } catch {
        // A partial transcript remains useful even when finalization is interrupted.
        if self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.errorMessage = VoiceInputError.message(for: error)
        }
      }
      await self.cleanUp(keepResultTask: true)
    }
  }

  func cancel() {
    sessionTask?.cancel()
    resultTask?.cancel()
    captureSession?.stopRunning()
    Task { [weak self] in
      await self?.analyzer?.cancelAndFinishNow()
      await self?.cleanUp()
    }
  }

  private func beginTranscription(locale requestedLocale: Locale) async throws {
    guard SpeechTranscriber.isAvailable else { throw VoiceInputError.unavailable }
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
    else { throw VoiceInputError.unsupportedLocale(requestedLocale) }

    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let modules: [any SpeechModule] = [transcriber]
    switch await AssetInventory.status(forModules: modules) {
    case .unsupported:
      throw VoiceInputError.unsupportedLocale(locale)
    case .installed, .supported:
      break
    case .downloading:
      throw VoiceInputError.modelDownloading
    @unknown default:
      throw VoiceInputError.unavailable
    }

    if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
      try await installation.downloadAndInstall()
    }
    try Task.checkCancellation()

    guard let microphone = AVCaptureDevice.default(for: .audio) else {
      throw VoiceInputError.noMicrophone
    }
    let provider = try await CaptureInputSequenceProvider.providerWithSession(
      from: microphone,
      compatibleWith: modules
    )
    let analyzer = SpeechAnalyzer(
      inputSequence: provider.analyzerInputs,
      modules: modules
    )
    self.analyzer = analyzer
    captureSession = provider.captureSession
    observeInterruption(of: provider.captureSession)
    consumeResults(from: transcriber)

    provider.captureSession.startRunning()
    try Task.checkCancellation()
    state = .listening
  }

  private func consumeResults(from transcriber: SpeechTranscriber) {
    resultTask?.cancel()
    resultTask = Task { [weak self] in
      var finalized = ""
      do {
        for try await result in transcriber.results {
          guard !Task.isCancelled else { return }
          let current = String(result.text.characters)
          if result.isFinal {
            finalized = Self.join(finalized, current)
            self?.transcript = finalized
          } else {
            self?.transcript = Self.join(finalized, current)
          }
        }
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.state != .idle else { return }
        await self.fail(error)
      }
    }
  }

  private func observeInterruption(of session: AVCaptureSession) {
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
    }
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVCaptureSession.wasInterruptedNotification,
      object: session,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.state.hasActiveSession else { return }
        self.errorMessage = "Voice input was interrupted. Your transcribed text is still available."
        self.stop()
      }
    }
  }

  private func fail(_ error: Error) async {
    errorMessage = VoiceInputError.message(for: error)
    captureSession?.stopRunning()
    await analyzer?.cancelAndFinishNow()
    await cleanUp()
  }

  private func cleanUp(keepResultTask: Bool = false) async {
    if !keepResultTask { resultTask?.cancel() }
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
      self.interruptionObserver = nil
    }
    captureSession = nil
    analyzer = nil
    sessionTask = nil
    state = .idle
  }

  private static func requestMicrophoneAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  static func join(_ prefix: String, _ suffix: String) -> String {
    guard !prefix.isEmpty else { return suffix }
    guard !suffix.isEmpty else { return prefix }
    let needsSpace = !prefix.last!.isWhitespace && !suffix.first!.isWhitespace
    return prefix + (needsSpace ? " " : "") + suffix
  }
}

private enum VoiceInputError: LocalizedError {
  case microphoneDenied
  case unavailable
  case unsupportedLocale(Locale)
  case modelDownloading
  case noMicrophone

  static func message(for error: Error) -> String {
    (error as? VoiceInputError)?.errorDescription
      ?? "Voice input couldn't start. You can still type what you ate."
  }

  var errorDescription: String? {
    switch self {
    case .microphoneDenied:
      return "Microphone access is off. Enable Microphone for JustLogIt in Settings, or type what you ate."
    case .unavailable:
      return "On-device transcription isn't available on this device. You can still type what you ate."
    case .unsupportedLocale(let locale):
      return "On-device transcription doesn't support \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) yet."
    case .modelDownloading:
      return "The on-device speech model is still downloading. Try voice input again shortly."
    case .noMicrophone:
      return "No microphone is available. You can still type what you ate."
    }
  }
}
