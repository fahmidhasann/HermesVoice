import Foundation
import HermesVoiceKit

enum VoiceFlowTests {
    static let cases: [TestCase] = [
        TestCase(name: "default flow is transcribe → review → send") {
            checkEqual(AppSettings.default.voiceFlow, .reviewSend,
                       "accurate-by-default flow fills the field for review")
        },
        TestCase(name: "stopsOnSilence is true except push-to-talk") {
            check(VoiceFlow.reviewSend.stopsOnSilence, "review auto-stops on silence")
            check(VoiceFlow.autoSend.stopsOnSilence, "auto-send auto-stops on silence")
            check(!VoiceFlow.pushToTalk.stopsOnSilence, "push-to-talk holds the mic open")
        },
        TestCase(name: "review flow fills the input, never sends") {
            checkEqual(VoiceFlow.reviewSend.outcome(for: "hello there"),
                       .fill("hello there"))
        },
        TestCase(name: "auto-send flow sends immediately") {
            checkEqual(VoiceFlow.autoSend.outcome(for: "send this"),
                       .send("send this"))
        },
        TestCase(name: "push-to-talk sends on release") {
            checkEqual(VoiceFlow.pushToTalk.outcome(for: "talk now"),
                       .send("talk now"))
        },
        TestCase(name: "empty / whitespace transcript is ignored for every flow") {
            for flow in VoiceFlow.allCases {
                checkEqual(flow.outcome(for: "   \n  "), .ignore,
                           "\(flow) ignores a no-speech transcript")
                checkEqual(flow.outcome(for: ""), .ignore,
                           "\(flow) ignores an empty transcript")
            }
        },
        TestCase(name: "outcome trims surrounding whitespace") {
            checkEqual(VoiceFlow.reviewSend.outcome(for: "  padded  "),
                       .fill("padded"))
            checkEqual(VoiceFlow.autoSend.outcome(for: "\n trimmed \n"),
                       .send("trimmed"))
        },
    ]
}
