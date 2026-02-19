//
//  DustAndDateEffect.swift
//  Ferrey
//
//  Phase 4: Dust & Date effects. Dust = fine film-grain effect (reference-style).
//  All effect logic lives here; FilterType remains unchanged.
//

import Foundation
import UIKit
import CoreImage

// MARK: - Dust and Date Effect Keys (UserDefaults)

enum DustAndDateEffectKeys {
    static let dustEnabled = "phase4DustEnabled"
    static let dustIntensity = "phase4DustIntensity"
    static let dateEnabled = "phase4DateEnabled"
}

// MARK: - Dust and Date Effect Application

enum DustAndDateEffectUtils {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Apply dust (film grain) and optionally date when enabled. Call after filter pipeline.
    /// Returns image with effects applied, or original if nothing enabled / on failure.
    static func applyEffects(to image: UIImage) -> UIImage? {
        var result = image
        if Self.isDustEnabled(), let withDust = applyDustEffect(to: result, intensity: Self.dustIntensity()) {
            result = withDust
        }
        // Date effect: switch only for now; no rendering yet.
        return result
    }
    
    /// Apply only if dust is enabled in settings (reads UserDefaults).
    static func applyDustIfEnabled(to image: UIImage) -> UIImage? {
        guard isDustEnabled() else { return nil }
        return applyDustEffect(to: image, intensity: dustIntensity())
    }
    
    static func isDustEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: DustAndDateEffectKeys.dustEnabled)
    }
    
    static func dustIntensity() -> Double {
        let v = UserDefaults.standard.double(forKey: DustAndDateEffectKeys.dustIntensity)
        if v == 0 { return 0.2 }
        return max(0, min(1, v))
    }
    
    static func isDateEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: DustAndDateEffectKeys.dateEnabled)
    }
    
    // MARK: - Dust effect (luminance-only grain + micro dust)
    
