import AppKit

public extension NSImage {
    /// PNG encoding of the image's best bitmap representation, used when an image
    /// arrives without original file bytes (e.g. pasted) and must still be stored
    /// losslessly in the .luce package.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
