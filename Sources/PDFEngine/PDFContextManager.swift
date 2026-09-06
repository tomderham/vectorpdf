import Foundation
import MuPDFBridge

public typealias FZContext = UnsafeMutablePointer<fz_context>
public typealias FZDocument = UnsafeMutablePointer<fz_document>
public typealias FZPage = UnsafeMutablePointer<fz_page>
public typealias FZDisplayList = OpaquePointer
public typealias FZPixmap = UnsafeMutablePointer<fz_pixmap>
public typealias FZStextPage = UnsafeMutablePointer<fz_stext_page>
public typealias FZOutline = UnsafeMutablePointer<fz_outline>
public typealias FZLink = UnsafeMutablePointer<fz_link>

/// ARCHITECTURAL NOTE: MuPDF Thread Safety & Multi-Actor Concurrency
///
/// In MuPDF, neither `fz_context` nor `fz_document` are thread-safe for concurrent operations:
/// 1. `fz_context`: MuPDF contexts manage memory allocators, font caches, and exception handling
///    via setjmp/longjmp (`fz_try`/`fz_catch`). Sharing a single `fz_context` concurrently across
///    different OS threads without locks causes fatal crashes. Threads must each operate on their
///    own `fz_context` created via `fz_clone_context()`.
/// 2. `fz_document`: While reading/rendering pages or searching text, MuPDF actively mutates internal
///    xref tables, stream decoders, page trees, and font descriptors. Sharing a single `fz_document`
///    pointer concurrently between threads (e.g. searching page 50 while rendering page 2) causes
///    data races and memory corruption.
///
/// Therefore, the application isolates responsibilities across distinct Swift actors:
/// - `PDFRenderActor`: Dedicated background actor with its own cloned context & document for high-speed page tile rasterization.
/// - `PDFSearchActor`: Dedicated background actor with its own cloned context & document for regex full-text searches.
/// - `PDFDocumentCore`: Main thread lock-guarded wrapper for metadata, layout calculations, and AcroForm mutations.
///
/// Manages the root MuPDF context and creates thread-isolated cloned contexts for Swift 6 actors.
public final class PDFContextManager: @unchecked Sendable {
    public static let shared = PDFContextManager()
    
    private let rootContext: FZContext
    private let lock = NSLock()
    
    private init() {
        guard let ctx = mupdf_context_create(32 * 1024 * 1024) else {
            fatalError("Failed to initialize root MuPDF context")
        }
        self.rootContext = ctx
    }
    
    deinit {
        mupdf_context_drop(rootContext)
    }
    
    /// Creates a cloned context for thread-isolated rendering or searching.
    public func makeClonedContext() -> FZContext {
        lock.lock()
        defer { lock.unlock() }
        guard let clone = mupdf_context_clone(rootContext) else {
            fatalError("Failed to clone MuPDF context")
        }
        return clone
    }
    
    /// Destroys a thread context.
    public func dropContext(_ ctx: FZContext) {
        // Locked to match makeClonedContext(): fz_clone_context/fz_drop_context both
        // adjust the base context's shared, reference-counted store/font cache. With
        // multiple tabs/windows open on the same document (or even different documents,
        // since all of them clone from this one process-wide rootContext), a clone on
        // one tab and a drop on another (e.g. closing a tab) can race here without this
        // lock — cloning was already protected, dropping wasn't.
        lock.lock()
        defer { lock.unlock() }
        mupdf_context_drop(ctx)
    }
}
