//
//  FilterType.swift
//  Ferrey
//
//  Created by Junaid on 16/08/2025.
//

import SwiftUI
import Foundation
import UIKit
import CoreImage

#if canImport(Kingfisher)
import Kingfisher
#endif


// MARK: - Filter Type Definition

enum FilterType: String, CaseIterable, Equatable, Hashable {
    case normal, t32Update, t34, apeninos, asf, bandw, f7x, luxury, terra

    var title: String {
        switch self {
            case .normal: return "Normal"
            case .t32Update: return "T32"
            case .t34: return "T34"
            case .apeninos: return "Apeninos"
            case .asf: return "ASF"
            case .bandw: return "B&W"
            case .f7x: return "F7x"
            case .luxury: return "Luxury"
            case .terra: return "Terra"
        }
    }

    private var iconAssetName: String {
        switch self {
            case .t32Update, .t34: return "icon t32"
            default: return title
        }
    }
    var icon: Image { Image(iconAssetName) }

    var isPro: Bool {
        switch self {
            case .normal, .t32Update, .t34, .apeninos, .asf:
                return false
            case .bandw, .f7x, .luxury, .terra:
                return true
        }
    }

    var samples: [String] {
        switch self {
            case .normal: return ["normal_1"]
            case .t32Update, .t34: return ["apeninos_1", "apeninos_2"]
            case .apeninos: return ["apeninos_1", "apeninos_2"]
            case .asf: return ["asf_1", "asf_2"]
            case .bandw: return ["bandw_1", "bandw_2"]
            case .f7x: return ["f7x_1", "f7x_2"]
            case .luxury: return ["luxury_1", "luxury_2"]
            case .terra: return ["terra_1", "terra_2"]
        }
    }
    
    static var allSamples: [String] { FilterType.allCases.flatMap { $0.samples } }
    static var visibleFilterCases: [FilterType] { FilterType.allCases.filter { $0 != .t32Update } }
}

extension FilterType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "t33" {
            self = .t34
        } else if let value = FilterType(rawValue: raw) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid FilterType: \(raw)")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Centralized Filter Utilities

struct FilterUtils {
    static let context = CIContext(options: nil)
    
    private static let t32CacheLock = NSLock()
    private static var t32CubeCache: (dimension: Int, data: Data)?
    
    static func applyAdjustedFilter(
        to image: UIImage,
        with type: FilterType,
        filterIntensity: Double,
        textureIntensity: Double,
        exposureIntensity: Double,
        logT32Timing: Bool = true
    ) -> UIImage? {
        guard let ciImage = CIImage(image: image.fixedOrientation()) else { return nil }
        var processed = ciImage
        
        if type != .normal && filterIntensity > 0 {
            guard let lutFilter = createColorCubeFilter(for: type) else { return nil }
            lutFilter.setValue(processed, forKey: kCIInputImageKey)
            guard let lutOutput = lutFilter.outputImage else { return nil }
            let transitionFilter = CIFilter(name: "CIDissolveTransition")!
            transitionFilter.setValue(processed, forKey: kCIInputImageKey)
            transitionFilter.setValue(lutOutput, forKey: kCIInputTargetImageKey)
            transitionFilter.setValue(filterIntensity, forKey: kCIInputTimeKey)
            processed = transitionFilter.outputImage ?? processed
        }
        
        let exposureFilter = CIFilter(name: "CIExposureAdjust")!
        exposureFilter.setValue(processed, forKey: kCIInputImageKey)
        let exposureValue = (exposureIntensity - 0.5) * 10.0
        exposureFilter.setValue(exposureValue, forKey: kCIInputEVKey)
        processed = exposureFilter.outputImage ?? processed

        if (type == .t34 || type == .apeninos || type == .asf) && DustAndDateEffectUtils.isDustEnabled() {
            if let withDust = T34Filter.applyDustOverlay(photo: processed, extent: processed.extent) {
                processed = withDust
            }
        }

        guard let cgImage = context.createCGImage(processed, from: processed.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    static func createColorCubeFilter(for type: FilterType) -> CIFilter? {
        if type == .t32Update || type == .t34 {
            let cached: (dimension: Int, data: Data)? = {
                t32CacheLock.lock()
                defer { t32CacheLock.unlock() }
                return t32CubeCache
            }()
            if let c = cached {
                guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
                filter.setValue(c.dimension, forKey: "inputCubeDimension")
                filter.setValue(c.data, forKey: "inputCubeData")
                filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
                return filter
            }
            guard let name = lutFileName(for: type),
                  let url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: "LUTs"),
                  let parsed = parseCubeFile(at: url) else {
                return nil
            }
            t32CacheLock.lock()
            t32CubeCache = parsed
            t32CacheLock.unlock()
            guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
            filter.setValue(parsed.dimension, forKey: "inputCubeDimension")
            filter.setValue(parsed.data, forKey: "inputCubeData")
            filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
            return filter
        }
        guard let name = lutFileName(for: type),
              let url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: "LUTs"),
              let (dimension, cubeData) = parseCubeFile(at: url) else {
            return nil
        }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
        return filter
    }

