import Foundation
import CryptoKit

/// Downloads a release asset into the user's Downloads folder, picking a
/// non-colliding filename, and verifies what arrived: the download URL must be
/// HTTPS on a GitHub host, the size must match the API's `size`, and when the API
/// supplied a `sha256:` digest the file's SHA-256 must match it (chonk finding 10).
struct UpdateDownloader {

    enum DownloadError: LocalizedError {
        case untrustedHost(String)
        case sizeMismatch(expected: Int, actual: Int)
        case digestMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .untrustedHost(let host):
                return "Refusing to download from \"\(host)\" — only GitHub hosts are allowed."
            case let .sizeMismatch(expected, actual):
                return "Downloaded file is \(actual) bytes, expected \(expected). The download was incomplete or tampered with."
            case let .digestMismatch(expected, actual):
                return "SHA-256 mismatch: expected \(expected), got \(actual). The download was tampered with."
            }
        }
    }

    /// Hosts a release asset may be fetched from (the API response itself comes
    /// from api.github.com over HTTPS; the asset URL must stay on GitHub).
    static let allowedHosts: Set<String> = [
        "github.com", "api.github.com", "codeload.github.com", "objects.githubusercontent.com"
    ]
    /// A session with a resource timeout, so a stalled download eventually fails
    /// (and the caller's release-page fallback kicks in) instead of hanging forever.
    var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30          // per chunk of progress
        configuration.timeoutIntervalForResource = 15 * 60    // whole-file ceiling
        return URLSession(configuration: configuration)
    }()
    var fileManager: FileManager = .default

    /// Downloads `asset` to `~/Downloads`, returning the saved file URL. The
    /// download is verified before it is moved into place: HTTPS GitHub host,
    /// exact size, and SHA-256 when the API provided a digest.
    func downloadToDownloads(_ asset: GitHubRelease.Asset) async throws -> URL {
        let url = asset.browserDownloadURL
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              Self.allowedHosts.contains(host) else {
            throw DownloadError.untrustedHost(url.host ?? url.absoluteString)
        }
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubReleaseClient.ClientError.badResponse(http.statusCode)
        }
        try Self.verify(tempURL, asset: asset, fileManager: fileManager)
        let downloads = try fileManager.url(for: .downloadsDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)
        let destination = Self.uniqueDestination(in: downloads, fileName: asset.name, fileManager: fileManager)
        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Verifies a downloaded temp file against the API's asset metadata. Size is
    /// always checked; the SHA-256 digest is checked whenever the API supplied one.
    static func verify(_ fileURL: URL, asset: GitHubRelease.Asset,
                       fileManager: FileManager = .default) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let actualSize = (attributes[.size] as? Int) ?? 0
        if asset.size > 0, actualSize != asset.size {
            throw DownloadError.sizeMismatch(expected: asset.size, actual: actualSize)
        }
        guard let digest = asset.digest, digest.lowercased().hasPrefix("sha256:") else { return }
        let expected = String(digest.dropFirst("sha256:".count)).lowercased()
        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if actual != expected {
            throw DownloadError.digestMismatch(expected: expected, actual: actual)
        }
    }

    /// A non-colliding URL in `directory` for `fileName` (`Foo.dmg`, then `Foo-1.dmg`,
    /// `Foo-2.dmg`, …) so re-downloading never clobbers an existing file.
    static func uniqueDestination(in directory: URL, fileName: String,
                                  fileManager: FileManager = .default) -> URL {
        let name = fileName.isEmpty ? "download" : fileName
        let first = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: first.path) else { return first }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
