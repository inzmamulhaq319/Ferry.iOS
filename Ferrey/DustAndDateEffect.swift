//
//  DustAndDateEffect.swift
//  Ferrey
//

import Foundation
import UIKit
import CoreImage

enum DustAndDateEffectKeys {
    static let dateEnabled = "phase4DateEnabled"
    /// 0.0–1.0 (0%–100%) dust overlay strength for T34 only.
    static let dustIntensity = "phase4DustIntensity"
}

enum DustAndDateEffectUtils {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let grainCacheLock = NSLock()
    private static var cachedGrainLuma: CIImage?
    private static var cachedLowFreqLuma: CIImage?
    private static var cachedDistortLuma: CIImage?
    private static let grainCacheSize: CGFloat = 2048
    
    /// Natural grain; dark areas almost no change (0.5) so shadows stay clean.
    private static let grainKernel: CIColorKernel? = {
        CIColorKernel(source: """
            kernel vec4 remapGrainForOverlay(__sample base, __sample n, __sample lowFreq, __sample distort) {
                float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
                float g = (n.r - 0.5) * 0.18 + 0.5;
                float mod = 0.88 + 0.12 * lowFreq.r;
                g = 0.5 + (g - 0.5) * mod;
                float shadowMask = 1.0 - smoothstep(0.0, 0.32, luma);
                g = 0.5 + (g - 0.5) * (1.0 - shadowMask * 0.92);
                float shadowBoost = smoothstep(0.0, 0.5, 1.0 - luma);
                g *= mix(0.94, 1.02, shadowBoost);
                float midtone = smoothstep(0.22, 0.45, luma) * (1.0 - smoothstep(0.55, 0.80, luma));
                g = 0.5 + (g - 0.5) * (0.72 + 0.32 * midtone);
                g += (distort.r - 0.5) * 0.002;
                g = clamp(g, 0.001, 1.0);
                g = pow(g, 0.92);
                return vec4(g, g, g, 1.0);
            }
        """)
    }()
    
    /// Date is drawn as draggable overlay in UI (T34); not baked here for other filters.
    static func applyEffects(to image: UIImage, for filter: FilterType, logTiming: Bool = true) -> UIImage? {
        return image
    }
    
