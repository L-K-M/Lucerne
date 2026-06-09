import AppKit

// The Lucerne artwork for in-app chrome (the About and Welcome windows). Loaded
// from the bundled `icon.png` resource so it's the real icon in every run context —
// including `swift run` (unbundled), where `NSApp.applicationIconImage` is just the
// generic placeholder. Falls back to the application icon if the resource is
// somehow missing.
enum AppIcon {
    static let image: NSImage = {
        if let url = Bundle.module.url(forResource: "icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage ?? NSImage()
    }()
}
