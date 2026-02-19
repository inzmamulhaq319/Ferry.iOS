import SwiftUI
import Lottie
import SwiftRater

// MARK: - Main Content View
struct ContentView: View {
    
    // MARK: - Persisted Settings
    @AppStorage("gridOverlayEnabled") private var gridOverlayEnabled: Bool = false
    @AppStorage("livePreviewEnabled") private var livePreviewEnabled: Bool = false
    
    @AppStorage("flashOnEnabled") private var flashOnEnabled: Bool = false
    
    @AppStorage("hideLogoEnabled") private var hideLogoEnabled: Bool = false
    @AppStorage("lastFlashIndex") private var flashIndex: Int = 0
    @AppStorage("lastFilter") private var lastFilterRaw: String = "normal"
    @AppStorage("lastTimerIndex") private var timerIndex: Int = 0
    @AppStorage("lastAspectIndex") private var aspectIndex: Int = 0
    
    @AppStorage("seenFilters") private var seenFiltersData: Data = Data()
    
    @EnvironmentObject private var storeManager: StoreManager
    
    @StateObject private var cameraManager = CameraManager.shared
    @ObservedObject var photoManager = PhotoManager.shared
    
    @State private var showGallery = false
    @State private var showSettings = false
    @State private var showProScreen = false
    @State private var selectedFilter: FilterType = .normal
    @State private var showFilterBar = false
    
    @State private var showNewFilterPopup = false
    @State private var newFilters: [FilterType] = []
    
    private let flashAssetNames = ["flash_off", "flash_on", "flash_auto"]
    private let timerOptions: [Int] = [0, 3, 5]
    private let aspectOptions: [String] = ["3:4", "9:16"]
    