    static func createColorCubeFilter(named name: String) -> CIFilter? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: "LUTs"),
              let (dimension, cubeData) = parseCubeFile(at: url) else {
            return nil
        }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
        return filter
    }
    
    private static func lutFileName(for type: FilterType) -> String? {
        switch type {
            case .normal: return nil
            case .t32Update, .t34: return "T32 update"
            default: return type.title
        }
    }
    
    private static func parseCubeFile(at url: URL) -> (dimension: Int, data: Data)? {
        guard let content = try? String(contentsOf: url) else { return nil }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        var dimension: Int?
        var values: [Float] = []
        for line in lines {
            if line.hasPrefix("LUT_3D_SIZE") {
                if let size = line.components(separatedBy: .whitespaces).last, let d = Int(size) {
                    dimension = d
                }
            } else if let rgb = parseRGB(line) {
                values.append(contentsOf: rgb)
                values.append(1.0)
            }
        }
        guard let dim = dimension, values.count == dim * dim * dim * 4 else { return nil }
        return (dim, values.withUnsafeBytes { Data($0) })
    }
    
    private static func parseRGB(_ line: String) -> [Float]? {
        let parts = line.components(separatedBy: .whitespaces).compactMap { Float($0) }
        return parts.count == 3 ? parts : nil
    }
}

// MARK: - UIImage Orientation Helper

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? self
    }
}

// MARK: - Data Structures and Manager

struct PhotoMetadata: Codable, Identifiable, Equatable {
    let id: String
    var filter: FilterType
    var filterIntensity: Double = 1.0
    var textureIntensity: Double = 1.0
    var exposureIntensity: Double = 0.5
    var lastUpdated: Date = Date()
}

class PhotoManager: ObservableObject {
    static let shared = PhotoManager()
    static let jpegCompressionQuality: CGFloat = 0.95
    
    var lastCapturedExposure: Double = 0.5
    
    @Published var photos: [PhotoMetadata] = []
    
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled: Bool = true
    
    private let photosKey = "savedPhotos"

    private func bakeDateIfNeeded(_ image: UIImage, filter: FilterType, photoId: String) -> UIImage {
        guard filter == .t34, DustAndDateEffectUtils.isDateEnabled(),
              let withDate = FilmDateOverlay.apply(to: image) else { return image }
        return withDate
    }
    
    private init() {
        load()
        migrateAndCleanFilteredFiles()
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let decoded = try? JSONDecoder().decode([PhotoMetadata].self, from: data) {
            photos = decoded
            removeOrphanedPhotos()
        }
    }

    private func removeOrphanedPhotos() {
        let fm = FileManager.default
        let before = photos.count
        photos.removeAll { photo in
            let origExists = fm.fileExists(atPath: originalURL(for: photo.id).path)
            let filtExists = fm.fileExists(atPath: filteredURL(for: photo.id, filter: photo.filter).path)
            return !origExists && !filtExists
        }
        if photos.count != before {
            save()
        }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(photos) {
            UserDefaults.standard.set(data, forKey: photosKey)
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func originalURL(for id: String) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id)_original.jpg")
    }

