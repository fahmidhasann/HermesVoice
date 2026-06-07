import SwiftUI
import MarkdownUI
import Highlightr

/// Renders an assistant message as GitHub-flavored markdown themed to the warm
/// amber palette. Fenced code blocks are syntax-highlighted (Highlightr) and
/// carry a per-block copy button; lists/tables/headings/quotes render natively
/// and links open in the browser.
struct MarkdownMessageView: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.hermes)
            .markdownCodeSyntaxHighlighter(.hermes)
            .markdownBlockStyle(\.codeBlock) { configuration in
                HermesCodeBlockView(configuration: configuration)
            }
            // Render incomplete markdown (mid-stream) without flipping layout.
            .textSelection(.enabled)
    }
}

// MARK: - Theme

extension MarkdownUI.Theme {
    /// Amber-tinted markdown theme built on top of `.basic` so lists, tables,
    /// headings, and quotes keep sensible system-adapting defaults.
    static var hermes: MarkdownUI.Theme {
        MarkdownUI.Theme.basic
            .text {
                ForegroundColor(Theme.Colors.textPrimary)
                FontSize(13.5)
            }
            .link {
                ForegroundColor(Theme.Colors.accent)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.92))
                BackgroundColor(Theme.Colors.textPrimary.opacity(0.06))
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle { FontStyle(.italic) }
                    .padding(.leading, Theme.Spacing.md)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.Colors.accent.opacity(0.5))
                            .frame(width: 3)
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
            }
    }
}

// MARK: - Code block (header + copy button + horizontal scroll)

private struct HermesCodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(copied ? .green : Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied" : "Copy code")
                .accessibilityLabel("Copy code block")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Colors.textPrimary.opacity(0.05))

            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .background(Theme.Colors.textPrimary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
        .markdownMargin(top: 8, bottom: 8)
    }

    private var languageLabel: String {
        let lang = (configuration.language ?? "").trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? "code" : lang.lowercased()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.content, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - Syntax highlighting

/// `CodeSyntaxHighlighter` backed by Highlightr (highlight.js). Picks a light or
/// dark highlight theme to match the current appearance.
struct HermesCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        guard let attributed = HighlightrEngine.shared.highlight(code, language: language) else {
            return Text(code).font(.system(size: 12, design: .monospaced))
        }
        return Text(AttributedString(attributed))
    }
}

extension CodeSyntaxHighlighter where Self == HermesCodeSyntaxHighlighter {
    static var hermes: HermesCodeSyntaxHighlighter { HermesCodeSyntaxHighlighter() }
}

/// Shared Highlightr instance. `highlight` is only called on the main thread
/// (during SwiftUI body evaluation), so no extra synchronization is needed.
private final class HighlightrEngine {
    static let shared = HighlightrEngine()

    private let highlightr = Highlightr()
    private var currentTheme = ""
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        applyThemeForAppearance()
        let lang = language?.trimmingCharacters(in: .whitespaces)
        // An unknown language makes Highlightr return nil; fall back to auto.
        let resolved = (lang?.isEmpty == false && highlightr?.supportedLanguages().contains(lang!) == true)
            ? lang
            : nil
        let result = highlightr?.highlight(code, as: resolved, fastRender: true)
        return result.map(trimTrailingNewline)
    }

    /// Highlightr appends a trailing newline to each block; drop it so the code
    /// block doesn't render an extra blank line.
    private func trimTrailingNewline(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.string.hasSuffix("\n") else { return attributed }
        return attributed.attributedSubstring(from: NSRange(location: 0, length: attributed.length - 1))
    }

    private func applyThemeForAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = isDark ? "atom-one-dark" : "atom-one-light"
        guard name != currentTheme else { return }
        _ = highlightr?.setTheme(to: name)
        highlightr?.theme.setCodeFont(codeFont)
        currentTheme = name
    }
}
