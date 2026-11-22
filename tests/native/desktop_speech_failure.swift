import Foundation

@main
struct SpeechFailureTests {
  static func main() {
    // Actual failure from the macOS Speech service after permission was granted.
    let disabled = NSError(domain: "kLSRErrorDomain", code: 201,
                           userInfo: [NSLocalizedDescriptionKey: "Siri and Dictation are disabled"])
    precondition(DesktopSpeechFailure.classify(disabled) == .dictationDisabled)
    let wrapped = NSError(domain: "kAFAssistantErrorDomain", code: 203,
                          userInfo: [NSUnderlyingErrorKey: disabled])
    precondition(DesktopSpeechFailure.classify(wrapped) == .dictationDisabled)
    let cases: [(String, Int, DesktopSpeechFailure)] = [
      ("kLSRErrorDomain", 102, .assetsMissing),
      ("kLSRErrorDomain", 300, .unavailable),
      ("kAFAssistantErrorDomain", 1700, .permission),
      ("kAFAssistantErrorDomain", 1100, .busy),
      ("kAFAssistantErrorDomain", 1101, .unavailable),
      ("kAFAssistantErrorDomain", 1107, .unavailable),
      ("kAFAssistantErrorDomain", 1110, .noMatch),
      (NSURLErrorDomain, NSURLErrorNotConnectedToInternet, .network),
      (NSURLErrorDomain, NSURLErrorTimedOut, .network),
      ("unrelated", 201, .unavailable),
      ("unrelated", 1110, .unavailable),
      ("kLSRErrorDomain", 999, .unavailable),
    ]
    for (domain, code, expected) in cases {
      let actual = DesktopSpeechFailure.classify(NSError(domain: domain, code: code))
      precondition(actual == expected, "Incorrect failure category for \(domain) \(code)")
    }
    print("{\"passed\":true,\"checks\":\(cases.count + 2),\"microphoneOpened\":false}")
  }
}
