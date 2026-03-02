//
//  T33Filter.swift
//  Ferrey
//
//  T33: "T32 update.cube" LUT + dust_04 overlay.
//

import Foundation
import UIKit
import CoreImage

enum T33Filter {
    static let lutFileName = "T32 update"
    
    /// dust_04 overlay – same 25% blend (Data Set/NSDataAsset se load).
    /// Extent (0,0,w,h) normalize taake capture par white layer na aaye.
    static func applyDustOverlay(photo: CIImage, extent: CGRect) -> CIImage? {
        let origin = extent.origin
        let normExtent = CGRect(origin: .zero, size: extent.size)
        let photoWork: CIImage
        if origin.x != 0 || origin.y != 0 {
            photoWork = photo.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        } else {
            photoWork = photo
        }
        // dust_04 – Data Set se load; pehle NSDataAsset, phir bundle, phir named
        let dustImage: UIImage? = {
            if let asset = NSDataAsset(name: "dust_04"), let img = UIImage(data: asset.data) { return img }
            if let url = Bundle.main.url(forResource: "dust_04", withExtension: "webp"),
               let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
            if let img = UIImage(named: "dust_04") { return img }
            return nil
        }()
        guard let dust = dustImage, let dustCI = CIImage(image: dust) else { return photo }
        var dustExt = dustCI.extent
        let dustAdjusted: CIImage
        if dustExt.origin.x != 0 || dustExt.origin.y != 0 {
            dustAdjusted = dustCI.transformed(by: CGAffineTransform(translationX: -dustExt.origin.x, y: -dustExt.origin.y))
            dustExt = dustAdjusted.extent
        } else {
            dustAdjusted = dustCI
        }
        guard dustExt.width > 0, dustExt.height > 0 else { return photo }
        let sx = normExtent.width / dustExt.width
        let sy = normExtent.height / dustExt.height
        let scale = max(sx, sy)
        let scaledW = dustExt.width * scale
        let scaledH = dustExt.height * scale
        let tx = (normExtent.width - scaledW) / 2
        let ty = (normExtent.height - scaledH) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
        let dustScaled = dustAdjusted.transformed(by: t).cropped(to: normExtent)
        // Screen blend: dust_04 overlay
        guard let screen = CIFilter(name: "CIScreenBlendMode") else { return photo }
        screen.setValue(photoWork, forKey: kCIInputBackgroundImageKey)
        screen.setValue(dustScaled, forKey: kCIInputImageKey)
        guard let dusted = screen.outputImage?.cropped(to: normExtent) else { return photo }
        // 25% dust, 75% original – dissolve se strength control
        guard let dissolve = CIFilter(name: "CIDissolveTransition") else { return dusted }
        dissolve.setValue(photoWork, forKey: kCIInputImageKey)
        dissolve.setValue(dusted, forKey: kCIInputTargetImageKey)
        dissolve.setValue(0.25, forKey: kCIInputTimeKey)
        return dissolve.outputImage?.cropped(to: normExtent)
    }
}

// MARK: - T34 (same file, neeche) – "Dust t32" .png overlay
enum T34Filter {
    /// T34: "Dust t32" (.png) capture par layer – Bundle se load, 50% mix taake clearly dikhe.
    static func applyDustOverlay(photo: CIImage, extent: CGRect) -> CIImage? {
        let dustImage: UIImage? = {
            if let img = UIImage(named: "Dust t32", in: Bundle.main, compatibleWith: nil) { return img }
            if let img = UIImage(named: "Dust t32") { return img }
            if let url = Bundle.main.url(forResource: "Dust t32", withExtension: "png", subdirectory: nil),
               let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
            return nil
        }()
        guard let dust = dustImage, let dustCI = CIImage(image: dust) else { return photo }
        var dustExt = dustCI.extent
        let dustAdjusted: CIImage
        if dustExt.origin.x != 0 || dustExt.origin.y != 0 {
            dustAdjusted = dustCI.transformed(by: CGAffineTransform(translationX: -dustExt.origin.x, y: -dustExt.origin.y))
            dustExt = dustAdjusted.extent
        } else {
            dustAdjusted = dustCI
        }
        guard dustExt.width > 0, dustExt.height > 0 else { return photo }
        let sx = extent.width / dustExt.width
        let sy = extent.height / dustExt.height
        let scale = max(sx, sy)
        let scaledW = dustExt.width * scale
        let scaledH = dustExt.height * scale
        let tx = (extent.width - scaledW) / 2
        let ty = (extent.height - scaledH) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
        let dustScaled = dustAdjusted.transformed(by: t).cropped(to: extent)
        // Screen blend: sirf dust/specks apply – black = no change, light = overlay. 100% use.
        guard let screen = CIFilter(name: "CIScreenBlendMode") else { return photo }
        screen.setValue(photo, forKey: kCIInputBackgroundImageKey)
        screen.setValue(dustScaled, forKey: kCIInputImageKey)
        return screen.outputImage?.cropped(to: extent)
    }
}
