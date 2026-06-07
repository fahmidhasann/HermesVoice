import SwiftUI
import HermesVoiceKit

/// In-panel, searchable list of past conversations. Flips into place over the
/// chat surface when the history button (or ⌘F) is used. Click a row to open it,
/// the back button (or Esc) to return. Keyboard: ⌘F focuses search, ↑/↓ move the
/// selection, Enter opens it, Esc goes back.
struct HistoryView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var searchFocused: Bool
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchField
            Divider().background(Theme.Colors.divider)
            listView
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.historySearchShouldFocus) { _, should in
            if should { searchFocused = true }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Button(action: viewModel.closeHistory) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Back (Esc)")
                .accessibilityLabel("Back")

                Text("History")
                    .font(Theme.Font.header(size: 14))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(viewModel.filteredHistory.count)")
                    .font(Theme.Font.status(size: 10.5))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)

            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(height: 1)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary)

            TextField("Search conversations…", text: $viewModel.historyQuery)
                .font(Theme.Font.message(size: 13))
                .foregroundColor(Theme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.return) { openSelected(); return .handled }
                .onKeyPress(.escape) { viewModel.closeHistory(); return .handled }
                .accessibilityLabel("Search conversations")

            if !viewModel.historyQuery.isEmpty {
                Button(action: { viewModel.historyQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(searchFocused ? Theme.Colors.accent.opacity(0.55)
                                                     : Theme.Colors.hairline,
                                      lineWidth: searchFocused ? 1.5 : 0.5)
                )
        )
        .animation(Theme.Motion.ifMotion(.easeOut(duration: 0.15)), value: searchFocused)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        let entries = viewModel.filteredHistory
        if entries.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            HistoryRow(
                                entry: entry,
                                isSelected: index == clampedSelection(in: entries),
                                onOpen: { viewModel.openConversation(id: entry.id) },
                                onDelete: { viewModel.deleteConversation(id: entry.id) }
                            )
                            .id(entry.id)
                            .onTapGesture { viewModel.openConversation(id: entry.id) }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
                }
                .frame(maxHeight: Theme.Layout.panelMaxHeight - 150)
                .onChange(of: selectedIndex) { _, _ in
                    let clamped = clampedSelection(in: entries)
                    if entries.indices.contains(clamped) {
                        withAnimation(Theme.Motion.ifMotion(.easeOut(duration: 0.15))) {
                            proxy.scrollTo(entries[clamped].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: viewModel.historyQuery.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.Gradients.accent.opacity(0.7))
            Text(viewModel.historyQuery.isEmpty
                 ? "No conversations yet"
                 : "No matches for “\(viewModel.historyQuery)”")
                .font(Theme.Font.message(size: 13))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    // MARK: - Keyboard selection

    /// Keep the stored selection within the current (possibly filtered) range.
    private func clampedSelection(in entries: [OverlayViewModel.HistoryEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), entries.count - 1)
    }

    private func moveSelection(_ delta: Int) {
        let entries = viewModel.filteredHistory
        guard !entries.isEmpty else { return }
        selectedIndex = min(max(clampedSelection(in: entries) + delta, 0), entries.count - 1)
    }

    private func openSelected() {
        let entries = viewModel.filteredHistory
        let index = clampedSelection(in: entries)
        guard entries.indices.contains(index) else { return }
        viewModel.openConversation(id: entries[index].id)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: OverlayViewModel.HistoryEntry
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.meta.title)
                    .font(Theme.Font.messageEmphasized(size: 13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .font(Theme.Font.message(size: 11.5))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(ConversationStore.relativeTime(from: entry.meta.lastActiveAt))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Colors.textSecondary.opacity(0.7))
                Text("\(entry.meta.messageCount) msg")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.Colors.textSecondary.opacity(0.5))
            }

            // Delete affordance — revealed on hover to keep rows tidy.
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Theme.Colors.error)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
                .accessibilityLabel("Delete conversation")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Theme.Motion.ifMotion(.easeOut(duration: 0.12))) {
                isHovered = hovering
            }
        }
    }

    /// Selected rows take a soft amber gradient wash + hairline; hovered rows a
    /// faint neutral lift. Both use the continuous rounded shape for consistency.
    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        if isSelected {
            shape
                .fill(Theme.Gradients.accent.opacity(0.16))
                .overlay(shape.strokeBorder(Theme.Colors.accent.opacity(0.30), lineWidth: 0.5))
        } else if isHovered {
            shape.fill(Theme.Colors.textPrimary.opacity(0.05))
        } else {
            Color.clear
        }
    }
}
