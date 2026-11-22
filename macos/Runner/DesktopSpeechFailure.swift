import Foundation

/// Map the documented Speech errors by domain and code, not by whether a
/// partial transcript happened to arrive before the failure.
/// https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error
enum DesktopSpeechFailure: String {
  case dictationDisabled = "voice_dictation_disabled"
  case assetsMissing = "voice_assets_missing"
  case permission = "voice_permission"
  case busy = "voice_busy"
  case noMatch = "voice_no_match"
  case network = "voice_network"
  case unavailable = "voice_unavailable"

  static func classify(_ error: NSError) -> DesktopSpeechFailure {
    var current: NSError? = error
    // Speech can wrap the local recognizer's error in an assistant error.
    // Bound traversal so a malformed underlying-error chain cannot hang UI.
    for _ in 0..<8 {
      guard let value = current else { break }
      switch (value.domain, value.code) {
      case ("kLSRErrorDomain", 201): return .dictationDisabled
      case ("kLSRErrorDomain", 102): return .assetsMissing
      case ("kAFAssistantErrorDomain", 1700): return .permission
      case ("kAFAssistantErrorDomain", 1100): return .busy
      case ("kAFAssistantErrorDomain", 1110): return .noMatch
      case (NSURLErrorDomain, _): return .network
      default: current = value.userInfo[NSUnderlyingErrorKey] as? NSError
      }
    }
    return .unavailable
  }
}
