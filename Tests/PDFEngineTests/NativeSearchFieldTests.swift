import Foundation
import AppKit
import SwiftUI
import Testing
@testable import PDFEngine

@Suite(.serialized)
struct NativeSearchFieldTests {
    @Test @MainActor func testNativeSearchFieldOverflowAndScrollable() {
        var query = ""
        let binding = Binding<String>(get: { query }, set: { query = $0 })
        let searchFieldRep = NativeSearchField(text: binding, onCommit: {})
        let coordinator = searchFieldRep.makeCoordinator()
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        
        let field = NSSearchField(frame: NSRect(x: 10, y: 50, width: 100, height: 24))
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        coordinator.searchField = field
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        
        #expect(field.cell?.isScrollable == true)
        #expect(field.cell?.wraps == false)
        #expect(field.usesSingleLineMode == true)
        
        guard let ed = field.currentEditor() as? NSTextView else {
            Issue.record("Expected currentEditor to be NSTextView")
            return
        }
        
        #expect(ed.isHorizontallyResizable == true)
        #expect(ed.textContainer?.widthTracksTextView == false)
        
        let longQuery = "This is a very long search term that exceeds the visible width of the search field"
        ed.string = longQuery
        ed.setSelectedRange(NSRange(location: longQuery.count, length: 0))
        coordinator.scrollToSelection(in: ed)
        
        if let clip = ed.superview as? NSClipView {
            #expect(clip.bounds.origin.x > 22.0)
            
            ed.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator.scrollToSelection(in: ed)
            #expect(clip.bounds.origin.x <= 25.0)
        }
    }

    @Test @MainActor func testSearchPageGroupsAndNavigation() {
        let vm = PDFViewerViewModel()
        let match1 = SearchResult(pageIndex: 0, matchedText: "foo", snippet: "foo snippet 1", highlightQuads: [])
        let match2 = SearchResult(pageIndex: 0, matchedText: "foo", snippet: "foo snippet 2", highlightQuads: [])
        let match3 = SearchResult(pageIndex: 2, matchedText: "foo", snippet: "foo snippet 3", highlightQuads: [])
        let match4 = SearchResult(pageIndex: 5, matchedText: "foo", snippet: "foo snippet 4", highlightQuads: [])

        vm.searchResults = [match1, match2, match3, match4]

        let groups = vm.searchPageGroups
        #expect(groups.count == 3)
        #expect(groups[0].pageIndex == 0)
        #expect(groups[0].matches.count == 2)
        #expect(groups[1].pageIndex == 2)
        #expect(groups[1].matches.count == 1)
        #expect(groups[2].pageIndex == 5)
        #expect(groups[2].matches.count == 1)

        vm.navigateToMatch(match3)
        #expect(vm.activeSearchMatchIndex == 2)
        #expect(vm.activeSearchMatchId == match3.id)
        #expect(vm.currentPageIndex == 2)
    }
}

