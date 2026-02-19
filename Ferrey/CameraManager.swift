import Foundation
import AVFoundation
import SwiftUI

class CameraManager: ObservableObject {
    static let shared = CameraManager()
    
    @Published var isBackCamera: Bool = true
    @Published var zoomFactors: [Double] = [1.0]
    @Published var zoomFactorDisplayNames: [Double: String] = [1.0: "1x"]
    @Published var defaultZoomFactor: Double = 1.0
    
    @Published var currentZoomFactorDisplayText: String = "1x"
    
    private var normalizationFactor: Double = 1.0
    
    @Published var currentZoomFactor: Double {
        didSet {
            let key = self.isBackCamera ? "lastZoomFactor_back" : "lastZoomFactor_front"
            UserDefaults.standard.set(currentZoomFactor, forKey: key)
            updateDisplayText()
        }
    }
    
    private init() {
        let savedZoom = UserDefaults.standard.double(forKey: "lastZoomFactor_back")
        self.currentZoomFactor = savedZoom
    }
    
    func updateCameraState(for device: AVCaptureDevice) {
        
        self.isBackCamera = device.position == .back
        var factors: [Double] = []
        var displayNames: [Double: String] = [:]
        
        var normalizationFactor: Double = 1.0
        
        if self.isBackCamera && device.isVirtualDevice {
            let constituentDevices = device.constituentDevices
            
            // Start with the minimum zoom (usually 0.5x for Ultra Wide)
            var rawFactors: Set<Double> = [device.minAvailableVideoZoomFactor]
            
            // Add the switch-over points (where lenses switch)
            rawFactors.formUnion(device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue })
            
            // Find the Wide Angle Camera to use as the baseline (1.0x)
            if let wideAngleIndex = constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) {
                // The wide angle camera's zoom factor is the one at its index in the switch-over list (roughly)
                // But a safer way for the 'Virtual' device is to look at the switch over factors.
                // Usually:
                // 0: Ultra Wide (0.5x - 1.0x)
                // 1: Wide (1.0x - 3.0x)
                // 2: Telephoto (3.0x+)
                
                // If we have an Ultra Wide, the Wide camera starts at the first switch over point.
                // If we don't have Ultra Wide, Wide starts at minAvailableVideoZoomFactor.
                
                let hasUltraWide = constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera })
                
                if hasUltraWide {
                    // If we have Ultra Wide, the Wide camera is the *second* device (index 1 usually),
                    // so its native start point is the first switch-over factor.
                    if let firstSwitch = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                        normalizationFactor = firstSwitch.doubleValue
                    }
                } else {
                    // If no Ultra Wide, the Wide camera is likely the base, so normalization is minAvailable (usually 1.0)
                    normalizationFactor = device.minAvailableVideoZoomFactor
                }
            } else {
                 // Fallback if no Wide camera found (unlikely on back virtual device)
                 normalizationFactor = device.minAvailableVideoZoomFactor
            }
            
            // Sort and filter factors
            let sortedRawFactors = rawFactors.sorted()
            
            for rawFactor in sortedRawFactors {
                let normalized = rawFactor / normalizationFactor
                
                // We only want "nice" zoom levels like 0.5, 1.0, 2.0, 3.0, 5.0
                // We'll accept them if they are close to these values.
                // Or we can just expose all switch points.
                // Let's expose the switch points but format them nicely.
                
                factors.append(rawFactor)
                displayNames[rawFactor] = self.zoomText(for: normalized)
            }
            
            // Ensure 1.0x (relative) is always present if it's valid
            let oneXRaw = normalizationFactor
            if !factors.contains(where: { abs($0 - oneXRaw) < 0.01 }) {
                factors.append(oneXRaw)
                displayNames[oneXRaw] = "1x"
            }
            
            factors.sort()
            self.defaultZoomFactor = normalizationFactor
            
        } else {
            factors = [1.0]
            displayNames = [1.0: "1x"]
            self.defaultZoomFactor = 1.0
        }
        
        self.normalizationFactor = normalizationFactor
        self.zoomFactors = factors
        self.zoomFactorDisplayNames = displayNames
        
        let key = self.isBackCamera ? "lastZoomFactor_back" : "lastZoomFactor_front"
        let savedZoom = UserDefaults.standard.double(forKey: key)
        
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = device.activeFormat.videoMaxZoomFactor
        
        if savedZoom >= minZoom && savedZoom <= maxZoom {
            self.currentZoomFactor = savedZoom
        } else {
            self.currentZoomFactor = self.defaultZoomFactor
        }
    }
    
    private func updateDisplayText() {
        if let displayName = self.zoomFactorDisplayNames[self.currentZoomFactor] {
            self.currentZoomFactorDisplayText = displayName
        } else {
            let normalizedZoom = self.currentZoomFactor / self.normalizationFactor
            let roundedValue = Int(normalizedZoom.rounded())
            self.currentZoomFactorDisplayText = "\(roundedValue)x"
        }
    }
    
    private func zoomText(for z: Double) -> String {
        let roundedZoom = (z * 10).rounded() / 10
        if roundedZoom.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(roundedZoom))x"
        } else {
            return String(format: "%.1fx", roundedZoom)
        }
    }
}
