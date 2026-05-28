import AppKit
import Foundation
import Observation

enum ArtworkStyle: String {
    case libraryGrid = "library_600x900"
    case header      = "header"
    case hero        = "library_hero"
}

@Observable
final class ArtworkService {
    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheDir: URL

    init() {
        diskCacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appending(path: "MacGameLauncher/Artwork")
        try? FileManager.default.createDirectory(
            at: diskCacheDir,
            withIntermediateDirectories: true
        )
        memoryCache.countLimit = 200
    }

    func artwork(for steamAppID: Int, style: ArtworkStyle = .libraryGrid) async -> NSImage? {
        let key = "\(steamAppID)-\(style.rawValue)" as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Disk cache
        let diskPath = diskCacheDir.appending(path: "\(key).jpg")
        if let data = try? Data(contentsOf: diskPath), let img = NSImage(data: data) {
            memoryCache.setObject(img, forKey: key)
            return img
        }

        // 3. Network
        let urlString = "https://cdn.akamai.steamstatic.com/steam/apps/\(steamAppID)/\(style.rawValue).jpg"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { return nil }

            try? data.write(to: diskPath)
            memoryCache.setObject(img, forKey: key)
            return img
        } catch {
            return nil
        }
    }

    func clearCache(for steamAppID: Int) {
        for style in [ArtworkStyle.libraryGrid, .header, .hero] {
            let key = "\(steamAppID)-\(style.rawValue)" as NSString
            memoryCache.removeObject(forKey: key)
            let diskPath = diskCacheDir.appending(path: "\(key).jpg")
            try? FileManager.default.removeItem(at: diskPath)
        }
    }

    func clearAllCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }
}
