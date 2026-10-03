import XCTest
@testable import PDFEngine

final class PDFOutlineTests: XCTestCase {
    
    func testFilterEmptyQueryReturnsAllNodes() {
        let node1 = PDFOutlineNode(title: "Chapter 1", uri: nil, targetPage: 0)
        let node2 = PDFOutlineNode(title: "Chapter 2", uri: nil, targetPage: 10)
        let nodes = [node1, node2]
        
        let filteredEmpty = PDFOutlineNode.filter(nodes: nodes, query: "")
        XCTAssertEqual(filteredEmpty.count, 2)
        XCTAssertEqual(filteredEmpty[0].id, node1.id)
        XCTAssertEqual(filteredEmpty[1].id, node2.id)
        
        let filteredWhitespace = PDFOutlineNode.filter(nodes: nodes, query: "   \n  ")
        XCTAssertEqual(filteredWhitespace.count, 2)
    }
    
    func testFilterMatchingNodePreservesHierarchyAndIDs() {
        let sub1 = PDFOutlineNode(title: "Background", uri: nil, targetPage: 2)
        let sub2 = PDFOutlineNode(title: "Methodology", uri: nil, targetPage: 5)
        let ch1 = PDFOutlineNode(title: "Chapter 1: Overview", uri: nil, targetPage: 0, children: [sub1, sub2])
        let ch2 = PDFOutlineNode(title: "Chapter 2: Results", uri: nil, targetPage: 10)
        
        let nodes = [ch1, ch2]
        
        // Search for "method" (matches sub2)
        let result = PDFOutlineNode.filter(nodes: nodes, query: "method")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, ch1.id)
        XCTAssertEqual(result[0].title, "Chapter 1: Overview")
        XCTAssertEqual(result[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].id, sub2.id)
        XCTAssertEqual(result[0].children[0].title, "Methodology")
    }
    
    func testFilterCaseInsensitive() {
        let node = PDFOutlineNode(title: "Quantum Computing", uri: nil, targetPage: 0)
        
        XCTAssertEqual(PDFOutlineNode.filter(nodes: [node], query: "quantum").count, 1)
        XCTAssertEqual(PDFOutlineNode.filter(nodes: [node], query: "QUANTUM").count, 1)
        XCTAssertEqual(PDFOutlineNode.filter(nodes: [node], query: "COMPUTING").count, 1)
        XCTAssertEqual(PDFOutlineNode.filter(nodes: [node], query: "xyz").count, 0)
    }
    
    func testFindActiveNodeId() {
        let sub1 = PDFOutlineNode(title: "Section 1.1", uri: nil, targetPage: 2)
        let sub2 = PDFOutlineNode(title: "Section 1.2", uri: nil, targetPage: 5)
        let ch1 = PDFOutlineNode(title: "Chapter 1", uri: nil, targetPage: 0, children: [sub1, sub2])
        let ch2 = PDFOutlineNode(title: "Chapter 2", uri: nil, targetPage: 10)
        let outline = [ch1, ch2]
        
        // Page 0: Chapter 1
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 0), ch1.id)
        
        // Page 1: Still Chapter 1 (before Sec 1.1 on page 2)
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 1), ch1.id)
        
        // Page 2: Section 1.1
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 2), sub1.id)
        
        // Page 4: Still Section 1.1
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 4), sub1.id)
        
        // Page 5: Section 1.2
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 5), sub2.id)
        
        // Page 8: Still Section 1.2
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 8), sub2.id)
        
        // Page 10: Chapter 2
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 10), ch2.id)
        
        // Page 20: Still Chapter 2
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 20), ch2.id)
        
        // Negative page returns nil
        XCTAssertNil(PDFOutlineNode.findActiveNodeId(in: outline, for: -1))
    }
    
    func testFindActiveNodeWithPageBeforeFirstSection() {
        let ch1 = PDFOutlineNode(title: "Chapter 1", uri: nil, targetPage: 5)
        let outline = [ch1]
        
        // Pages 0 to 4 are before the first chapter
        XCTAssertNil(PDFOutlineNode.findActiveNodeId(in: outline, for: 0))
        XCTAssertNil(PDFOutlineNode.findActiveNodeId(in: outline, for: 4))
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 5), ch1.id)
    }

    func testFilterExcludesNonMatchingDescendantsWhenParentMatches() {
        let general = PDFOutlineNode(title: "General", uri: nil, targetPage: 10)
        let parameters = PDFOutlineNode(title: "Parameters", uri: nil, targetPage: 12)
        let precoding = PDFOutlineNode(title: "Precoding for MU-MIMO", uri: nil, targetPage: 15)
        let muMimo = PDFOutlineNode(title: "MU-MIMO Overview", uri: nil, targetPage: 10, children: [general, parameters, precoding])
        let siso = PDFOutlineNode(title: "SISO Transmission", uri: nil, targetPage: 20)
        
        let outline = [muMimo, siso]
        
        // Searching "MU-MIMO":
        // muMimo matches self.
        // Among its children, only "Precoding for MU-MIMO" matches.
        // "General" and "Parameters" MUST NOT be included!
        let result = PDFOutlineNode.filter(nodes: outline, query: "MU-MIMO")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "MU-MIMO Overview")
        XCTAssertEqual(result[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].title, "Precoding for MU-MIMO")
        
        // Searching "Overview":
        // muMimo matches self, but none of its children match "Overview".
        // Its children MUST be empty (no "General", "Parameters", or "Precoding")!
        let resultOverview = PDFOutlineNode.filter(nodes: outline, query: "Overview")
        XCTAssertEqual(resultOverview.count, 1)
        XCTAssertEqual(resultOverview[0].title, "MU-MIMO Overview")
        XCTAssertTrue(resultOverview[0].children.isEmpty)
    }

    func testFindActiveNodeIdWithMultipleHeadingsOnSamePage() {
        let sub1 = PDFOutlineNode(title: "Section 1.1", uri: nil, targetPage: 5)
        let sub2 = PDFOutlineNode(title: "Section 1.2", uri: nil, targetPage: 5)
        let ch1 = PDFOutlineNode(title: "Chapter 1", uri: nil, targetPage: 5, children: [sub1, sub2])
        let ch2 = PDFOutlineNode(title: "Chapter 2", uri: nil, targetPage: 10)
        let outline = [ch1, ch2]
        
        // Page 5: Should pick Chapter 1 (the first heading on page 5), NOT sub2!
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 5), ch1.id)
        
        // Page 6: Subsections started on page 5 and continue onto page 6.
        // Last preceding heading before page 6 is sub2!
        XCTAssertEqual(PDFOutlineNode.findActiveNodeId(in: outline, for: 6), sub2.id)
    }
}


