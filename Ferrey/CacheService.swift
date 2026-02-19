//
//  CacheService.swift
//  Ferrey
//
//  Created by Junaid on 12/09/2025.
//


//  CacheService.swift
//  Ferrey

import Foundation
import UIKit

#if canImport(Kingfisher)
import Kingfisher
#endif

final class CacheService {
    static let shared = CacheService()
    private init() {}

    /// Hard clear everything that is safe to delete at runtime.
    func clearAllCaches() {
        // App-level URL cache
        URLCache.shared.removeAllCachedResponses()

        // Kingfisher cache (if present)
        #if canImport(Kingfisher)
        let cache = KingfisherManager.shared.cache
        cache.clearMemoryCache()
        cache.clearDiskCache()
        cache.cleanExpiredDiskCache()
        #endif

        // Temporary directory clean (e.g., CoreImage / exporter temps)
        clearTemporaryDirectory()
    }

    /// Gentle trim without nuking everything (call more frequently).
    func trimCaches() {
        // Trim URLCache (drop older responses)
        URLCache.shared.removeAllCachedResponses()

        #if canImport(Kingfisher)
        KingfisherManager.shared.cache.cleanExpiredDiskCache()
        #endif

        clearTemporaryDirectory()
    }

    /// Cap caches so they don’t balloon.
    func configureCacheLimits(
        urlCacheMemoryMB: Int = 8,
        urlCacheDiskMB: Int = 32,
        kingfisherDiskLimitMB: Int = 64
    ) {
        // URLCache caps
        let mem = urlCacheMemoryMB * 1024 * 1024
        let disk = urlCacheDiskMB * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "com.ferrey.urlcache")

        #if canImport(Kingfisher)
        // Kingfisher caps
        var diskConfig = KingfisherManager.shared.cache.diskStorage.config
        diskConfig.sizeLimit = UInt(kingfisherDiskLimitMB * 1024 * 1024)
        KingfisherManager.shared.cache.diskStorage.config = diskConfig
        #endif
    }

    // MARK: - Helpers

    private func clearTemporaryDirectory() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in files { try? FileManager.default.removeItem(at: url) }
        }
    }
}