    private var latestPhotoInfo: (pathURL: URL, bustedURL: URL)? {
        guard let photo = photoManager.photos.first else { return nil }
        
        let baseURL = photoManager.filteredURL(for: photo.id, filter: photo.filter)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "v", value: "\(photo.lastUpdated.timeIntervalSince1970)")]
        
        guard let bustedURL = components.url else { return nil }
        
        return (pathURL: baseURL, bustedURL: bustedURL)
    }
    
    private let firstLaunchKey = "didRunFirstLaunchCleanup"
    private let lastDailyCleanupKey = "lastDailyCleanupAt"
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    
                    if !hideLogoEnabled || !storeManager.isPro {
                        Text("FERREY")
                            .font(.druk(size: 28))
                            .foregroundColor(.white)
                            .padding()
                    } else {
                        Spacer().frame(height: 24)
                    }
                    
                    HStack {
                        Button(action: {
                            flashIndex = (flashIndex + 1) % flashAssetNames.count
                            NotificationCenter.default.post(name: .setFlashMode, object: nil, userInfo: ["flashIndex": flashIndex])
                        }) {
                            Image(flashAssetNames[flashIndex])
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                        }
                        
                        Spacer()
                        
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .switchCamera, object: nil)
                        }) {
                            Image("rotate")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Image("menu")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.horizontal)
                    
                    
                    ZStack {
                        GeometryReader { geometry in
                            let parts = aspectOptions[aspectIndex].split(separator: ":")
                            let width = Double(parts[0]) ?? 1
                            let height = Double(parts[1]) ?? 1
                            let ratio = width / height
                            
                            ZStack {
                                CameraView(imageHandler: { rawImage in
                                    Task {
                                        PhotoManager.shared.addPhoto(original: rawImage, filter: selectedFilter)
                                    }
                                }, selectedFilter: selectedFilter, enableLiveFilter: livePreviewEnabled)
                                
                                if gridOverlayEnabled && storeManager.isPro {
                                    GridView()
                                }
                            }
                            .cornerRadius(30)
                            .animation(.linear, value: aspectIndex)
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                    
                    ZStack {
                        
                        HStack {
                            
                            HStack {
                                VStack(spacing: 10) {
                                    Button(action: {
                                        withAnimation(.spring()) { showFilterBar.toggle() }
                                    }) {
                                        selectedFilter.icon
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundColor(.white)
                                            .padding(.all, 4)
                                            .frame(width: 55, height: 55)
                                            .background(Color(.darkGray))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .clipped()
                                    }
                                    
                                    NavigationLink(destination: GalleryView()) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color(.darkGray))
                                                .frame(width: 55, height: 55)
                                            
                                            if let info = latestPhotoInfo, let ui = UIImage(contentsOfFile: info.pathURL.path) {
                                                Image(uiImage: ui)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 55, height: 55)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                                    .blurReplaceCompatTransition()
                                                    .id(info.bustedURL)
                                            }
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .takePhoto, object: nil)
                                SwiftRater.incrementSignificantUsageCount()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(.darkGray))
                                        .frame(width: 120, height: 120)
                                    
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                ZStack {
                                    VStack {
                                        if cameraManager.isBackCamera && cameraManager.zoomFactors.count > 1 {
                                            // Single button that cycles through available zoom levels
                                            Button(action: {
                                                let currentZoom = cameraManager.currentZoomFactor
                                                let availableZooms = cameraManager.zoomFactors.sorted()
                                                
                                                // Find the index of the preset closest to the current zoom
                                                // We use a small tolerance to "snap" to a preset if we are very close
                                                let tolerance = 0.1
                                                
                                                var nextIndex = 0
                                                
                                                if let exactIndex = availableZooms.firstIndex(where: { abs($0 - currentZoom) < tolerance }) {
                                                    // We are at a preset, go to the next one
                                                    nextIndex = (exactIndex + 1) % availableZooms.count
                                                } else {
                                                    // We are at a custom zoom (pinch), find the next larger preset
                                                    // If we are larger than all, wrap to the first (smallest)
                                                    if let firstLarger = availableZooms.firstIndex(where: { $0 > currentZoom }) {
                                                        nextIndex = firstLarger
                                                    } else {
                                                        nextIndex = 0 // Wrap to start
                                                    }
                                                }
                                                
                                                let newZoom = availableZooms[nextIndex]
                                                NotificationCenter.default.post(name: .setZoom, object: nil, userInfo: ["zoom": newZoom])
                                                
                                            }) {
                                                Text(cameraManager.currentZoomFactorDisplayText)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        } else {
                                            Text("1x")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                        Rectangle().fill(.gray).frame(width: 20, height: 1)
                                        Spacer()
                                        
                                        Button(action: {
                                            timerIndex = (timerIndex + 1) % timerOptions.count
                                            NotificationCenter.default.post(name: .cycleTimer, object: nil)
                                        }) {
                                            if timerOptions[timerIndex] == 0 {
                                                Image("timer")
                                                    .renderingMode(.template)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .foregroundColor(.white)
                                                    .frame(width: 20, height: 20)
                                            } else {
                                                Text("\(timerOptions[timerIndex])s")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        
                                        Spacer()
                                        Rectangle().fill(.gray).frame(width: 20, height: 1)
                                        Spacer()
                                        
                                        Button(action: {
                                            aspectIndex = (aspectIndex + 1) % aspectOptions.count
                                        }) {
                                            Text(aspectOptions[aspectIndex])
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.white)
                                                .frame(width: 34)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical)
                                }
                                .background(Color(.darkGray))
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .clipped()
                            }
                        }
                        .padding(.horizontal)
                        .padding()
                    }
                }
                
                if showNewFilterPopup {
                    NewFilterPopupView(
                        isPresented: $showNewFilterPopup,
                        selectedFilter: $selectedFilter,
                        newFilters: newFilters,
                        onDismiss: {
                            // After the popup is dismissed, update the saved list to the current total.
                            let allCurrentRawValues = FilterType.allCases.map { $0.rawValue }
                            if let data = try? JSONEncoder().encode(allCurrentRawValues) {
                                seenFiltersData = data
                            }
                        }
                    )
                }
            }
            .background(.black)
            .sheet(isPresented: $showFilterBar) {
                ZStack {
                    Color.darkGray.ignoresSafeArea()
                    FilterBarView(selectedFilter: $selectedFilter, showFilterBar: $showFilterBar)
                        .ignoresSafeArea()
                }
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showProScreen) {
                ProScreen()
            }
            .onAppear {
                
                // 0) Configure safe size limits to avoid ballooning
                CacheService.shared.configureCacheLimits(
                    urlCacheMemoryMB: 8,
                    urlCacheDiskMB: 32,
                    kingfisherDiskLimitMB: 64
                )
                
                // 1) First launch cleanup
                let didRun = UserDefaults.standard.bool(forKey: firstLaunchKey)
                if !didRun {
                    CacheService.shared.clearAllCaches()
                    // Also clear Kingfisher/URL caches via PhotoManager if you want redundancy:
                    PhotoManager.shared.clearImageCaches()
                    UserDefaults.standard.set(true, forKey: firstLaunchKey)
                }
                
                // 2) Once-a-day hygiene (keeps things tidy over time)
                let now = Date()
                if shouldRunDailyCleanup(now: now) {
                    CacheService.shared.trimCaches()
                    PhotoManager.shared.clearImageCaches()
                    UserDefaults.standard.set(now, forKey: lastDailyCleanupKey)
                }
                
                let allCurrentFilterRawValues = Set(FilterType.allCases.map { $0.rawValue })
                
                let seenFilters: Set<String>
                if let decodedFilters = try? JSONDecoder().decode(Set<String>.self, from: seenFiltersData) {
                    seenFilters = decodedFilters
                } else {
                    seenFilters = Set()
                }
                
                if seenFilters.isEmpty {
                    if let data = try? JSONEncoder().encode(allCurrentFilterRawValues) {
                        seenFiltersData = data
                    }
                } else {
                    let newFilterRawValues = allCurrentFilterRawValues.subtracting(seenFilters)
                    
                    if !newFilterRawValues.isEmpty {
                        let newlyAddedFilters = newFilterRawValues.compactMap { FilterType(rawValue: $0) }
                        
                        if !newlyAddedFilters.isEmpty {
                            self.newFilters = newlyAddedFilters
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation {
                                    self.showNewFilterPopup = true
                                }
                            }
                        }
                    }
                }
                
                let lastFilter = FilterType(rawValue: lastFilterRaw) ?? .normal
                if lastFilter.isPro && !storeManager.isPro {
                    selectedFilter = .normal
                } else {
                    selectedFilter = lastFilter
                }
                if flashOnEnabled {
                    flashIndex = 1
                }
                NotificationCenter.default.post(name: .setFlashMode, object: nil, userInfo: ["flashIndex": flashIndex])
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                CacheService.shared.trimCaches()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                CacheService.shared.trimCaches()
            }
            .onChange(of: selectedFilter) { newValue in
                if newValue.isPro && !storeManager.isPro {
                    selectedFilter = .normal
                    showProScreen = true
                } else {
                    lastFilterRaw = newValue.rawValue
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func shouldRunDailyCleanup(now: Date) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastDailyCleanupKey) as? Date else { return true }
        return now.timeIntervalSince(last) > 24 * 60 * 60
    }
}

