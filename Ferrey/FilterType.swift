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
    
    case normal, t32Update, t33, t34, apeninos, asf, bandw, f7x, luxury, terra
    
    // MARK: - Filter NAME
    
    var title: String {
        switch self {
            case .normal: return "Normal"
            case .t32Update: return "T32"
            case .t33: return "T33"
            case .t34: return "T34"
            case .apeninos: return "Apeninos"
            case .asf: return "ASF"
            case .bandw: return "B&W"
            case .f7x: return "F7x"
            case .luxury: return "Luxury"
            case .terra: return "Terra"
        }
    }
    
    /// Asset name for filter icon (in Assets). Defaults to title; override per filter if needed.
    private var iconAssetName: String {
        switch self {
            case .t32Update, .t33, .t34: return "icon t32"
            default: return title
        }
    }
    var icon: Image { Image(iconAssetName) }
    
    // MARK: - Filter Free/Pro
    
    var isPro: Bool {
        switch self {
            case .normal, .t32Update, .t33, .t34, .apeninos, .asf:
                return false
            case .bandw, .f7x, .luxury, .terra:
                return true
        }
    }
    
    // MARK: - Filter Samples
    
    var samples: [String] {
        switch self {
            case .normal: return ["normal_1"]
            case .t32Update, .t33, .t34: return ["apeninos_1", "apeninos_2"]
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

// MARK: - T32 timing (remove or gate with #if DEBUG when done)
private func t32Log(_ label: String, seconds: Double) {
    print(String(format: "[T32] %@: %.2f s", label, seconds))
}

struct FilterUtils {
    static let context = CIContext(options: nil)
    
    // T32 LUT cache: keep loaded for app lifetime so re-apply is instant. Populated in background.
    private static let t32CacheLock = NSLock()
    private static var t32CubeCache: (dimension: Int, data: Data)?
    
    /// Call at app launch to preload T32 (LUT + texture + grain/dust) in background; stays cached until app kill for instant apply.
    static func warmUpT32InBackground() {
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = createColorCubeFilter(for: .t32Update)
            let size = CGSize(width: 64, height: 64)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let tinyImage = renderer.image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            var filtered = applyAdjustedFilter(
                to: tinyImage,
                with: .t32Update,
                filterIntensity: 1.0,
                textureIntensity: 1.0,
                exposureIntensity: 0.5
            )
            if let img = filtered, let withDust = DustAndDateEffectUtils.applyEffects(to: img, for: .t32Update) {
                _ = withDust
            }
            t32Log("warmup total", seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
    }
    
    // MODIFIED: Simplified the function to use a single `exposureIntensity` parameter.
    /// logT32Timing: false when prefetch (sirf user apply par time print ho).
    static func applyAdjustedFilter(
        to image: UIImage,
        with type: FilterType,
        filterIntensity: Double,
        textureIntensity: Double,
        exposureIntensity: Double,
        logT32Timing: Bool = true
    ) -> UIImage? {
        let t0 = (type == .t32Update && logT32Timing) ? CFAbsoluteTimeGetCurrent() : 0
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
        
        // Texture (noise overlay) sirf T32 par – baaki filters par grain/texture nahi.
        if type == .t32Update && textureIntensity > 0 {
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
        
        // T33: mamuli sharpness, phir dust overlay
        if type == .t33 {
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setValue(processed, forKey: kCIInputImageKey)
                sharpen.setValue(0.22, forKey: kCIInputSharpnessKey)
                if let sharpened = sharpen.outputImage?.cropped(to: processed.extent) {
                    processed = sharpened
                }
            }
            if let withDust = T33Filter.applyDustOverlay(photo: processed, extent: processed.extent) {
                processed = withDust
            }
        }
        // T34: "Dust t32" overlay
        if type == .t34, let withDust = T34Filter.applyDustOverlay(photo: processed, extent: processed.extent) {
            processed = withDust
        }
        
        guard let cgImage = context.createCGImage(processed, from: processed.extent) else { return nil }
        if type == .t32Update && logT32Timing && t0 > 0 {
            t32Log("LUT+texture+render", seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    static func createColorCubeFilter(for type: FilterType) -> CIFilter? {
        if type == .t32Update || type == .t33 || type == .t34 {
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
            case .t32Update, .t33, .t34: return "T32 update"
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
    /// JPEG save quality – high quality capture ke liye 0.95 (device max quality capture alag se CameraView mein).
    static let jpegCompressionQuality: CGFloat = 0.95
    /// Jab T32 result ready ho (addPhoto ya prefetch) – post with userInfo ["photoId": String]. View isse sun kar current photo refresh kare.
    static let t32ResultReadyNotification = Notification.Name("T32ResultReady")
    /// Recently captured T32 photo id – isko priority deni hai, baaki normal.
    var lastAddedT32PhotoId: String?
    
    var lastCapturedExposure: Double = 0.5
    
    @Published var photos: [PhotoMetadata] = []
    
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled: Bool = true
    
    private let photosKey = "savedPhotos"
    
    /// T32 result cache: aik bar load ho to session bhar reuse, bar bar load nahi. LRU + size limit taake memory/energy theek rahe.
    private var t32ResultCache: [String: UIImage] = [:]
    private var t32CacheOrder: [String] = []
    private let t32CacheLock = NSLock()
    private let t32CacheMaxCount = 5
    private let t32PrefetchQueue = DispatchQueue(label: "com.ferrey.t32prefetch", qos: .userInitiated)
    
    /// Call when user goes back (e.g. leaves gallery) so next time T32 can load fresh.
    func clearT32SessionCache() {
        t32CacheLock.lock()
        t32ResultCache.removeAll()
        t32CacheOrder.removeAll()
        t32CacheLock.unlock()
    }
    
    /// Returns true if T32 result is in memory ya disk (apply instant / load fast, loader avoid).
    func hasCachedT32(for id: String, filterIntensity: Double, textureIntensity: Double, exposureIntensity: Double) -> Bool {
        t32CacheLock.lock()
        let key = t32CacheKey(id: id, fi: filterIntensity, ti: textureIntensity, ei: exposureIntensity)
        let inMemory = t32ResultCache[key] != nil
        t32CacheLock.unlock()
        if inMemory { return true }
        return FileManager.default.fileExists(atPath: t32CacheFileURL(for: id).path)
    }
    
    /// Cache mein daalte waqt jagah na ho to purani (LRU) entry hata do.
    private func t32CacheEvictIfNeeded(beforeAddingKey newKey: String) {
        guard t32ResultCache[newKey] == nil else { return }
        while t32CacheOrder.count >= t32CacheMaxCount, let oldest = t32CacheOrder.first {
            t32CacheOrder.removeFirst()
            t32ResultCache.removeValue(forKey: oldest)
        }
    }
    
    /// T32: pehle memory, phir disk (t32_cache file) check; nahi mila to pipeline chala kar memory + disk par save. Ek bar run, phir reuse.
    func prefetchT32IfNeeded(for id: String, filterIntensity: Double, textureIntensity: Double, exposureIntensity: Double) {
        let key = t32CacheKey(id: id, fi: filterIntensity, ti: textureIntensity, ei: exposureIntensity)
        let alreadyInMemory: Bool = {
            t32CacheLock.lock()
            defer { t32CacheLock.unlock() }
            return t32ResultCache[key] != nil
        }()
        if alreadyInMemory { return }
        
        let cacheFileURL = t32CacheFileURL(for: id)
        if FileManager.default.fileExists(atPath: cacheFileURL.path),
           let diskImage = UIImage(contentsOfFile: cacheFileURL.path) {
            t32CacheLock.lock()
            t32CacheEvictIfNeeded(beforeAddingKey: key)
            t32ResultCache[key] = diskImage
            t32CacheOrder.append(key)
            t32CacheLock.unlock()
            return
        }
        if id == lastAddedT32PhotoId {
            return
        }
        
        let origURL = originalURL(for: id)
        t32PrefetchQueue.async { [weak self] in
            guard let self = self else { return }
            let alreadyThere: Bool = {
                self.t32CacheLock.lock()
                defer { self.t32CacheLock.unlock() }
                return self.t32ResultCache[key] != nil
            }()
            if alreadyThere { return }
            if FileManager.default.fileExists(atPath: cacheFileURL.path),
               let diskImage = UIImage(contentsOfFile: cacheFileURL.path) {
                self.t32CacheLock.lock()
                self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                self.t32ResultCache[key] = diskImage
                self.t32CacheOrder.append(key)
                self.t32CacheLock.unlock()
                return
            }
            guard let original = UIImage(contentsOfFile: origURL.path) else { return }
            autoreleasepool {
                print("[T32 prefetch] grain started")
                let t0 = CFAbsoluteTimeGetCurrent()
                var filtered = FilterUtils.applyAdjustedFilter(
                    to: original,
                    with: .t32Update,
                    filterIntensity: filterIntensity,
                    textureIntensity: textureIntensity,
                    exposureIntensity: exposureIntensity,
                    logT32Timing: false
                ) ?? original
                if let withEffects = DustAndDateEffectUtils.applyEffects(to: filtered, for: .t32Update, logTiming: false) {
                    filtered = withEffects
                }
                let elapsed = CFAbsoluteTimeGetCurrent() - t0
                print(String(format: "[T32 prefetch] grain completed: %.2f s", elapsed))
                if let data = filtered.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                    try? data.write(to: cacheFileURL)
                }
                self.t32CacheLock.lock()
                self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                self.t32ResultCache[key] = filtered
                self.t32CacheOrder.append(key)
                self.t32CacheLock.unlock()
                DispatchQueue.main.async {
                    if let index = self.photos.firstIndex(where: { $0.id == id }), self.photos[index].filter == .t32Update {
                        if let data = filtered.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                            try? data.write(to: self.filteredURL(for: id, filter: .t32Update))
                        }
                        self.photos[index].lastUpdated = Date()
                        self.save()
                        NotificationCenter.default.post(name: PhotoManager.t32ResultReadyNotification, object: nil, userInfo: ["photoId": id])
                    }
                }
            }
        }
    }
    
    private func t32CacheKey(id: String, fi: Double, ti: Double, ei: Double) -> String {
        "\(id)_\(fi)_\(ti)_\(ei)"
    }
    
    /// Call when camera screen is showing with T32 selected – warms grain pipeline in background so first capture is faster.
    func warmT32PipelineIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            let size = CGSize(width: 64, height: 64)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let dummy = renderer.image { ctx in UIColor.darkGray.setFill(); ctx.fill(CGRect(origin: .zero, size: size)) }
            let afterLUT = FilterUtils.applyAdjustedFilter(to: dummy, with: .t32Update, filterIntensity: 1.0, textureIntensity: 1.0, exposureIntensity: 0.5, logT32Timing: false) ?? dummy
            _ = DustAndDateEffectUtils.applyEffects(to: afterLUT, for: .t32Update, logTiming: false)
        }
    }
    
    /// Bakes T32 date stamp into the image when date is enabled (fixed position/size/angle).
    private func bakeDateIfNeeded(_ image: UIImage, filter: FilterType, photoId: String) -> UIImage {
        guard filter == .t32Update, DustAndDateEffectUtils.isDateEnabled(),
              let withDate = FilmDateOverlay.apply(to: image) else { return image }
        return withDate
    }
    
    private init() {
        load()
        migrateAndCleanFilteredFiles() // <- removes old _filtered_ variants
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let decoded = try? JSONDecoder().decode([PhotoMetadata].self, from: data) {
            photos = decoded
            removeOrphanedPhotos()
        }
    }
    
    /// Deleted image footprints na dikhein: jin photos ki original/filtered dono files disk par nahi, unhe list se hata do aur save.
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
    
    // IMPORTANT: single filtered filename to avoid storage bloat
    func filteredURL(for id: String, filter: FilterType) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id)_filtered.jpg")
    }
    
    /// T32 prefetch result – run once, store here, reuse from disk so pipeline na dobara chale.
    func t32CacheFileURL(for id: String) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id)_t32_cache.jpg")
    }
    
    /// Adds a photo with filter applied. T32: photo is added immediately (no loader), grain runs in background and cache is updated.
    /// Non-T32: same as before. Completion is called on main when the new photo is in the list.
    func addPhoto(original: UIImage, filter: FilterType, shouldAutoSave: Bool = true, completion: (() -> Void)? = nil) {
        let id = UUID().uuidString
        let applyFullEffects = (filter != .normal)
        let textureValue = applyFullEffects ? 1.0 : 0.0
        let exposureValue = self.lastCapturedExposure
        let origURL = originalURL(for: id)
        let filtURL = filteredURL(for: id, filter: filter)
        
        if filter == .t32Update {
            // T32: add photo immediately with original as placeholder, run grain in background, then update file + cache.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { completion?(); return }
                if let data = original.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                    try? data.write(to: origURL)
                }
                if let data = original.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
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
                    self.lastAddedT32PhotoId = id
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.photos.insert(metadata, at: 0)
                    }
                    self.save()
                    completion?()
                }
                var filteredImage = FilterUtils.applyAdjustedFilter(
                    to: original,
                    with: .t32Update,
                    filterIntensity: 1.0,
                    textureIntensity: textureValue,
                    exposureIntensity: exposureValue,
                    logT32Timing: false
                ) ?? original
                if let withEffects = DustAndDateEffectUtils.applyEffects(to: filteredImage, for: .t32Update, logTiming: false) {
                    filteredImage = withEffects
                }
                let key = self.t32CacheKey(id: id, fi: 1.0, ti: textureValue, ei: exposureValue)
                self.t32CacheLock.lock()
                self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                self.t32ResultCache[key] = filteredImage
                self.t32CacheOrder.append(key)
                self.t32CacheLock.unlock()
                if let data = filteredImage.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                    try? data.write(to: filtURL)
                    try? data.write(to: self.t32CacheFileURL(for: id))
                }
                if self.autoSaveEnabled && shouldAutoSave {
                    let toSave = self.bakeDateIfNeeded(filteredImage, filter: filter, photoId: id)
                    UIImageWriteToSavedPhotosAlbum(toSave, nil, nil, nil)
                }
                DispatchQueue.main.async {
                    if let index = self.photos.firstIndex(where: { $0.id == id }) {
                        self.photos[index].lastUpdated = Date()
                        self.save()
                    }
                    if self.lastAddedT32PhotoId == id { self.lastAddedT32PhotoId = nil }
                    NotificationCenter.default.post(name: PhotoManager.t32ResultReadyNotification, object: nil, userInfo: ["photoId": id])
                }
            }
            return
        }
        
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
    
    /// Sync version – can block main thread on T32. Prefer `updateFilter(for:newFilter:completion:)` for UI.
    func updateFilter(for id: String, newFilter: FilterType) -> UIImage? {
        var result: UIImage?
        let semaphore = DispatchSemaphore(value: 0)
        updateFilter(for: id, newFilter: newFilter) { result = $0; semaphore.signal() }
        semaphore.wait()
        return result
    }
    
    /// Apply new filter on background so UI stays responsive (T32 grain especially). Completion called on main.
    /// T32: first apply in session runs pipeline; subsequent switch-back to T32 uses cache (instant) until user leaves gallery.
    func updateFilter(for id: String, newFilter: FilterType, completion: @escaping (UIImage?) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { completion(nil); return }
        let photo = photos[index]
        if photo.filter == newFilter { completion(nil); return }
        
        let intensity = photo.filterIntensity
        let texture = photo.textureIntensity
        let exposure = photo.exposureIntensity
        let origURL = originalURL(for: id)
        let filtURL = filteredURL(for: id, filter: newFilter)
        
        if newFilter == .t32Update {
            let key = t32CacheKey(id: id, fi: intensity, ti: texture, ei: exposure)
            let cached: UIImage? = {
                t32CacheLock.lock()
                defer { t32CacheLock.unlock() }
                guard let img = t32ResultCache[key] else { return nil }
                t32CacheOrder.removeAll { $0 == key }
                t32CacheOrder.append(key)
                return img
            }()
            if let img = cached {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    if let data = img.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                        try? data.write(to: filtURL)
                    }
                    DispatchQueue.main.async {
                        self.photos[index].filter = newFilter
                        self.photos[index].lastUpdated = Date()
                        self.save()
                        completion(img)
                    }
                }
                return
            }
            let cacheFileURL = t32CacheFileURL(for: id)
            if FileManager.default.fileExists(atPath: cacheFileURL.path),
               let diskImg = UIImage(contentsOfFile: cacheFileURL.path) {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    if let data = diskImg.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                        try? data.write(to: filtURL)
                    }
                    self.t32CacheLock.lock()
                    self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                    self.t32ResultCache[key] = diskImg
                    self.t32CacheOrder.append(key)
                    self.t32CacheLock.unlock()
                    DispatchQueue.main.async {
                        self.photos[index].filter = newFilter
                        self.photos[index].lastUpdated = Date()
                        self.save()
                        completion(diskImg)
                    }
                }
                return
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion(nil); return }
            self.removeAllFilteredVariants(for: id)
            guard let original = UIImage(contentsOfFile: origURL.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let t0 = newFilter == .t32Update ? CFAbsoluteTimeGetCurrent() : 0
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
            if newFilter == .t32Update && t0 > 0 {
                t32Log("updateFilter total", seconds: CFAbsoluteTimeGetCurrent() - t0)
                let key = self.t32CacheKey(id: id, fi: intensity, ti: texture, ei: exposure)
                self.t32CacheLock.lock()
                self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                self.t32ResultCache[key] = filtered
                self.t32CacheOrder.append(key)
                self.t32CacheLock.unlock()
                if let data = filtered.jpegData(compressionQuality: PhotoManager.jpegCompressionQuality) {
                    try? data.write(to: self.t32CacheFileURL(for: id))
                }
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
    
    /// Updates filter intensities; heavy work runs on background. Completion called on main with new image.
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
            let t0 = filter == .t32Update ? CFAbsoluteTimeGetCurrent() : 0
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
            if filter == .t32Update && t0 > 0 {
                t32Log("updateIntensities total", seconds: CFAbsoluteTimeGetCurrent() - t0)
                let key = self.t32CacheKey(id: id, fi: filterIntensity, ti: textureIntensity, ei: exposureIntensity)
                self.t32CacheLock.lock()
                self.t32CacheEvictIfNeeded(beforeAddingKey: key)
                self.t32ResultCache[key] = filtered
                self.t32CacheOrder.append(key)
                self.t32CacheLock.unlock()
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
            try? fm.removeItem(at: t32CacheFileURL(for: id))
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
                if name.hasSuffix("_original.jpg") || name.hasSuffix("_t32_cache.jpg") || name.contains("_filtered_") || name.hasSuffix("_filtered.jpg") {
                    try? fm.removeItem(at: url)
                }
            }
        }
        photos.removeAll()
        UserDefaults.standard.removeObject(forKey: photosKey)
        clearImageCaches()
    }
}
