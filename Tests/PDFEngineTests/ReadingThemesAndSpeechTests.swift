import Testing
import Foundation
@testable import PDFEngine

@Suite("Reading Themes & Speech Tests")
struct ReadingThemesAndSpeechTests {
    @Test("PDFColorAppearance cases and display names")
    func testPDFColorAppearanceCases() {
        let cases = PDFColorAppearance.allCases
        #expect(cases.contains(.system))
        #expect(cases.contains(.light))
        #expect(cases.contains(.dark))
        #expect(cases.contains(.sepia))
        
        #expect(PDFColorAppearance.sepia.displayName == "Sepia")
        #expect(PDFColorAppearance.system.displayName == "Follow System")
        #expect(PDFColorAppearance.light.displayName == "Light")
        #expect(PDFColorAppearance.dark.displayName == "Dark")
    }

    @Test("PDFSpeechCoordinator toggle and stop")
    @MainActor
    func testSpeechCoordinator() {
        let coordinator = PDFSpeechCoordinator.shared
        #expect(!coordinator.isSpeaking)

        // Stopping when not speaking is safe no-op
        coordinator.stopSpeaking()
        #expect(!coordinator.isSpeaking)

        // Blank text speaking does not trigger speaking state
        coordinator.startSpeaking("   \n  ")
        #expect(!coordinator.isSpeaking)
    }

    @Test("InstalledBrowser discovery and preferences")
    @MainActor
    func testInstalledBrowsers() {
        let appCoordinator = PDFViewerAppCoordinator.shared
        let browsers = appCoordinator.installedBrowsers
        #expect(!browsers.isEmpty)
        #expect(browsers.first?.id == "system")
        #expect(browsers.first?.name == "System Default")

        // Preferred browser setting persistence
        appCoordinator.preferredBrowserBundleID = "com.apple.Safari"
        #expect(appCoordinator.preferredBrowserBundleID == "com.apple.Safari")

        // Reset to system default
        appCoordinator.preferredBrowserBundleID = "system"
        #expect(appCoordinator.preferredBrowserBundleID == "system")
    }
}