//    / (1) 35mm film grain, luminance-only; midtone density +10–15%, highlights clean, shadows natural. (2) Extremely subtle tonal micro-variation on flat surfaces to reduce digital smoothness. (3) Micro dust overlay. No contrast/color/exposure/sharpness change, no new dust. Micro-refinement pass. Preserves resolution.
//    / (1) 35mm film grain (High Quality): Scaled Luma Noise, Overlay Blend. (2) T32 Color Grading.
    
    static func applyDustEffect(to image: UIImage, intensity: Double) -> UIImage? {
        guard let ciImage = CIImage(image: image.fixedOrientation()) else { return nil }
        let extent = ciImage.extent
        let grainStrength = 0.2 + (intensity * 0.3) // Stronger base for visibility
        
        // ---------------------------------------------------------
        // 1. High-Fidelity 35mm Grain (Refined: Finer & Sharper)
        // ---------------------------------------------------------
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        
        // Whitening (Monochrome Noise)
        let monoNoise = noise.applyingFilter("CIColorMonochrome", parameters: [
            "inputColor": CIColor(red: 0.5, green: 0.5, blue: 0.5),
            "inputIntensity": 1.0
        ])
        
        // Scale: Keep it tight (1.0) for fine 35mm texture (Reference Image 1 style)
        // No blur: Keep it crisp/sharp.
        let scaledNoise = monoNoise.transformed(by: CGAffineTransform(scaleX: 1.0, y: 1.0))
            .cropped(to: extent)
        
        // Contrast Boost for visibility
        let contrastGrain = scaledNoise.applyingFilter("CIColorControls", parameters: [
            "inputContrast": 1.6, // Slight boost for visibility
            "inputBrightness": 0.0,
            "inputSaturation": 0.0
        ])
        
        // Match Reference Image 1: Fine, sharp grain.
        // Micro-adjustment: Reduce highlight visibility ~5%, add organic irregularity.
        
        // Highlight Masking: Grain distinct in Mids/Shadows, less in Highlights
        let luma = ciImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.2126, z: 0.2126, w: 0),
            "inputGVector": CIVector(x: 0.7152, y: 0.7152, z: 0.7152, w: 0),
            "inputBVector": CIVector(x: 0.0722, y: 0.0722, z: 0.0722, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        
        // Mask: 1.0 in shadows/mids, fading to 0.0 in pure white
        // Adjustment: Reduce highlight visibility by ~5% (Bias 1.0 -> 0.95 in bright areas? tricky).
        // Standard Invert: (1 - Luma). To reduce grain in highlights even more, we want (1 - Luma) to be smaller when Luma is high.
        // Actually, just changing the bias from 1.0 to 0.95 reduces the CEILING of the mask, meaning even shadows get 5% less grain?
        // No, we want to cut highlights more.
        // Let's use a steeper curve or just shift the bias slightly.
        // Current: Out = 1.0 - Luma.
        // Target: Out = 0.95 - Luma? No, that reduces everywhere.
        // Target: Out = 1.0 - (Luma * 1.05)? Pushes whites to negative (clamped to 0).
        // Let's just adjust the bias to 0.95 as a safe "overall 5% reduction including highlights" which satisfies "reduce highlight visibility" (and everything else slightly).
        // User said: "Very slightly reduce grain visibility in highlight areas (approximately 5%)".
        // Let's try: Out = 1.05 - (Luma * 1.1).
        // Luma 0.0 -> 1.05 (Clamped 1.0). Shadows Safe.
        // Luma 1.0 -> -0.05 (Clamped 0.0). Highlights Cleaner.
        
        let mask = luma.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1.05, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: -1.05, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: -1.05, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1.0, y: 1.0, z: 1.0, w: 0) // Keep 1.0 anchor for midtones, but the steeper slope cuts highlights faster.
        ])
        
        // Organic Irregularity: Use a low-freq noise to modulate the mask
        // Generate a large-scale noise pattern
        guard let irregularityNoise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let organicMap = irregularityNoise
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 50.0]) // Heavy blur for large blotches
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                "inputContrast": 0.2, // Very low contrast (subtle variation)
                "inputBrightness": 0.0,
                "inputSaturation": 0.0
            ])
            // Shift range to [0.8, 1.0] so it only reduces grain slightly, never adds
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0, y: 0, z: 0, w: 0), // Pass through gray
                "inputGVector": CIVector(x: 1.0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1.0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.4, y: 0.4, z: 0.4, w: 0) // Shift up? Noise is 0.5 +/-.
                // We want avg ~0.9.
            ])
            
        // Combine Luma Mask * Organic Map
        // Multiply filter
        let irregularMask = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: organicMap,
            kCIInputBackgroundImageKey: mask
        ])?.outputImage ?? mask
        
        // Blend Grain: Use Overlay for that "embedded" film look
        guard let overlayBlend = CIFilter(name: "CIOverlayBlendMode") else { return nil }
        overlayBlend.setValue(contrastGrain, forKey: kCIInputImageKey)
        overlayBlend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
        guard let grainResult = overlayBlend.outputImage else { return nil }
        
        // Mix based on Irregular Mask
        let maskedGrain = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: grainResult,
            kCIInputBackgroundImageKey: ciImage,
            kCIInputMaskImageKey: irregularMask
        ])?.outputImage ?? grainResult
        
        let finalGrainyImage = maskedGrain
        
        // ---------------------------------------------------------
        // 2. Color Grading (LUT: T32 (+ color preset))
        // ---------------------------------------------------------
        
        var finalOutput = finalGrainyImage
        
        // Apply "Filter2"
        if let lutFilter = createLUTFilter(named: "Filter2") {
            lutFilter.setValue(finalGrainyImage, forKey: kCIInputImageKey)
            if let lutOutput = lutFilter.outputImage {
                finalOutput = lutOutput
            } else {
                print("Warning: Filter2 LUT filter failed to produce output")
            }
        } else {
            print("Warning: Could not load Filter2.cube")
        }
         
        guard let cgImage = ciContext.createCGImage(finalOutput, from: finalOutput.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Private Helpers (LUT Parsing)
    
    // Helper to load LUT from Bundle (either root or LUTs folder)
    private static func createLUTFilter(named name: String) -> CIFilter? {
        // 1. Try LUTs subdirectory first (most likely location)
        var url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: "LUTs")
        
        // 2. Try root bundle if not found
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
