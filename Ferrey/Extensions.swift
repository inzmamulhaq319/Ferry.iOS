//
//  Extensions.swift
//  Lumina
//
//  Created by Junaid on 23/08/2024.
//

import SwiftUI

extension Bundle {
    /// Retrieves the app's marketing version and build number from the Info.plist.
    /// Example output: "1.3.0 (1)"
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "\(version) (\(build))"
    }
}

extension Font {
    static func druk(size: CGFloat) -> Font {
        // Temporary: DrukTextWide font removed, use plain system font instead.
        return .system(size: size, weight: .regular, design: .default)
    }
}

extension UIImage {
    func fixOrientation() -> UIImage {
        // If the orientation is already correct, just return the image.
        if self.imageOrientation == .up {
            return self
        }
        
        // Use a UIGraphicsImageRenderer to redraw the image.
        // This method respects the image's orientation property.
        let format = imageRendererFormat
        return UIGraphicsImageRenderer(size: self.size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
}

extension Color {
    
    static func myColors() -> [String] {
        return ["#000000",  // Black
                "#AFE9DD",  // Light Aqua
                "#C3B1E1",  // Soft Purple
                "#77DD77",  // Light Green
                "#FFB380",  // Peach
                "#FF6961",  // Coral Red
                "#FFE680",  // Light Yellow
                "#AC939D",  // Soft Mauve
                "#FF80E5",  // Pink
                "#80E5FF",  // Sky Blue
                "#B5838D",  // Pale Brownish Pink
                "#F4BFBF",  // Light Coral Pink
                "#F4A261",  // Warm Sand
                "#E9C46A",  // Mustard Yellow
                "#264653",  // Deep Teal
                "#E76F51",  // Warm Terracotta
                "#2A9D8F",  // Rich Turquoise
                "#F9DC5C",  // Soft Lemon
                "#D3C0D2",  // Muted Lavender
                "#D4A5A5",  // Soft Rose
                
        ]
    }

        
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
            case 3: // RGB (12-bit)
                (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6: // RGB (24-bit)
                (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8: // ARGB (32-bit)
                (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default:
                (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


