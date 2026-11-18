import Foundation

/// The marketing version this build reports to the update checker.
///
/// `CFBundleShortVersionString` normally comes from `Scripts/Info.plist`; an
/// unbundled `swift run` has no readable bundle, so it falls back to the same
/// constant the About window shows (`AboutWindowController.fallbackVersion`,
/// kept in step by `Scripts/release.sh`) instead of Updraft's `"0"` — which
/// would make every real release look like an update to an unbundled build.
/// An empty value counts as missing too, so `""` never reaches the checker.
enum AppVersion {
    static var shortVersionString: String {
        let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return (bundled?.isEmpty == false ? bundled : nil)
            ?? AboutWindowController.fallbackVersion
    }
}
