//
//  DateStyle.swift
//  Ferrey
//
//  Single fixed date stamp style (no style picker).
//

import Foundation
import SwiftUI
import UIKit

enum DateStyle {

    /// Format: day month year country code e.g. "3 3 26 br" — country from device region
    static func formattedString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d M yy"
        let datePart = formatter.string(from: date)
        let countryCode = (Locale.current.region?.identifier ?? "US").uppercased()
        return "\(datePart) \(countryCode)"
    }

    /// #e0cc6a
    static var color: Color { Color(red: 224/255.0, green: 204/255.0, blue: 106/255.0) }

    static var uiColor: UIColor {
        UIColor(red: 224/255.0, green: 204/255.0, blue: 106/255.0, alpha: 0.95)
    }

    static var fontWeight: Font.Weight { .medium }
    static var uiFontWeight: UIFont.Weight { .medium }
}
