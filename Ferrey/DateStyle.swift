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

    /// Format: Day-Month-Year e.g. "24 Feb 2026"
    static func formattedString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static var color: Color { Color(red: 1.0, green: 0.82, blue: 0.22) }

    static var uiColor: UIColor {
        UIColor(red: 1.0, green: 0.82, blue: 0.22, alpha: 0.95)
    }

    static var fontWeight: Font.Weight { .bold }

    static var uiFontWeight: UIFont.Weight { .bold }
}
