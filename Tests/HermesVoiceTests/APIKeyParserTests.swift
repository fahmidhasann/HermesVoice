import HermesVoiceKit

enum APIKeyParserTests {
    static let cases: [TestCase] = [
        TestCase(name: "parses plain value") {
            checkEqual(APIKeyParser.parse(env: "API_SERVER_KEY=hermes-abc123"), "hermes-abc123")
        },
        TestCase(name: "strips double quotes") {
            checkEqual(APIKeyParser.parse(env: #"API_SERVER_KEY="hermes-abc123""#), "hermes-abc123")
        },
        TestCase(name: "strips single quotes") {
            checkEqual(APIKeyParser.parse(env: "API_SERVER_KEY='hermes-abc123'"), "hermes-abc123")
        },
        TestCase(name: "finds key among other lines") {
            let env = """
            # Hermes config
            OTHER_VALUE=42
            API_SERVER_KEY=hermes-xyz
            TRAILING=1
            """
            checkEqual(APIKeyParser.parse(env: env), "hermes-xyz")
        },
        TestCase(name: "tolerates leading whitespace") {
            checkEqual(APIKeyParser.parse(env: "   API_SERVER_KEY=hermes-x"), "hermes-x")
        },
        TestCase(name: "returns nil when absent") {
            check(APIKeyParser.parse(env: "OTHER=1\nFOO=bar") == nil, "absent key returns nil")
        },
        TestCase(name: "empty value returns empty string") {
            checkEqual(APIKeyParser.parse(env: "API_SERVER_KEY="), "")
        },
    ]
}