    static func isDateEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: DustAndDateEffectKeys.dateEnabled)
    }

    /// Dust overlay intensity 0.0–1.0 from stored 0–100%. If user never changed slider (no key), use 100%.
    static func dustIntensity() -> Double {
        guard UserDefaults.standard.object(forKey: DustAndDateEffectKeys.dustIntensity) != nil else { return 1.0 }
        let percent = UserDefaults.standard.double(forKey: DustAndDateEffectKeys.dustIntensity)
        return max(0, min(1, percent / 100.0))
    }
    
    /// Slightly higher res for premium quality; grain at 0.27 keeps look refined.
    private static let dustPipelineScale: CGFloat = 0.42
    
    /// Sharpness → grain (medium, visible) → slight contrast. No grain blur. Runs at half-res then upscales for speed.
    static func applyDustEffect(to image: UIImage, intensity: Double) -> UIImage? {
        guard let ciImage = CIImage(image: image.fixedOrientation()) else { return nil }
        let fullExtent = ciImage.extent
        let scaleFactor = dustPipelineScale
        let scaledExtent = CGRect(x: 0, y: 0, width: fullExtent.width * scaleFactor, height: fullExtent.height * scaleFactor)
        let scaledInput = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)).cropped(to: scaledExtent)
        
        var work = scaledInput
        if let sharpened = applyFilmStyleSharpness(photo: work, extent: scaledExtent) {
            work = sharpened
        }
        guard var withGrain = applyVintageFilmOverlay(photo: work, extent: scaledExtent, intensity: intensity) else {
            return nil
        }
        if let withDust = applySubtleDustTexture(photo: withGrain, extent: scaledExtent, intensity: 0.4) {
            withGrain = withDust
        }
        if let withContrast = applySlightContrast(photo: withGrain) {
            withGrain = withContrast
        }
        if let withShadows = applyShadowLift(photo: withGrain) {
            withGrain = withShadows
        }
        guard let cgImageHalf = ciContext.createCGImage(withGrain, from: withGrain.extent) else { return nil }
        let fullSize = CGSize(width: fullExtent.width, height: fullExtent.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: fullSize, format: format)
        let upscaled = renderer.image { _ in
            UIImage(cgImage: cgImageHalf).draw(in: CGRect(origin: .zero, size: fullSize))
        }
        guard let cgFull = upscaled.cgImage else { return nil }
        return UIImage(cgImage: cgFull, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// Slight contrast so dark areas don’t crush; shadow lift preserves darks.
    private static func applySlightContrast(photo: CIImage) -> CIImage? {
        guard let color = CIFilter(name: "CIColorControls") else { return nil }
        color.setValue(photo, forKey: kCIInputImageKey)
        color.setValue(1.04, forKey: kCIInputContrastKey)
        return color.outputImage
    }
    
    /// Slight lift in dark areas to avoid crush and keep detail.
    private static func applyShadowLift(photo: CIImage) -> CIImage? {
        guard let gamma = CIFilter(name: "CIGammaAdjust") else { return nil }
        gamma.setValue(photo, forKey: kCIInputImageKey)
        gamma.setValue(0.96, forKey: "inputPower")
        return gamma.outputImage
    }
    
    /// Premium/luxury feel – luminance-only sharpness, color unchanged. Detail crisp, refined.
    private static func applyFilmStyleSharpness(photo: CIImage, extent: CGRect) -> CIImage? {
        guard let sharpen = CIFilter(name: "CISharpenLuminance") else { return nil }
        sharpen.setValue(photo, forKey: kCIInputImageKey)
        sharpen.setValue(0.42, forKey: kCIInputSharpnessKey)
        return sharpen.outputImage?.cropped(to: extent)
    }
    
    /// One-time fill of grain noise layers at fixed size; reused for all T32 photos for speed.
    private static func fillGrainCacheIfNeeded() {
        grainCacheLock.lock()
        defer { grainCacheLock.unlock() }
        if cachedGrainLuma != nil { return }
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return }
        let cacheExtent = CGRect(x: 0, y: 0, width: grainCacheSize, height: grainCacheSize)
        let grainScale: CGFloat = 0.92
        let scaledNoise = noise.transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
            .cropped(to: cacheExtent)
        let g = scaledNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).cropped(to: cacheExtent)
        let lowFreqScale: CGFloat = 0.038
        let lowFreqNoise = noise.transformed(by: CGAffineTransform(scaleX: lowFreqScale, y: lowFreqScale))
            .cropped(to: cacheExtent)
        let lf = lowFreqNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).cropped(to: cacheExtent)
        let distortScale: CGFloat = 0.6
        let distortNoise = noise.transformed(by: CGAffineTransform(scaleX: distortScale, y: distortScale))
            .cropped(to: cacheExtent)
        let dt = distortNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).cropped(to: cacheExtent)
        cachedGrainLuma = g
        cachedLowFreqLuma = lf
        cachedDistortLuma = dt
    }
    
    /// Cinematic film dust – organic, luminance-modulated. Reuses cached grain texture for speed; quality preserved.
    private static func applyVintageFilmOverlay(photo: CIImage, extent: CGRect, intensity: Double = 1.0) -> CIImage? {
        fillGrainCacheIfNeeded()
        grainCacheLock.lock()
        let gCache = cachedGrainLuma
        let lfCache = cachedLowFreqLuma
        let dtCache = cachedDistortLuma
        grainCacheLock.unlock()
        
        guard let gCache = gCache, let lfCache = lfCache, let dtCache = dtCache else { return photo }
        
        let sx = extent.width / grainCacheSize
        let sy = extent.height / grainCacheSize
        let t = CGAffineTransform(scaleX: sx, y: sy)
        let grainLuma = gCache.transformed(by: t).cropped(to: extent)
        let lowFreqLuma = lfCache.transformed(by: t).cropped(to: extent)
        let distortLuma = dtCache.transformed(by: t).cropped(to: extent)
        
        guard let kernel = grainKernel else { return photo }
        let overlayGrain = kernel.apply(extent: extent, arguments: [photo, grainLuma, lowFreqLuma, distortLuma]) ?? grainLuma
        
        let overlay = CIFilter(name: "CIOverlayBlendMode")!
        overlay.setValue(overlayGrain, forKey: kCIInputImageKey)
        overlay.setValue(photo, forKey: kCIInputBackgroundImageKey)
        guard var withGrain = overlay.outputImage?.cropped(to: extent) else { return photo }
        
        let amount: CGFloat = 0.14
        let blend = CIFilter(name: "CIDissolveTransition")!
        blend.setValue(photo, forKey: kCIInputImageKey)
        blend.setValue(withGrain, forKey: kCIInputTargetImageKey)
        blend.setValue(amount, forKey: kCIInputTimeKey)
        return blend.outputImage?.cropped(to: extent)
    }
    
    /// 35mm-style: very subtle dust/specks, film-like
    private static func applySubtleDustTexture(photo: CIImage, extent: CGRect, intensity: Double) -> CIImage? {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let scale = max(0.0, min(1.0, intensity)) * 0.28
        
        let scaledNoise = noise.transformed(by: CGAffineTransform(scaleX: 1.15, y: 1.15))
            .cropped(to: extent)
        
        let mono = scaledNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).cropped(to: extent)
        
        // 35mm: very sparse specks, soft values
        guard let speckKernel = CIColorKernel(source: """
            kernel vec4 subtleSpecks(__sample n, __sample img, float strength) {
                float r = n.r;
                float bright = step(0.98, r) * strength * 0.09;
                float dark   = step(r, 0.02) * strength * (-0.06);
                vec3 add = vec3(bright + dark, bright + dark, bright + dark);
                return vec4(clamp(img.rgb + add, 0.0, 1.0), img.a);
            }
        """) else { return photo }
        let dustLayer = speckKernel.apply(extent: extent, arguments: [mono, photo, Float(scale)])
        
        guard let dusted = dustLayer else { return photo }
        // 35mm: more original, light dust
        let dustBlend = CIFilter(name: "CIDissolveTransition")!
        dustBlend.setValue(photo, forKey: kCIInputImageKey)
        dustBlend.setValue(dusted, forKey: kCIInputTargetImageKey)
        dustBlend.setValue(0.65, forKey: kCIInputTimeKey)  // 65% original
        return dustBlend.outputImage?.cropped(to: extent)
    }
    
    private static func applyDustEffectProcedural(ciImage: CIImage, extent: CGRect, intensity: Double, imageScale: CGFloat, imageOrientation: UIImage.Orientation) -> UIImage? {
        // 1. Apply slight blur to the base photo (as requested)
        let blurredPhoto = ciImage.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.0])
            .cropped(to: extent)
        
        // 2. Generate Random Noise
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        
        // 3. Create Sparse Dust Specks (Procedural)
        // We want very few, distinct white specks, not heavy grain.
        // We scale the noise up so the specks are visible particles, not single pixels.
        let scaledNoise = noise.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        
        let sparseDust = scaledNoise
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0), // Use Green channel for randomness
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                // Extremely high bias to threshold out almost all pixels, leaving only rare peaks
                "inputBiasVector": CIVector(x: -0.9992, y: -0.9992, z: -0.9992, w: 0)
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1000, y: 0, z: 0, w: 0), // Amplify the remaining peaks to pure white
                "inputGVector": CIVector(x: 0, y: 1000, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1000, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
            .cropped(to: extent)
        
        // 4. Create Very Subtle Scratches
        // Vertical scaling to create lines, but very sparse
        let scratches = noise
            .transformed(by: CGAffineTransform(scaleX: 0.5, y: 40.0))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.9995, y: -0.9995, z: -0.9995, w: 0) // Even sparser than dust
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 500, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 500, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 500, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
            .cropped(to: extent)
        
        // 5. Combine Dust and Scratches
        let dustAndScratches = sparseDust.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: scratches
        ])
        
        // 6. Blend with Photo using Screen Mode
        // Screen mode ensures white specks are added to the image without darkening it
        let finalImage = dustAndScratches.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: blurredPhoto
        ])
        
        // 7. Output Result
        guard let cgImage = ciContext.createCGImage(finalImage, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: imageScale, orientation: imageOrientation)
    }
    
    // Helper to load LUT (kept for reference or future use)
    private static func createLUTFilter(named name: String) -> CIFilter? {
        var url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: "LUTs")
        if url == nil {
            url = Bundle.main.url(forResource: name, withExtension: "cube")
        }
        
        guard let fileURL = url else {
            print("Error: LUT file '\(name).cube' not found in bundle.")
            return nil
        }
        
        guard let (dimension, cubeData) = parseCubeFile(at: fileURL) else {
            print("Error: Failed to parse/read LUT file at \(fileURL)")
            return nil
        }
        
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
        return filter
    }
    
    private static func parseCubeFile(at url: URL) -> (dimension: Int, data: Data)? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .ascii) else { return nil }
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
