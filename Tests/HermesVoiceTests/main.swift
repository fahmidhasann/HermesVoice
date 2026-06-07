// Entry point for the standalone test runner.
// Run with: swift run HermesVoiceTests

let allCases =
    PanelStateMachineTests.cases +
    DebouncerTests.cases +
    SSEParserTests.cases +
    APIKeyParserTests.cases +
    ConversationStoreTests.cases +
    HermesErrorTests.cases +
    AppSettingsTests.cases

runAllTests(allCases)