// MARK: - New Filter Popup View
struct NewFilterPopupView: View {
    @Binding var isPresented: Bool
    @Binding var selectedFilter: FilterType
    
    let newFilters: [FilterType]
    let onDismiss: () -> Void
    
    @State private var pulse = false
    @State private var selectedNewFilter: FilterType
    
    init(isPresented: Binding<Bool>, selectedFilter: Binding<FilterType>, newFilters: [FilterType], onDismiss: @escaping () -> Void) {
        self._isPresented = isPresented
        self._selectedFilter = selectedFilter
        self.newFilters = newFilters
        self.onDismiss = onDismiss
        self._selectedNewFilter = State(initialValue: newFilters.first ?? .normal)
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 16) {
                
                LottieView(animation: .asset("new_filter"))
                    .playing()
                    .looping()
                    .scaledToFit()
                    .frame(height: 24)
                
                TabView(selection: $selectedNewFilter) {
                    ForEach(newFilters, id: \.self) { filter in
                        VStack(spacing: 12) {
                            
                            VStack {
                                
                                filter.icon
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                
                                Text(filter.title.uppercased())
                                    .font(.druk(size: 18))
                                    .foregroundColor(.white)
                            }
                            
                            TabView {
                                ForEach(filter.samples, id: \.self) { sampleImageName in
                                    Image(sampleImageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .clipped()
                                }
                            }
                            .tabViewStyle(PageTabViewStyle())
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .tag(filter)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 500)
                
                Button(action: {
                    selectedFilter = selectedNewFilter
                    dismiss()
                }) {
                    Text("Try NOW")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.vertical, 15)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(15)
                        .animation(.easeInOut, value: selectedNewFilter)
                }
            }
            .padding(24)
            .background(Color(.darkGray))
            .cornerRadius(30)
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private func dismiss() {
        withAnimation {
            isPresented = false
        }
        onDismiss()
    }
}


struct GridView: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            Path { path in
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: height))
                path.move(to: CGPoint(x: 2 * width / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * width / 3, y: height))
                
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                path.move(to: CGPoint(x: 0, y: 2 * height / 3))
                path.addLine(to: CGPoint(x: width, y: 2 * height / 3))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
    }
}

private extension View {
    @ViewBuilder
    func blurReplaceCompatTransition() -> some View {
        self.transition(.opacity)
    }
}

#Preview {
    ContentView()
        .environmentObject(StoreManager.shared)
}
