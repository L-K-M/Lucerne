import AppKit
import LucerneKit

// Entry point. Creating our NSDocumentController first makes it the shared
// instance, so Lucerne knows its single .luce document type even when launched
// unbundled via `swift run` (no Info.plist). The .app bundle path uses the same
// class plus Info.plist registration for Finder integration.
_ = LucerneDocumentController()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
