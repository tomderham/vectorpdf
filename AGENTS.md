# VectorPDF Agent Instructions & Repository Guidelines

## ⚠️ STRICT PRIVACY & PERSONAL IDENTIFIER DIRECTIVE

**CRITICAL RULE:**
- **NEVER** hardcode or commit personal file paths (e.g. `/Users/<username>/...`), personal email addresses (`*@gmail.com`, etc.), or private usernames into tests, fixtures, source code, scripts, or documentation.
- When writing tests or examples that simulate local filesystem paths or cloud storage accounts (such as iCloud Drive, Google Drive, OneDrive, Dropbox, Box):
  - Always use generic dummy usernames and mock domains:
    - Path prefix: `/Users/example/...` or `FileManager.default.homeDirectoryForCurrentUser` (dynamically evaluated at runtime)
    - Cloud account IDs: `user@example.com`, `user@domain.com`, `GoogleDrive-user@example.com`
  - Never copy paste real file paths from user prompt logs or error transcripts into committed test files.

---

## Architecture & Codebase Guidelines

1. **Framework & Engine:**
   - VectorPDF is a native macOS PDF application built in Swift and SwiftUI, backed by a C MuPDF bridge (`MuPDFBridge`) and Swift engine layer (`PDFEngine`).
   - All AppKit / UI interactions must be `@MainActor`-safe.

2. **Windowing & Native Appearance:**
   - Windows use a unified toolbar with tab bar support via `PDFViewerWindow` and `DocumentWindowing`.
   - Window top bar color follows macOS Preview styling with `NSColor.topWindowBarColor`.
   - Native segmented controls, capsules, and toolbars adapt across macOS versions.

3. **Menu Organization:**
   - Keep menus clean and uncluttered. Advanced engineering tools (e.g. scale calibration, takeoff summary tables) belong in their respective toolbars (such as the Measurement toolbar) rather than cluttering global menus.

4. **Testing:**
   - Run tests using `swift test`.
   - Headless test execution: Alerts (such as `NSAlert.runModal()`) must be guarded by checking `ProcessInfo` test runner environment variables to prevent headless test hangs.
   - Always run tests and verify zero regressions before committing.
