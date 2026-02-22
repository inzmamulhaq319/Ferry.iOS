//
//  FilterType.swift
//  Ferrey
//
//  Created by Junaid on 16/08/2025.
//

// Note: Consolidated all filter, LUT, and image processing logic into this file.

import SwiftUI
import Foundation
import UIKit
import CoreImage

#if canImport(Kingfisher)
import Kingfisher
#endif

// MARK: - How to Add a New Filter
/*
 Adding a new filter involves three simple steps:
 
 // MARK: 1) Add the filter case
 - Add a new case separated by comma to the FilterType enum, e.g.:
 case normal, apeninos, vintage
 
 // MARK: 2) Provide a title and assets
 - In `var title`, add a user-friendly display name:
 case .vintage: return "Vintage"
 - Provide an icon asset in your Assets folder named exactly "Vintage".
 - Add sample thumbnail names in `var samples` if you show previews:
 case .vintage: return ["vintage_1", "vintage_2"]
 Note: Sample thumbnail should be highly compressed. 1MB per image maxiumum. you can use whatsapp. Share image on whatsapp and download for thumbnail
 
 // MARK: 3) Mark the filter as Pro or Free (isPro)
 - In `var isPro`, decide whether this filter should be free or behind a paywall:
 case .vintage: return true   // Pro-only filter
 case .normal: return false   // Free filter
 - Setting `true` will show a lock icon (and require purchase) in the UI.
 - Setting `false` makes the filter available to all users.
 
 Done! Your new filter will automatically appear in the filter list, with its icon,
 title, and processing logic.
 
 Note: Double-check that the LUT file name, icon asset name, and case name all match
 to avoid missing assets at runtime.
 
 // MARK: 4) Provide a LUT file (for color transformations)
 - Place your .cube LUT file into the `LUTs` folder inside your app bundle.
 - The LUT file name (without extension) must match `title`, e.g. "Vintage.cube".
 - If the filter doesn’t use a LUT, you can implement a custom CIFilter chain
 inside `FilterUtils.applyAdjustedFilter` with a conditional for `.vintage`.
 */


// MARK: - Filter Type Definition

enum FilterType: String, CaseIterable, Codable, Equatable, Hashable {
    
    // MARK: - Filter ENUM
    
    case normal, t32, t32preset, apeninos, asf, bandw, f7x, luxury, terra
    
    // MARK: - Filter NAME
    
    var title: String {
        switch self {
            case .normal: return "Normal"
            case .t32: return "T32"
            case .t32preset: return "T32Preset"
            case .apeninos: return "Apeninos"
            case .asf: return "ASF"
            case .bandw: return "B&W"
            case .f7x: return "F7x"
            case .luxury: return "Luxury"
            case .terra: return "Terra"
        }
    }
    
    var icon: Image { Image(self.title) } // Don't change
    
    // MARK: - Filter Free/Pro
    
    var isPro: Bool {
        switch self {
            case .normal, .t32, .t32preset, .apeninos, .asf:
                return false
            case .bandw, .f7x, .luxury, .terra:
                return true
        }
    }
    
    // MARK: - Filter Samples
    
    var samples: [String] {
        switch self {
            case .normal: return ["normal_1"]
            case .t32: return ["apeninos_1", "apeninos_2"]
            case .t32preset: return ["apeninos_1", "apeninos_2"]
            case .apeninos: return ["apeninos_1", "apeninos_2"]
            case .asf: return ["asf_1", "asf_2"]
            case .bandw: return ["bandw_1", "bandw_2"]
            case .f7x: return ["f7x_1", "f7x_2"]
            case .luxury: return ["luxury_1", "luxury_2"]
            case .terra: return ["terra_1", "terra_2"]
        }
    }
    
    static var allSamples: [String] { FilterType.allCases.flatMap { $0.samples } }
}

// MARK: - Centralized Filter Utilities

struct FilterUtils {
    static let context = CIContext(options: nil)
    
