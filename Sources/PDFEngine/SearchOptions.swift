import Foundation

/// User-configurable search matching behavior, applied uniformly wherever a
/// query is compiled into a regex (see `SmartRegexBuilder` / `PDFSearchActor`).
public struct SearchOptions: Sendable, Equatable {
    /// When false (default), matching is case-insensitive.
    public var matchCase: Bool
    /// When true, only matches bounded by word boundaries at the start/end of the query.
    public var wholeWord: Bool
    /// When true (default), hyphens/dashes/soft-hyphens/whitespace are treated as
    /// interchangeable and smart quotes are normalized (see `SmartRegexBuilder.buildPattern`).
    /// When false, the query is matched literally.
    public var smartSearch: Bool

    public init(matchCase: Bool = false, wholeWord: Bool = false, smartSearch: Bool = true) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.smartSearch = smartSearch
    }
}
