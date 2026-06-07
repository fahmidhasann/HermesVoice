import Foundation

/// Pure parser for the `API_SERVER_KEY` value out of a `.env` file body.
public enum APIKeyParser {
    private static let keyPrefix = "API_SERVER_KEY="

    /// Returns the API key found in the given env-file contents, or `nil`
    /// if the key is absent. Surrounding single/double quotes are stripped.
    public static func parse(env contents: String) -> String? {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(keyPrefix) else { continue }
            let value = String(trimmed.dropFirst(keyPrefix.count))
            return value.trimmingCharacters(in: .init(charactersIn: "\"'"))
        }
        return nil
    }
}
