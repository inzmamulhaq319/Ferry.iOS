// FerreyApp.swift
// Ferrey
// Created by Junaid on 23/07/2025.

import SwiftUI
import SwiftRater
import CoreText

@main
struct FerreyApp: App {
    // Existing StoreManager
    @StateObject private var storeManager = StoreManager.shared
    // NEW: Bridge to UIApplicationDelegate for SwiftRater setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storeManager)
                .task {
                    await storeManager.updateCustomerProductStatus()
                }
                .onAppear {
                    SwiftRater.check()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                SwiftRater.check()
            }
        }
    }
}

// MARK: - AppDelegate for SwiftRater configuration
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // --- SwiftRater configuration ---
        // When to ask
        SwiftRater.daysUntilPrompt = 7
        SwiftRater.usesUntilPrompt = 5
        SwiftRater.significantUsesUntilPrompt = 3
        SwiftRater.daysBeforeReminding = 5
        SwiftRater.showLaterButton = true
        SwiftRater.conditionsMetMode = .any     // or .any
        
        
        // Replace with your real App Store ID when available.
        SwiftRater.appID = "6749463038"
        
        SwiftRater.appName = NSLocalizedString("swiftRater.appName", comment: "")
        
        SwiftRater.alertTitle = String(
            format: NSLocalizedString("swiftRater.alertTitle", comment: ""),
            NSLocalizedString("swiftRater.appName", comment: "")
        )
        SwiftRater.alertMessage = NSLocalizedString("swiftRater.alertMessage", comment: "")
        SwiftRater.alertCancelTitle    = NSLocalizedString("swiftRater.alertCancelTitle", comment: "")
        SwiftRater.alertRateTitle      = NSLocalizedString("swiftRater.alertRateTitle", comment: "")
        SwiftRater.alertRateLaterTitle = NSLocalizedString("swiftRater.alertRateLaterTitle", comment: "")
        
        // Kick off internal counters (must be called once on launch)
        SwiftRater.appLaunched()  // :contentReference[oaicite:3]{index=3}
        
        // Register Druk font from bundle so it loads even if plist path differs
        registerDrukFont()
        
        return true
    }
    
    private func registerDrukFont() {
        if let url = Bundle.main.url(forResource: "DrukTextWideTrial-Medium", withExtension: "otf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "DrukTextWideTrial-Medium", withExtension: "otf") {
            CTFontManagerRegisterFontURLs([url] as CFArray, .process, true, nil)
        }
    }
}

