import AppKit

// A small, tidy About window: the app icon, name, tagline, version, and a one-line
// note about the format. Nicer than the stock panel and shows the real icon.
final class AboutWindowController: NSWindowController {

    /// Version shown when the bundle's Info.plist can't be read — chiefly an unbundled
    /// `swift run`. The bundled app prefers `CFBundleShortVersionString` (stamped from
    /// the release tag); this constant is kept in step by `Scripts/release.sh`.
    static let fallbackVersion = "0.1.1"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About Lucerne"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        self.init(window: window)
        buildContent()
        window.center()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? Self.fallbackVersion
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let icon = NSImageView()
        icon.image = AppIcon.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 128).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 128).isActive = true

        let title = label("Lucerne", font: .systemFont(ofSize: 30, weight: .bold), color: .labelColor)
        let tagline = label("A ClarisWorks-style word editor for the Mac",
                            font: .systemFont(ofSize: 13), color: .secondaryLabelColor, wraps: true)
        let versionLabel = label("Version \(version) (\(build))",
                                 font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        let note = label("Letters with rulers, tabs, and genuine free placement of images.\n"
                         + "Documents are saved as “.luce” — a ZIP package you can always open.",
                         font: .systemFont(ofSize: 11), color: .secondaryLabelColor, wraps: true)

        let stack = NSStackView(views: [icon, title, tagline, versionLabel, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(16, after: versionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
    }

    private func label(_ text: String, font: NSFont, color: NSColor, wraps: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        if wraps {
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.preferredMaxLayoutWidth = 320
        }
        return field
    }
}