    func filteredURL(for id: String, filter: FilterType) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id)_filtered.jpg")
    }

    func addPhoto(original: UIImage, filter: FilterType, shouldAutoSave: Bool = true, completion: (() -> Void)? = nil) {
        let id = UUID().uuidString
        let applyFullEffects = (filter != .normal)
        let textureValue = applyFullEffects ? 1.0 : 0.0
        let exposureValue = self.lastCapturedExposure
        let origURL = originalURL(for: id)
        let filtURL = filteredURL(for: id, filter: filter)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion?(); return }
            var filteredImage = FilterUtils.applyAdjustedFilter(
                to: original,
                with: filter,
                filterIntensity: 1.0,
                textureIntensity: textureValue,
                exposureIntensity: exposureValue
            ) ?? original
            if let withEffects = DustAndDateEffectUtils.applyEffects(to: filteredImage, for: filter) {
                filteredImage = withEffects
            }
            if self.autoSaveEnabled && shouldAutoSave {
                let toSave = self.bakeDateIfNeeded(filteredImage, filter: filter, photoId: id)
                UIImageWriteToSavedPhotosAlbum(toSave, nil, nil, nil)
            }
            if let data = original.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                try? data.write(to: origURL)
            }
            if let data = filteredImage.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                try? data.write(to: filtURL)
            }
            let metadata = PhotoMetadata(
                id: id,
                filter: filter,
                filterIntensity: 1.0,
                textureIntensity: textureValue,
                exposureIntensity: exposureValue
            )
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.photos.insert(metadata, at: 0)
                }
                self.save()
                completion?()
            }
        }
    }

    func updateFilter(for id: String, newFilter: FilterType) -> UIImage? {
        var result: UIImage?
        let semaphore = DispatchSemaphore(value: 0)
        updateFilter(for: id, newFilter: newFilter) { result = $0; semaphore.signal() }
        semaphore.wait()
        return result
    }

    func updateFilter(for id: String, newFilter: FilterType, completion: @escaping (UIImage?) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { completion(nil); return }
        let photo = photos[index]
        if photo.filter == newFilter { completion(nil); return }
        
        let intensity = photo.filterIntensity
        let texture = photo.textureIntensity
        let exposure = photo.exposureIntensity
        let origURL = originalURL(for: id)
        let filtURL = filteredURL(for: id, filter: newFilter)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion(nil); return }
            self.removeAllFilteredVariants(for: id)
            guard let original = UIImage(contentsOfFile: origURL.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var filtered = FilterUtils.applyAdjustedFilter(
                to: original,
                with: newFilter,
                filterIntensity: intensity,
                textureIntensity: texture,
                exposureIntensity: exposure
            ) ?? original
            if let withEffects = DustAndDateEffectUtils.applyEffects(to: filtered, for: newFilter) {
                filtered = withEffects
            }
            if let data = filtered.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                try? data.write(to: filtURL)
            }
            DispatchQueue.main.async {
                self.photos[index].filter = newFilter
                self.photos[index].lastUpdated = Date()
                self.save()
                completion(filtered)
            }
        }
    }

    func updateIntensities(for id: String, filterIntensity: Double, textureIntensity: Double, exposureIntensity: Double, completion: @escaping (UIImage?) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { completion(nil); return }
        var photo = photos[index]
        photo.filterIntensity = filterIntensity
        photo.textureIntensity = textureIntensity
        photo.exposureIntensity = exposureIntensity
        photo.lastUpdated = Date()
        let filter = photo.filter
        let origURL = originalURL(for: id)
        let filtURL = filteredURL(for: id, filter: filter)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion(nil); return }
            guard let original = UIImage(contentsOfFile: origURL.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var filtered = FilterUtils.applyAdjustedFilter(
                to: original,
                with: filter,
                filterIntensity: filterIntensity,
                textureIntensity: textureIntensity,
                exposureIntensity: exposureIntensity
            ) ?? original
            if let withEffects = DustAndDateEffectUtils.applyEffects(to: filtered, for: filter) {
                filtered = withEffects
            }
            self.removeAllFilteredVariants(for: id)
            if let data = filtered.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                try? data.write(to: filtURL)
            }
            DispatchQueue.main.async {
                self.photos[index].filterIntensity = filterIntensity
                self.photos[index].textureIntensity = textureIntensity
                self.photos[index].exposureIntensity = exposureIntensity
                self.photos[index].lastUpdated = Date()
                self.save()
                completion(filtered)
            }
        }
    }
    
    func latestFilteredURL() -> URL? {
        guard let first = photos.first else { return nil }
        return filteredURL(for: first.id, filter: first.filter)
    }
    
    private func removeAllFilteredVariants(for id: String) {
        let fm = FileManager.default
        let docs = getDocumentsDirectory()
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.hasPrefix("\(id)_filtered_") || name == "\(id)_filtered.jpg" {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }
    
    private func migrateAndCleanFilteredFiles() {
        removeAllFilteredVariantsLegacy()
    }
    
    private func removeAllFilteredVariantsLegacy() {
        let fm = FileManager.default
        let docs = getDocumentsDirectory()
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.contains("_filtered_") {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    func clearImageCaches() {
#if canImport(Kingfisher)
        let cache = KingfisherManager.shared.cache
        cache.clearMemoryCache()
        cache.clearDiskCache()
        cache.cleanExpiredDiskCache()
#endif
        URLCache.shared.removeAllCachedResponses()
    }
    
    func deletePhotos(ids: [String]) {
        let fm = FileManager.default
        for id in ids {
            try? fm.removeItem(at: originalURL(for: id))
            removeAllFilteredVariants(for: id)
        }
        photos.removeAll { ids.contains($0.id) }
        save()
        clearImageCaches()
    }
    
    func deleteAllPhotos() {
        let fm = FileManager.default
        let docs = getDocumentsDirectory()
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.hasSuffix("_original.jpg") || name.contains("_filtered_") || name.hasSuffix("_filtered.jpg") {
                    try? fm.removeItem(at: url)
                }
            }
        }
        photos.removeAll()
        UserDefaults.standard.removeObject(forKey: photosKey)
        clearImageCaches()
    }
}
