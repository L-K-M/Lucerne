import Foundation
import CryptoKit

/// Downloads a release asset into the user's Downloads folder, picking a
/// non-colliding filename, and verifies what arrived: every URL the download
/// passes through — the initial URL, each redirect hop, and the URL the response
/// came from — must be HTTPS on a GitHub host, the size must match the API's
/// `size`, and when the API supplied a `sha256:` digest the file's SHA-256 must
/// match it (chonk finding 10).
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
    /// `browser_download_url` answers a 302 to release-assets.githubusercontent.com;
    /// objects.githubusercontent.com is that CDN's older name.
    static let allowedHosts: Set<String> = [
        "github.com", "api.github.com", "codeload.github.com",
        "objects.githubusercontent.com", "release-assets.githubusercontent.com"
    ]
    /// A session with a resource timeout, so a stalled download eventually fails
    /// (and the caller's release-page fallback kicks in) instead of hanging forever.
    var session: URLSession
    /// Remembers the redirect target the session vetoed, so the refusal can be
    /// reported by host name: a refused hop ends the task with the bare 3xx
    /// response, which on its own would surface as an unhelpful HTTP error.
    private let redirectGate = RedirectGate()
    var fileManager: FileManager = .default

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30          // per chunk of progress
        configuration.timeoutIntervalForResource = 15 * 60    // whole-file ceiling
        session = URLSession(configuration: configuration, delegate: redirectGate, delegateQueue: nil)
    }

    /// Whether `url` may serve a release asset: HTTPS on an allowlisted host.
    /// Applied to the API's `browser_download_url`, to every redirect hop the
    /// session reports, and to the URL the response actually came from.
    static func isAllowedAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host.map { allowedHosts.contains($0.lowercased()) } == true
    }

    /// Downloads `asset` to `~/Downloads`, returning the saved file URL. The
    /// download is verified before it is moved into place: HTTPS GitHub host on
    /// every redirect hop, exact size, and SHA-256 when the API provided a digest.
    func downloadToDownloads(_ asset: GitHubRelease.Asset) async throws -> URL {
        let url = asset.browserDownloadURL
        guard Self.isAllowedAssetURL(url) else {
            throw DownloadError.untrustedHost(url.host ?? url.absoluteString)
        }
        // The downloader is reused across checks; clear any earlier refusal first.
        redirectGate.reset()
        let (tempURL, response) = try await session.download(from: url)
        // A vetoed redirect completes the task with the redirect's 3xx response —
        // report the refused host instead of a bare HTTP status.
        if let refused = redirectGate.refused {
            throw DownloadError.untrustedHost(refused.host ?? refused.absoluteString)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubReleaseClient.ClientError.badResponse(http.statusCode)
        }
        // The delegate vetted each hop; still check the URL the bytes actually
        // came from before accepting the file.
        if let finalURL = response.url, !Self.isAllowedAssetURL(finalURL) {
            throw DownloadError.untrustedHost(finalURL.host ?? finalURL.absoluteString)
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
        let actual = try Self.sha256Hex(ofFileAt: fileURL)
        if actual != expected {
            throw DownloadError.digestMismatch(expected: expected, actual: actual)
        }
    }

    /// Streams `fileURL` through SHA-256 in 1 MiB chunks and returns the lowercase
    /// hex digest, so hashing a large disk image never holds it all in memory.
    static func sha256Hex(ofFileAt fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

    /// Session delegate that applies the asset host policy to every redirect hop,
    /// not just the initial URL — without it, a `browser_download_url` that 302s
    /// to an attacker-chosen host would be followed unchecked.
    private final class RedirectGate: NSObject, URLSessionTaskDelegate {
        private let lock = NSLock()
        private var refusedTarget: URL?

        /// The redirect target the gate refused, if any (read after the task ends).
        var refused: URL? {
            lock.lock()
            defer { lock.unlock() }
            return refusedTarget
        }

        func reset() {
            lock.lock()
            refusedTarget = nil
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let target = request.url, UpdateDownloader.isAllowedAssetURL(target) else {
                lock.lock()
                refusedTarget = request.url
                lock.unlock()
                completionHandler(nil)  // refuse: the task ends with the 3xx response
                return
            }
            completionHandler(request)
        }
    }
}
