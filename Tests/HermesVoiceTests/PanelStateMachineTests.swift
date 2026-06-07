import HermesVoiceKit

enum PanelStateMachineTests {
    static let cases: [TestCase] = [
        TestCase(name: "starts hidden") {
            let sm = PanelStateMachine()
            checkEqual(sm.phase, .hidden)
        },
        TestCase(name: "full show/hide cycle") {
            var sm = PanelStateMachine()
            check(sm.beginShow(), "beginShow from hidden should succeed")
            checkEqual(sm.phase, .showing)
            sm.finishShow()
            checkEqual(sm.phase, .visible)
            check(sm.beginHide(), "beginHide from visible should succeed")
            checkEqual(sm.phase, .hiding)
            sm.finishHide()
            checkEqual(sm.phase, .hidden)
        },
        TestCase(name: "double beginShow is a no-op (one press = one panel)") {
            var sm = PanelStateMachine()
            check(sm.beginShow(), "first beginShow succeeds")
            check(!sm.beginShow(), "second beginShow while showing must be rejected")
            checkEqual(sm.phase, .showing)
        },
        TestCase(name: "beginHide from hidden is rejected") {
            var sm = PanelStateMachine()
            check(!sm.beginHide(), "beginHide from hidden must be rejected")
            checkEqual(sm.phase, .hidden)
        },
        TestCase(name: "beginHide interrupts showing") {
            var sm = PanelStateMachine()
            sm.beginShow()
            check(sm.beginHide(), "toggling off mid-fade-in should be allowed")
            checkEqual(sm.phase, .hiding)
        },
        TestCase(name: "finishShow only applies from showing") {
            var sm = PanelStateMachine()
            sm.finishShow()
            checkEqual(sm.phase, .hidden)
        },
        TestCase(name: "finishHide only applies from hiding") {
            var sm = PanelStateMachine()
            sm.beginShow()
            sm.finishHide()
            checkEqual(sm.phase, .showing)
        },
        TestCase(name: "forceHidden resets to hidden") {
            var sm = PanelStateMachine()
            sm.beginShow()
            sm.forceHidden()
            checkEqual(sm.phase, .hidden)
        },
    ]
}
