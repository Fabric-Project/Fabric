//
//  CodeEditorChrome.swift
//  Fabric
//

import SwiftUI
import CodeEditorView
import LanguageSupport

extension Theme
{
    /// The theme every code editor in the app uses, in the appearance the system
    /// is in. `CodeEditor` takes a theme rather than reading the environment, so
    /// it is resolved per editor against that editor's own `\.colorScheme`.
    ///
    /// Both are built once. Writing any of a theme's properties stamps it with a
    /// fresh `id`, and `CodeEditor` restyles the whole text storage whenever that
    /// `id` differs from the one it holds — so a theme built per view update has
    /// a new identity on every keystroke, and is paid for on every keystroke.
    @MainActor
    public static func v(for colorScheme: ColorScheme) -> Theme
    {
        colorScheme == .dark ? Self.vDark : Self.vLight
    }

    @MainActor private static let vDark = Theme.v(basedOn: .defaultDark)
    @MainActor private static let vLight = Theme.v(basedOn: .defaultLight)

    private static func v(basedOn base: Theme) -> Theme
    {
        var theme = base
        theme.fontName = "SFMono-Medium"
        theme.fontSize = 11.0
        return theme
    }
}

/// Everything a `CodeEditor` looks like, wherever it appears. Font travels with
/// the theme, so an editor without this has neither.
///
/// Size is not here: these editors sit in different places — one fills its
/// window, another is a section of a taller stack — and only their placement
/// knows how much room they get.
private struct CodeEditorChrome: ViewModifier
{
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View
    {
        content
            .environment(\.codeEditorTheme, Theme.v(for: self.colorScheme))
            .environment(\.codeEditorLayoutConfiguration, .init(showMinimap: false, wrapText: true))
    }
}

extension View
{
    /// Applies the shared code editor appearance. Pass no `layout:` to the
    /// editor itself — an argument there takes precedence over this.
    func codeEditorChrome() -> some View
    {
        modifier(CodeEditorChrome())
    }
}

/// What to write in the editor below, and where the reference is. The summary
/// carries the shape of the thing — a signature, an entry point, what becomes a
/// port — since that is what cannot be guessed from an empty editor.
struct CodeEditorGuidance: View
{
    private let summary: LocalizedStringKey
    private let guide: LocalizedStringKey?

    init(_ summary: LocalizedStringKey, guide: LocalizedStringKey? = nil)
    {
        self.summary = summary
        self.guide = guide
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 4)
        {
            Text(self.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let guide = self.guide
            {
                // Outside the secondary style, which would take the link colour.
                Text(guide)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
