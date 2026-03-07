//
//  SettingsView.swift
//  Ferrey
//
//  Created by Junaid on 03/08/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: — Purchase State
    @EnvironmentObject private var storeManager: StoreManager
    
    @State private var showPro: Bool = false
    
    // MARK: — Confirmation Alerts
    @State private var showClearCacheAlert = false
    @State private var showDeleteAllAlert = false
    
    // MARK: - Storage State
    @State private var appStorageSize: String = "Calculating..."
    
    // MARK: — Feature Toggles (persisted)
    
    // Pro Features
    @AppStorage("disableSelfieMirroring") private var disableSelfieMirroring: Bool = false
    @AppStorage("gridOverlayEnabled")     private var gridOverlayEnabled: Bool      = false
    @AppStorage("livePreviewEnabled")     private var livePreviewEnabled: Bool      = false
    @AppStorage("hideLogoEnabled")        private var hideLogoEnabled: Bool         = false
    @AppStorage("autoSaveEnabled")        private var autoSaveEnabled: Bool         = true
    @AppStorage("flashOnEnabled")         private var flashOnEnabled: Bool          = false
    
    @AppStorage("volumeShutterEnabled")   private var volumeShutterEnabled: Bool    = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: — Pro Card
                if !storeManager.isPro {
                    Section {
                        ProCard(isPro: storeManager.isPro) {
                            purchasePro()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets()) // Make the card fill the width
                    }
                }
                
                Section {
                    HStack {
                        Label("settings.plan", systemImage: "person.crop.circle")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(storeManager.isPro ? LocalizedStringKey("settings.plan.pro") : LocalizedStringKey("settings.plan.free"))
                            .foregroundColor(storeManager.isPro ? .blue : .gray)
                            .fontWeight(storeManager.isPro ? .bold : .regular)
                    }
                    
                    Button(action: {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    }) {
                        Label("settings.restorePurchase", systemImage: "arrow.clockwise.circle")
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                
                // MARK: — Capture Section
                Section(header: Text("settings.section.capture")) {
                    Toggle("settings.toggle.flash", isOn: $flashOnEnabled)
                    Toggle("settings.toggle.volumeShutter", isOn: $volumeShutterEnabled)
                    lockedToggle("settings.toggle.selfieMirroring", isOn: $disableSelfieMirroring)
                }
                
                // MARK: — Library Section
                Section(header: Text("settings.section.library")) {
                    Toggle("settings.toggle.autoSave", isOn: $autoSaveEnabled)
                }
                
                // MARK: — Interface Section
                Section(header: Text("settings.section.interface")) {
                    lockedToggle("settings.toggle.livePreview", isOn: $livePreviewEnabled)
                    lockedToggle("settings.toggle.gridOverlay", isOn: $gridOverlayEnabled)
                    lockedToggle("settings.toggle.hideLogo", isOn: $hideLogoEnabled)
                }
                
                // MARK: — Storage Section
                Section(header: Text("settings.section.storage")) {
                    // Hide temporarily
                     lockedRow(label: "App Storage", systemImage: "internaldrive", value: storeManager.isPro ? appStorageSize : "--")
                    
                    lockedButton(label: "settings.button.deleteAll", systemImage: "trash.circle.fill", role: .destructive) {
                        showDeleteAllAlert = true
                    }
                }
                
                // MARK: — Legal Section
                Section(header: Text("settings.section.legal")) {
                    SettingsLink(label: "settings.link.terms", systemImage: "doc.text") {
                        UtilityManager.openURL(Constants.TERMS_OF_SERVICE_URL)
                    }
                    SettingsLink(label: "settings.link.privacy", systemImage: "lock.shield") {
                        UtilityManager.openURL(Constants.PRIVACY_POLICY_URL)
                    }
                }
                
                // MARK: — About Section
                Section(header: Text("settings.section.about")) {
                    SettingsLink(label: "settings.link.aboutUs", systemImage: "info.circle") {
                        UtilityManager.openURL(Constants.DEV_URL)
                    }
                    SettingsLink(label: "settings.link.instagram", systemImage: "camera") {
                        UtilityManager.openURL(Constants.INSTA_URL)
                    }
                    SettingsLink(label: "settings.link.rateUs", systemImage: "hand.thumbsup") {
                        UtilityManager.openURL(Constants.APP_URL)
                    }
                }
                
                HStack {
                    Label("settings.appVersion", systemImage: "gearshape")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(Bundle.main.appVersion) // Your app version
                        .foregroundColor(.secondary)
                }
                
                // MARK: — Community Message Footer
                Section {
                    Text("settings.footer.communityMessage")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .onAppear {
                if storeManager.isPro {
                    calculateAppStorageSize()
                }
            }
            .onChange(of: storeManager.isPro) { isPro in
                if isPro {
                    calculateAppStorageSize()
                }
            }
            .sheet(isPresented: $showPro) {
                ProScreen()
            }
            .alert("settings.alert.deleteAll.title", isPresented: $showDeleteAllAlert) {
                Button("settings.alert.deleteAll.button.delete", role: .destructive) {
                    PhotoManager.shared.deleteAllPhotos()
                    PhotoManager.shared.clearImageCaches()
                    CacheService.shared.clearAllCaches()
                    calculateAppStorageSize() // Recalculate size
                }
                Button("settings.alert.deleteAll.button.cancel", role: .cancel) {}
            } message: {
                Text("settings.alert.deleteAll.message")
            }
            .navigationBarTitle(Text("settings.title"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: — Helpers
    
    private func purchasePro() {
        showPro = true
    }
    
    private func lockedRow(label: LocalizedStringKey, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
            if !storeManager.isPro {
                Image(systemName: "lock.fill")
                    .foregroundColor(.gray)
                    .font(.caption2)
                    .padding(.leading, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !storeManager.isPro {
                purchasePro()
            }
        }
    }
    
    private func semiLockedToggle(_ label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        ZStack {
            Toggle(isOn: isOn) {
                HStack {
                    Text(label)
                    if !storeManager.isPro {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.gray)
                            .font(.caption2)
                    }
                }
            }
            .disabled(!storeManager.isPro)
            
            if !storeManager.isPro {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        purchasePro()
                    }
            }
        }
    }
    
    private func lockedToggle(_ label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(label)
                if !storeManager.isPro {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(.caption2)
                }
            }
        }
        .disabled(!storeManager.isPro)
        .onTapGesture {
            if !storeManager.isPro {
                isOn.wrappedValue = false
                purchasePro()
            }
        }
    }
    
    private func lockedButton(label: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(action: {
            if storeManager.isPro {
                action()
            } else {
                purchasePro()
            }
        }) {
            HStack {
                Label(label, systemImage: systemImage)
                    .foregroundColor(role == .destructive ? .red : .primary)
                Spacer()
                if !storeManager.isPro {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Storage Calculation
    
    private func calculateAppStorageSize() {
        DispatchQueue.global(qos: .background).async {
            let fileManager = FileManager.default
            let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            
            var totalSize: Int64 = 0
            
            if let cacheURL {
                totalSize += getDirectorySize(at: cacheURL) ?? 0
            }
            if let documentsURL {
                totalSize += getDirectorySize(at: documentsURL) ?? 0
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = .useAll
            formatter.countStyle = .file
            let formattedSize = formatter.string(fromByteCount: totalSize)
            
            DispatchQueue.main.async {
                self.appStorageSize = formattedSize
            }
        }
    }
    
    private func getDirectorySize(at url: URL) -> Int64? {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: []) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
                totalSize += Int64(size)
            } catch {
                print("Error getting file size for \(fileURL): \(error)")
            }
        }
        return totalSize
    }
}


// MARK: — Pro Card

fileprivate struct ProCard: View {
    let isPro: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("proCard.badge")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.yellow))
                Spacer()
            }
            
            Text("proCard.title")
                .font(.headline)
                .multilineTextAlignment(.leading)
                .foregroundColor(.white)
            
            Button(action: action) {
                Text(isPro ? "proCard.button.pro" : "proCard.button.upgrade")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isPro ? Color.gray : Color.white)
                    .foregroundColor(isPro ? .white : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 50))
            }
            .disabled(isPro)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.darkGray))
        )
    }
}

// MARK: — Settings Link (full-width, single-tap responsive)

fileprivate struct SettingsLink: View {
    let label: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading) // expand tap target
            .contentShape(Rectangle())                       // full-row hit area
        }
        .buttonStyle(.plain) // keep form styling, no extra chrome
    }
}

#Preview {
    SettingsView()
        .environmentObject(StoreManager.shared)
}
