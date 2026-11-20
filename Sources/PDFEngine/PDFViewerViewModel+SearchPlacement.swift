//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import SwiftUI
import Foundation

/// What shows in the column on the window's right when Search and the Inspector are both there.
public enum RightColumnPane: Sendable {
    case search
    case inspector
}

/// Search can move from the sidebar to the column on the window's right, which it shares with
/// the Inspector, so the outline and the results can be seen together. Each document keeps the
/// side it was last moved to.
extension PDFViewerViewModel {
    /// Search is in the right column, whether or not the Inspector is in front of it.
    var showsSearchOnRight: Bool { isSearchOnRight && isRightSearchShown }

    /// Whether the right column shows: for the Inspector, Search, or both.
    public var isRightColumnShown: Bool { isInspectorVisible || showsSearchOnRight }

    /// Whether the right column holds both Search and the Inspector, with a control to switch.
    public var isRightColumnShared: Bool { isInspectorVisible && showsSearchOnRight }

    /// The Inspector shows, not behind Search.
    public var isInspectorOnScreen: Bool { isInspectorVisible && (!showsSearchOnRight || rightColumnPane == .inspector) }

    /// Search shows on the right, not behind the Inspector.
    public var isRightSearchOnScreen: Bool { showsSearchOnRight && (!isInspectorVisible || rightColumnPane == .search) }

    /// Closes the right column, with what's in it.
    public func closeRightColumn() {
        isInspectorVisible = false
        isRightSearchShown = false
    }

    /// Hides Search on the right, leaving the Inspector if it's open.
    public func closeRightSearch() {
        isRightSearchShown = false
    }

    /// Shows Search on the right, in front of the Inspector, for Find.
    public func showRightSearch() {
        isRightSearchShown = true
        rightColumnPane = .search
    }

    /// Moves Search to the right column or back to the sidebar, for this document. The window
    /// moves the sidebar off the Search tab, or onto it.
    public func moveSearch(toRight: Bool) {
        isSearchOnRight = toRight
        isRightSearchShown = toRight
        if toRight { rightColumnPane = .search }
        guard !isTransientWindow, let doc = document else { return }
        ReadingStateManager.shared.setSearchOnRight(toRight, for: doc.filePath)
    }
}
