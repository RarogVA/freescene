import Cocoa
import AVFoundation
import FlutterMacOS
import Speech

/// Captures only an explicitly started voice search. All session state and
/// Flutter callbacks are confined to the main queue; audio is never persisted.
final class DesktopVoiceInput: NSObject, FlutterStreamHandler {
  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var completion: FlutterResult?
  private var engine: AVAudioEngine?
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var limit: Timer?
  private var silence: Timer?
  private var deadline: Timer?
  private var generation = 0
  private var partial = ""
  private var finalizing = false
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "freescene/desktop_voice", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "freescene/desktop_voice/events", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { reply(nil); return }
      switch call.method {
      case "voiceListen":
        let language = (call.arguments as? [String: Any])?["language"] as? String ?? "ru-RU"
        self.listen(language: language, reply: reply)
      case "voiceCancel": self.finish(nil); reply(nil)
      default: reply(FlutterMethodNotImplemented)
      }
    }
    events.setStreamHandler(self)
    observers.append(NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in self?.finish(nil) })
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.finish(nil) })
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
  private func fail(_ code: String) { finish(FlutterError(code: code, message: nil, details: nil)) }
  private func listen(language: String, reply: @escaping FlutterResult) {
    guard completion == nil else { reply(FlutterError(code: "voice_busy", message: nil, details: nil)); return }
    generation += 1
    let session = generation
    completion = reply
    partial = ""
    finalizing = false
    sink?(["phase": "permission"])
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self = self, self.generation == session, self.completion != nil else { return }
        guard status == .authorized else { self.fail("voice_permission"); return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
          DispatchQueue.main.async {
            guard let self = self, self.generation == session, self.completion != nil else { return }
            guard allowed else { self.fail("voice_permission"); return }
            self.start(language: language, session: session)
          }
        }
      }
    }
  }

  private func start(language: String, session: Int) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
      fail("voice_unavailable"); return
    }
    self.recognizer = recognizer
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .search
    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
    self.request = request
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { fail("voice_audio"); return }
    self.engine = engine
    var meteredFrames: AVAudioFrameCount = 0
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      request.append(buffer)
      meteredFrames += buffer.frameLength
      guard Double(meteredFrames) >= format.sampleRate * 0.08 else { return }
      meteredFrames = 0
      var sum: Float = 0
      if let values = buffer.floatChannelData?[0], buffer.frameLength > 0 {
        for i in 0..<Int(buffer.frameLength) { sum += values[i] * values[i] }
      }
      let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
      let level = max(0, min(1, (20 * log10(max(rms, 0.00001)) + 60) / 60))
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.generation == session, !self.finalizing else { return }
        self.sink?(["level": level])
      }
    }
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self = self, self.generation == session, self.completion != nil else { return }
        if let result = result {
          let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
          if result.isFinal {
            if text.isEmpty { self.fail("voice_no_match") } else { self.finish(text) }
            return
          }
          if !text.isEmpty, text != self.partial {
            self.partial = text
            self.sink?(["partial": text])
            if !self.finalizing {
              self.silence?.invalidate()
              self.silence = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.endAudio(session: session)
              }
            }
          }
        }
        if let error = error as NSError? {
          self.fail(error.domain == NSURLErrorDomain ? "voice_network" : (self.partial.isEmpty ? "voice_no_match" : "voice_unavailable"))
        }
      }
    }
    do {
      engine.prepare()
      try engine.start()
      sink?(["phase": "listening"])
      limit = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
        self?.endAudio(session: session)
      }
    } catch { fail("voice_audio") }
  }
  private func stopInput() {
    if let engine = engine {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
      self.engine = nil
    }
  }
  private func endAudio(session: Int) {
    guard generation == session, completion != nil, !finalizing else { return }
    finalizing = true
    limit?.invalidate(); limit = nil
    silence?.invalidate(); silence = nil
    stopInput()
    request?.endAudio()
    sink?(["phase": "recognizing"])
    deadline = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
      guard let self = self, self.generation == session else { return }
      self.fail("voice_timeout")
    }
  }
  private func finish(_ value: Any?) {
    generation += 1
    let reply = completion
    completion = nil
    limit?.invalidate(); limit = nil
    silence?.invalidate(); silence = nil
    deadline?.invalidate(); deadline = nil
    stopInput()
    request?.endAudio(); request = nil
    task?.cancel(); task = nil
    recognizer = nil
    reply?(value)
  }
  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    limit?.invalidate(); silence?.invalidate(); deadline?.invalidate()
    engine?.stop()
    if let engine = engine { engine.inputNode.removeTap(onBus: 0) }
    request?.endAudio(); task?.cancel()
  }
}
