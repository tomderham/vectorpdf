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
}

