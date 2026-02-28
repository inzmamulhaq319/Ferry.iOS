//
//  FilmDateOverlay.swift
//  Ferrey
//
//  Date stamp design for T32 / dust filter. Style only – no filter logic.
//

import Foundation
import UIKit

enum FilmDateOverlay {
    
    /// Default position: bottom-left corner, wall ke kareeb. (0,0)=top-left, (1,1)=bottom-right.
    static let defaultPosition = CGPoint(x: 0.008, y: 0.97)
    /// Default angle when first time: vertical (-90°). After user rotates, saved value is used.
    static let defaultAngle: CGFloat = -90
    static let defaultSize: CGFloat = 10
    
    // MARK: - Design (look only)
    
    static func formattedDateString(from date: Date = Date()) -> String {
        DateStyle.formattedString(from: date)
    }
    
    private static func dateFont(size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: DateStyle.uiFontWeight)
    }
    
    /// Optional soft shadow so it sits in the image
    private static var shadowColor: UIColor {
        UIColor.black.withAlphaComponent(0.5)
    }
    
    /// Inset from edges when drawing (export/bake) – corner ke kareeb allow.
    private static let defaultInset: CGFloat = 20
    
    /// Text size relative to image short side; kept smaller for date stamp.
    private static func fontSize(for imageSize: CGSize) -> CGFloat {
        let short = min(imageSize.width, imageSize.height)
        return max(28, min(72, short * 0.012 + 32))
    }
    
    // MARK: - Draw (vertical, any position)
    
    /// Renders the date onto the image. Position/size/angle optional; nil = default. Single fixed style.
    static func apply(to image: UIImage, date: Date = Date(), position: CGPoint? = nil, size customSize: CGFloat? = nil, angle degrees: CGFloat? = nil) -> UIImage? {
        let toDraw = image.fixedOrientation()
        let size = toDraw.size
        guard size.width > 0, size.height > 0 else { return nil }
        
        let norm = position ?? defaultPosition
        let anchorX = max(defaultInset, min(size.width - defaultInset, norm.x * size.width))
        let anchorYFromBottom = (1.0 - norm.y) * size.height
        let anchorYFromBottomClamped = max(defaultInset, min(size.height - defaultInset, anchorYFromBottom))
        
        let ptSize = customSize ?? fontSize(for: size)
        let angleRad = (degrees ?? defaultAngle) * .pi / 180
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = toDraw.scale
        format.opaque = false
        
        let styleColor = DateStyle.uiColor
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let result = renderer.image { ctx in
            toDraw.draw(at: .zero)
            
            let font = dateFont(size: ptSize)
            let text = DateStyle.formattedString(from: date)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: styleColor
            ]
            
            let attr = NSAttributedString(string: text, attributes: attributes)
            let naturalTextSize = attr.size()
            let contentSize = naturalTextSize
            let textOrigin: CGPoint = .zero
            let centerX = anchorX + contentSize.height * 0.5
            let centerY = size.height - anchorYFromBottomClamped - contentSize.width * 0.5
            
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: centerX, y: centerY)
            cg.rotate(by: angleRad)
            cg.translateBy(x: -contentSize.width * 0.5, y: -contentSize.height * 0.5)
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: shadowColor.cgColor)
            attr.draw(in: CGRect(origin: textOrigin, size: naturalTextSize))
            cg.restoreGState()
        }
        
        guard let cg = result.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: toDraw.scale, orientation: .up)
    }
    
    // MARK: - Persist position per photo
    
    private static let positionPrefix = "T32DatePosition_"
    
    /// First time (no saved position): bottom left. After user drags, saved position is used.
    static func position(forPhotoId id: String) -> CGPoint {
        let key = positionPrefix + id
        guard let s = UserDefaults.standard.string(forKey: key) else { return defaultPosition }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 2 else { return defaultPosition }
        return CGPoint(x: parts[0], y: parts[1])
    }
    
    static func setPosition(_ point: CGPoint, forPhotoId id: String) {
        let key = positionPrefix + id
        let s = "\(point.x),\(point.y)"
        UserDefaults.standard.set(s, forKey: key)
    }
    
    static func size(forPhotoId id: String) -> CGFloat {
        let key = "T32DateSize_" + id
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultSize }
        let v = CGFloat(UserDefaults.standard.double(forKey: key))
        return v > 0 ? v : defaultSize
    }
    
    static func setSize(_ value: CGFloat, forPhotoId id: String) {
        UserDefaults.standard.set(Double(value), forKey: "T32DateSize_" + id)
    }
    
    /// First time (no saved angle): vertical (-90°). After user rotates, saved angle is used.
    static func angle(forPhotoId id: String) -> CGFloat {
        let key = "T32DateAngle_" + id
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultAngle }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }
    
    static func setAngle(_ value: CGFloat, forPhotoId id: String) {
        UserDefaults.standard.set(Double(value), forKey: "T32DateAngle_" + id)
    }
}