    // MODIFIED: Simplified the function to use a single `exposureIntensity` parameter.
    static func applyAdjustedFilter(
        to image: UIImage,
        with type: FilterType,
        filterIntensity: Double,
        textureIntensity: Double,
        exposureIntensity: Double
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
        
        if textureIntensity > 0 {
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
                .applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 0,
                    "inputContrast": textureIntensity * 0.70
                ])
                .cropped(to: processed.extent)
            let blend = CIFilter(name: "CIOverlayBlendMode")!
            blend.setValue(noise, forKey: kCIInputImageKey)
            blend.setValue(processed, forKey: kCIInputBackgroundImageKey)
            processed = blend.outputImage ?? processed
        }
        
        let exposureFilter = CIFilter(name: "CIExposureAdjust")!
        exposureFilter.setValue(processed, forKey: kCIInputImageKey)
        // Map the 0.0-1.0 intensity to a -1.0 to 1.0 exposure value.
        let exposureValue = (exposureIntensity - 0.5) * 10.0
        exposureFilter.setValue(exposureValue, forKey: kCIInputEVKey)
        processed = exposureFilter.outputImage ?? processed
        
        guard let cgImage = context.createCGImage(processed, from: processed.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    static func createColorCubeFilter(for type: FilterType) -> CIFilter? {
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
    
    /// Load a LUT by file name (without .cube) from LUTs folder. Used e.g. for T32 in dust effect.
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
            case .t32: return "T32"
            case .t32preset: return "T32 (+ color preset)"
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
    
    var lastCapturedExposure: Double = 0.5
    
    @Published var photos: [PhotoMetadata] = []
    
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled: Bool = true
    
    private let photosKey = "savedPhotos"
    
    private init() {
        load()
        migrateAndCleanFilteredFiles() // <- removes old _filtered_ variants
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let decoded = try? JSONDecoder().decode([PhotoMetadata].self, from: data) {
            photos = decoded
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
    
    // IMPORTANT: single filtered filename to avoid storage bloat
    func filteredURL(for id: String, filter: FilterType) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id)_filtered.jpg")
    }
    
    func addPhoto(original: UIImage, filter: FilterType, shouldAutoSave: Bool = true) {
        let id = UUID().uuidString
        let applyFullEffects = (filter != .normal)
        let textureValue = applyFullEffects ? 1.0 : 0.0
        let exposureValue = self.lastCapturedExposure
        
        // MODIFIED: Call the updated filter function with the direct exposure value.
        var filteredImage = FilterUtils.applyAdjustedFilter(
            to: original,
            with: filter,
            filterIntensity: 1.0,
            textureIntensity: textureValue,
            exposureIntensity: exposureValue
        ) ?? original
        if let withEffects = DustAndDateEffectUtils.applyEffects(to: filteredImage) {
            filteredImage = withEffects
        }
        
        if autoSaveEnabled && shouldAutoSave {
            UIImageWriteToSavedPhotosAlbum(filteredImage, nil, nil, nil)
        }
        
        if let data = original.jpegData(compressionQuality: 0.70) {
            try? data.write(to: originalURL(for: id))
        }
        
        // Always write ONE filtered copy
        if let data = filteredImage.jpegData(compressionQuality: 0.70) {
            try? data.write(to: filteredURL(for: id, filter: filter))
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
        }
    }
    
    func updateFilter(for id: String, newFilter: FilterType) -> UIImage? {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
        let photo = photos[index]
        if photo.filter == newFilter { return nil }
        
        // Remove ANY existing filtered files for this id (legacy patterns + current)
        removeAllFilteredVariants(for: id)
        
        guard let original = UIImage(contentsOfFile: originalURL(for: id).path) else { return nil }
        
        // MODIFIED: Call the updated filter function.
        var filtered = FilterUtils.applyAdjustedFilter(
            to: original,
            with: newFilter,
            filterIntensity: photo.filterIntensity,
            textureIntensity: photo.textureIntensity,
            exposureIntensity: photo.exposureIntensity
        ) ?? original
        if let withEffects = DustAndDateEffectUtils.applyEffects(to: filtered) {
            filtered = withEffects
        }
        
        if let data = filtered.jpegData(compressionQuality: 0.75) {
            try? data.write(to: filteredURL(for: id, filter: newFilter))
        }
        
        photos[index].filter = newFilter
        photos[index].lastUpdated = Date()
        save()
        return filtered
    }
    
    // MODIFIED: Renamed `exposureAdjustment` to `exposureIntensity` to reflect its new purpose.
    func updateIntensities(for id: String, filterIntensity: Double, textureIntensity: Double, exposureIntensity: Double) -> UIImage? {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
        var photo = photos[index]
        photo.filterIntensity = filterIntensity
        photo.textureIntensity = textureIntensity
        // MODIFIED: Update the stored exposure intensity directly.
        photo.exposureIntensity = exposureIntensity
        photo.lastUpdated = Date()
        photos[index] = photo
        
        guard let original = UIImage(contentsOfFile: originalURL(for: id).path) else { return nil }
        
        // MODIFIED: Call the updated filter function with the new absolute intensity.
        var filtered = FilterUtils.applyAdjustedFilter(
            to: original,
            with: photo.filter,
            filterIntensity: filterIntensity,
            textureIntensity: textureIntensity,
            exposureIntensity: exposureIntensity
        ) ?? original
        if let withEffects = DustAndDateEffectUtils.applyEffects(to: filtered) {
            filtered = withEffects
        }
        
        // Overwrite single filtered file
        removeAllFilteredVariants(for: id)
        if let data = filtered.jpegData(compressionQuality: 0.75) {
            try? data.write(to: filteredURL(for: id, filter: photo.filter))
        }
        
        save()
        return filtered
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
        // One-time cleanup: delete old multi-variant filtered files
        removeAllFilteredVariantsLegacy()
    }
    
    private func removeAllFilteredVariantsLegacy() {
        let fm = FileManager.default
        let docs = getDocumentsDirectory()
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.contains("_filtered_") { // legacy pattern
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
