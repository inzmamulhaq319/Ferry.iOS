//
//  UtilManager.swift
//  Wallbyte
//
//  Created by Junaid on 25/09/2024.
//

import SwiftUI

class UtilityManager {
    
    
    static func openURL(_ url: String) {
        if let url = URL(string: url) {
            UIApplication.shared.open(url)
        }
    }
    
    
}
