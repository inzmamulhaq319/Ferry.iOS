//
//  FilmDateOverlay.swift
//  Ferrey
//
//  Date stamp design for T32 / dust filter. Style only – no filter logic.
//

import Foundation
import UIKit

enum FilmDateOverlay {
    
    /// Position: left edge ~1.5–2% from left; bottom of text ~25% from bottom. (0,0)=top-left, (1,1)=bottom-right.
    static let defaultPosition = CGPoint(x: 0.09, y: 0.78)
    /// Portrait default: vertical (+90°) so text reads top → bottom (country code at bottom).
    static let defaultAngle: CGFloat = 90
    static let defaultSize: CGFloat = 24   // in-app preview size
    
    /// Horizontal (landscape) picture = width > height. Date angle usi ke mutabiq.
    static func isLandscape(_ size: CGSize) -> Bool { size.width > size.height }
    
    /// Portrait: +90° (vertical top → bottom); landscape: 0° (horizontal along bottom).
    static func defaultAngle(for imageSize: CGSize) -> CGFloat {
        isLandscape(imageSize) ? 0 : defaultAngle
    }
    
    /// Display dimensions (orientation ke mutabiq) – horizontal/portrait sahi detect ke liye.
    static func displaySize(for image: UIImage) -> CGSize {
        let s = image.size
        switch image.imageOrientation {
        case .left, .right: return CGSize(width: s.height, height: s.width)
        default: return s
        }
    }
    
    // MARK: - Design (look only)
    
    static func formattedDateString(from date: Date = Date()) -> String {
        DateStyle.formattedString(from: date)
    }
    
    /// Fixed DS Digital font name used everywhere (PostScript name, not filename).
    /// DS-DIGI.TTF exposes the font as \"DS-Digital\".
    static let swiftUIFontName: String = "DS-Digital"
    
    private static func dateFont(size: CGFloat) -> UIFont {
        if let font = UIFont(name: "DS-Digital", size: size) {
            return font
        }
        // Safety fallback only if DS-DIGI is not found (should not happen if font is bundled correctly).
        return UIFont.systemFont(ofSize: size)
    }
    
    /// Optional soft shadow so it sits in the image
    private static var shadowColor: UIColor {
        UIColor.black.withAlphaComponent(0.5)
    }
    
    /// Inset from edges when drawing (export/bake) – corner ke kareeb allow.
    private static let defaultInset: CGFloat = 20
    
    /// Text size for saved photo = fixed percentage of image short side (a bit larger).
    private static func fontSize(for imageSize: CGSize) -> CGFloat {
        let short = min(imageSize.width, imageSize.height)
        return max(32, short * 0.04) // ~4% of short side, at least 32pt
    }
    
    /// On-screen preview size = same percentage of on-screen image, so scale matches.
    static func previewFontSize(for imageSize: CGSize, inViewSize viewSize: CGSize) -> CGFloat {
        let shortView = min(viewSize.width, viewSize.height)
        return max(18, shortView * 0.04)
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
        let angleDeg = degrees ?? defaultAngle(for: size)
        let angleRad = angleDeg * .pi / 180
        
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
    
    /// First time (no saved angle): vertical (+90°). After user rotates, saved angle is used.
    static func angle(forPhotoId id: String) -> CGFloat {
        let key = "T32DateAngle_" + id
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultAngle }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }
    
    static func setAngle(_ value: CGFloat, forPhotoId id: String) {
        UserDefaults.standard.set(Double(value), forKey: "T32DateAngle_" + id)
    }
}
