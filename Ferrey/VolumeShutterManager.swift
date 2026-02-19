// VolumeShutterManager.swift

import Foundation
import AVFoundation
import SwiftUI // For @AppStorage

class VolumeShutterManager: NSObject {
    static let shared = VolumeShutterManager()
    
    @AppStorage("volumeShutterEnabled") private var isEnabled: Bool = false // Defaults to false—ensure this is toggled on in app settings!
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var volumeObservation: NSKeyValueObservation?
    
    // This action will be triggered when the volume changes.
    var shutterAction: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Starts listening for volume changes.
    func startObserving() {
        guard volumeObservation == nil else { return }
        do {
            // Set category to ambient with mix option to detect changes without interrupting other audio.
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true, options: [])
            
            // Observe outputVolume changes using modern KVO.
            volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
                guard let self = self else { return }
                if self.isEnabled {
                    // Trigger the shutter action on the main thread.
                    DispatchQueue.main.async {
                        self.shutterAction?()
                    }
                }
            }
        } catch {
            print("Error: Could not start observing volume for shutter. \(error.localizedDescription)")
        }
    }
    
    /// Stops listening for volume changes.
    func stopObserving() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }
}
