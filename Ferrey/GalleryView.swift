import SwiftUI
import PhotosUI
import Kingfisher
import Zoomable

// MARK: - Gallery View
struct GalleryView: View {
    @ObservedObject var photoManager = PhotoManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var itemFrames: [String: CGRect] = [:]
    
    private let gridSpacing: CGFloat = 8
    private let sidePadding: CGFloat = 12
    private let columnCount: CGFloat = 3
    private var itemSize: CGFloat {
        let width = UIScreen.main.bounds.width - (sidePadding * 2) - (gridSpacing * (columnCount - 1))
        return floor(width / columnCount)
    }
    
    private var thumbnailProcessor: DownsamplingImageProcessor {
        let pixelSize = itemSize * UIScreen.main.scale
        return DownsamplingImageProcessor(size: CGSize(width: pixelSize, height: pixelSize))
    }
    
    private func cacheBustedURL(for photo: PhotoMetadata) -> URL {
        let baseURL = photoManager.filteredURL(for: photo.id, filter: photo.filter)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "v", value: "\(photo.lastUpdated.timeIntervalSince1970)")]
        return components.url!
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        if isSelecting {
                            Button("gallery.cancel") {
                                withAnimation { isSelecting = false; selectedIDs.removeAll() }
                            }
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
                        } else {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        if !isSelecting {
                            Text("gallery.title")
                                .font(.druk(size: 24))
                                .bold()
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        if isSelecting {
                            Button("gallery.share") { showShareSheet = true }
                                .foregroundColor(selectedIDs.isEmpty ? .gray : .white)
                                .font(.system(size: 17))
                                .disabled(selectedIDs.isEmpty)
                            
                            Spacer().frame(width: 12)
                            
                            Button("gallery.delete") { showDeleteConfirmation = true }
                                .foregroundColor(selectedIDs.isEmpty ? .gray : .white)
                                .font(.system(size: 17))
                                .disabled(selectedIDs.isEmpty)
                        } else {
                            Button(action: { isSelecting = true }) {
                                Image("select")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                            }
                            
                            Spacer().frame(width: 12)
                            
                            Button(action: { showPhotoPicker = true }) {
                                Image("import")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                            }
                        }
                    }
                    .frame(height: 30)
                    .padding()
                    
                    // Grid
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(itemSize), spacing: gridSpacing), count: Int(columnCount)),
                            spacing: gridSpacing
                        ) {
                            ForEach(photoManager.photos) { photo in
                                if isSelecting {
                                    ZStack(alignment: .topTrailing) {
                                        KFImage(cacheBustedURL(for: photo))
                                            .setProcessor(thumbnailProcessor)
                                            .placeholder { Rectangle().fill(Color.gray) }
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: itemSize, height: itemSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        
                                        Image(systemName: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.white)
                                            .font(.system(size: 28))
                                            .padding(6)
                                    }
                                    .onTapGesture {
                                        if selectedIDs.contains(photo.id) {
                                            selectedIDs.remove(photo.id)
                                        } else {
                                            selectedIDs.insert(photo.id)
                                        }
                                    }
                                } else {
                                    NavigationLink(
                                        destination: FullImageView(
                                            initialIndex: photoManager.photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                        )
                                    ) {
                                        KFImage(cacheBustedURL(for: photo))
                                            .setProcessor(thumbnailProcessor)
                                            .placeholder { Rectangle().fill(Color.gray) }
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: itemSize, height: itemSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, sidePadding)
                        .coordinateSpace(name: "grid")
                        .onPreferenceChange(GridItemFrameKey.self) { itemFrames = $0 }
                    }
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, matching: .images)
                .onChange(of: selectedPhotoItems) { newItems in
                    Task {
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data)?.fixedOrientation() {
                                PhotoManager.shared.lastCapturedExposure = 0.5
                                await MainActor.run {
                                    PhotoManager.shared.addPhoto(original: uiImage, filter: .normal, shouldAutoSave: false)
                                }
                            }
                        }
                        selectedPhotoItems.removeAll()
                    }
                }
                .confirmationDialog(
                    "gallery.selected.delete",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("gallery.delete", role: .destructive) {
                        photoManager.deletePhotos(ids: Array(selectedIDs))
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                    Button("gallery.cancel", role: .cancel) { }
                }
                .sheet(isPresented: $showShareSheet) {
                    let urls = selectedIDs.compactMap { id in
                        photoManager.photos.first { $0.id == id }.map { photoManager.filteredURL(for: $0.id, filter: $0.filter) }
                    }
                    ShareSheet(items: urls)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct GridItemFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Fullscreen Seamless
struct FullImageView: View {
    let initialIndex: Int
    
    @ObservedObject var photoManager = PhotoManager.shared
    @EnvironmentObject private var storeManager: StoreManager
    
    @State private var currentIndex: Int = 0
    @State private var selectedFilter: FilterType = .normal
    @State private var filterIntensity: Double = 1.0
    @State private var textureIntensity: Double = 0.0
    @State private var exposureIntensity: Double = 0.5
    
    @Environment(\.presentationMode) var presentationMode
    @State private var showFilterAdjustView = false
    @State private var showProScreen = false
    @State private var showDeleteConfirmation = false
    @State private var urlToShare: IdentifiableURL?
    @State private var showOriginal = false
    
    // MARK: - Aggressive Cache
    // We keep a buffer of images loaded to ensure instant swiping.
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var loadedOriginals: [String: UIImage] = [:]
    
    @State private var updateTask: Task<Void, Never>?
    @State private var filterRects: [FilterType: CGRect] = [:]
    @State private var ignoreScrollChange = false
    
    private let filters: [FilterType] = FilterType.allCases
    
    // MARK: - Optimized Background Downsampler
    
    /// Strictly non-isolated to run on background threads only.
    nonisolated private func downsample(url: URL, targetSize: CGSize) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        // Downsample to screen scale to save RAM, but keep quality high
        let maxDim = Int(max(targetSize.width, targetSize.height) * UIScreen.main.scale)
        
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false // We manage our own caching
        ]
        
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    
    // MARK: - Sliding Window Logic
    
    /// The core engine: Loads neighbors immediately so the user never sees a spinner.
    private func updateSlidingWindow(at index: Int) {
        guard !photoManager.photos.isEmpty else { return }
        
        // 1. Define the window: Current +/- 2
        // We prioritize: Current > Immediate Neighbors > Outer Neighbors
        let highPriorityIndices = [index, index + 1, index - 1]
        let lowPriorityIndices = [index + 2, index - 2]
        
        // 2. Clean up memory (Unload anything outside the window of +/- 2)
        let windowIndices = Set(highPriorityIndices + lowPriorityIndices)
        let validIDs = windowIndices.compactMap { i -> String? in
            guard i >= 0, i < photoManager.photos.count else { return nil }
            return photoManager.photos[i].id
        }
        let keepSet = Set(validIDs)
        
        // Remove images that are too far away to save RAM
        for key in loadedImages.keys where !keepSet.contains(key) {
            loadedImages.removeValue(forKey: key)
        }
        for key in loadedOriginals.keys where !keepSet.contains(key) {
            loadedOriginals.removeValue(forKey: key)
        }
        
        // 3. Trigger Loads
        
        // Load High Priority (Current + Immediate Neighbors)
        for i in highPriorityIndices {
            loadImage(at: i, priority: .userInitiated)
        }
        
        // Load Low Priority (Outer Neighbors - ready for the next swipe)
        for i in lowPriorityIndices {
            loadImage(at: i, priority: .utility)
        }
    }
    
    private func loadImage(at index: Int, priority: TaskPriority) {
        guard index >= 0, index < photoManager.photos.count else { return }
        let photo = photoManager.photos[index]
        
        // If already loaded, skip
        if loadedImages[photo.id] != nil { return }
        
        Task.detached(priority: priority) {
            let displaySize = await UIScreen.main.bounds.size
            
            // Try Edited URL first
            let url = await photoManager.filteredURL(for: photo.id, filter: photo.filter)
            if let img = downsample(url: url, targetSize: displaySize) {
                await MainActor.run {
                    // No animation here to prevent UI flicker during fast scrolling
                    loadedImages[photo.id] = img
                }
            } else {
                // Fallback to original
                let oURL = await photoManager.originalURL(for: photo.id)
                if let oImg = downsample(url: oURL, targetSize: displaySize) {
                    await MainActor.run {
                        loadedImages[photo.id] = oImg
                    }
                }
            }
        }
    }
    
    /// Loads the original image for the "Long Press" compare feature
    private func loadOriginal(at index: Int) {
        guard index >= 0, index < photoManager.photos.count else { return }
        let photo = photoManager.photos[index]
        if loadedOriginals[photo.id] != nil { return }
        
        Task.detached(priority: .userInitiated) {
            let displaySize = await UIScreen.main.bounds.size
            let oURL = await photoManager.originalURL(for: photo.id)
            if let oImg = downsample(url: oURL, targetSize: displaySize) {
                await MainActor.run { loadedOriginals[photo.id] = oImg }
            }
        }
    }
    
    // MARK: - UI
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Top Navigation Bar
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white)
                            .padding(.horizontal)
                    }
                    Spacer()
                    
                    // Filter Button
                    Button(action: {
                        if storeManager.isPro { showFilterAdjustView = true }
                        else { showProScreen = true }
                    }) {
                        Image("filter")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                    }
                    Spacer().frame(width: 12)
                    
                    // Export Button
                    Button(action: {
                        if !photoManager.photos.isEmpty {
                            let photoId = photoManager.photos[currentIndex].id
                            urlToShare = IdentifiableURL(url: photoManager.filteredURL(for: photoId, filter: selectedFilter))
                        }
                    }) {
                        Image("export")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                    }
                    Spacer().frame(width: 12)
                    
                    // Delete Button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing)
                .padding(.vertical)
                
                // MARK: - Main Image Pager
                TabView(selection: $currentIndex) {
                    ForEach(Array(photoManager.photos.enumerated()), id: \.offset) { index, photo in
                        ZStack {
                            // Check if we are showing Original (Long Press) or Edited
                            if let img = (showOriginal && index == currentIndex ? loadedOriginals[photo.id] : loadedImages[photo.id]) {
                                ZoomableImageView(image: img)
                                    .tag(index)
                            } else {
                                // Fallback placeholder only if something goes wrong
                                ProgressView()
                                    .tint(.white)
                                    .tag(index)
                            }
                        }
                        .ignoresSafeArea()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .gesture(
                    LongPressGesture(minimumDuration: 0.15)
                        .onChanged { _ in
                            // Load original immediately when user touches down
                            loadOriginal(at: currentIndex)
                            showOriginal = true
                        }
                        .onEnded { _ in showOriginal = false }
                )
                
                // MARK: - Filter Strip
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            if let rect = filterRects[selectedFilter] {
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(Color.white)
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rect)
                            }
                            
                            HStack(spacing: 24) {
                                ForEach(filters, id: \.self) { filter in
                                    Button(action: {
                                        if filter.isPro && !storeManager.isPro {
                                            showProScreen = true
                                            return
                                        }
                                        
                                        if selectedFilter == filter {
                                            if storeManager.isPro { showFilterAdjustView = true }
                                            else { showProScreen = true }
                                        } else {
                                            // Apply new filter to current image
                                            if let newImage = photoManager.updateFilter(for: photoManager.photos[currentIndex].id, newFilter: filter) {
                                                loadedImages[photoManager.photos[currentIndex].id] = newImage
                                            }
                                            selectedFilter = filter
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                filter.icon
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 60, height: 60)
                                                
                                                if filter.isPro && !storeManager.isPro {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.white)
                                                        .padding(8)
                                                        .background(Color.black.opacity(0.5))
                                                        .clipShape(Circle())
                                                }
                                            }
                                            
                                            Text(filter.title)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(selectedFilter == filter ? .black : .white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    GeometryReader { geo in
                                                        Color.clear.preference(
                                                            key: FilterRectKey.self,
                                                            value: [filter: geo.frame(in: .named("filterHStack"))]
                                                        )
                                                    }
                                                )
                                        }
                                    }
                                    .id(filter)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .coordinateSpace(name: "filterHStack")
                        .onPreferenceChange(FilterRectKey.self) { filterRects = $0 }
                    }
                    .onAppear {
                        proxy.scrollTo(selectedFilter, anchor: .center)
                    }
                    .onChange(of: selectedFilter) { _ in
                        if !ignoreScrollChange {
                            withAnimation { proxy.scrollTo(selectedFilter, anchor: .center) }
                        }
                        ignoreScrollChange = false
                    }
                }
                .frame(height: 110)
            }
        }
        .onAppear {
            currentIndex = min(initialIndex, max(0, photoManager.photos.count - 1))
            if !photoManager.photos.isEmpty {
                let photo = photoManager.photos[currentIndex]
                selectedFilter = (photo.filter.isPro && !storeManager.isPro) ? .normal : photo.filter
                filterIntensity = photo.filterIntensity
                textureIntensity = photo.textureIntensity
                exposureIntensity = photo.exposureIntensity
                
                // Start aggressive preloading immediately
                updateSlidingWindow(at: currentIndex)
            }
        }
        .onChange(of: currentIndex) { newIndex in
            guard !photoManager.photos.isEmpty else { return }
            
            let photo = photoManager.photos[newIndex]
            selectedFilter = (photo.filter.isPro && !storeManager.isPro) ? .normal : photo.filter
            filterIntensity = photo.filterIntensity
            textureIntensity = photo.textureIntensity
            exposureIntensity = photo.exposureIntensity
            
            // This kicks off the prefetch for Next/Next
            updateSlidingWindow(at: newIndex)
        }
        // Live Preview
        .onChange(of: filterIntensity) { _ in if showFilterAdjustView { schedulePreviewUpdate() } }
        .onChange(of: textureIntensity) { _ in if showFilterAdjustView { schedulePreviewUpdate() } }
        .onChange(of: exposureIntensity) { _ in if showFilterAdjustView { schedulePreviewUpdate() } }
        // Save on Dismiss Adjust
        .onChange(of: showFilterAdjustView) { newValue in
            if !newValue {
                updateTask?.cancel()
                if let newImage = photoManager.updateIntensities(
                    for: photoManager.photos[currentIndex].id,
                    filterIntensity: filterIntensity,
                    textureIntensity: textureIntensity,
                    exposureIntensity: exposureIntensity
                ) {
                    loadedImages[photoManager.photos[currentIndex].id] = newImage
                }
            }
        }
        .confirmationDialog("gallery.current.delete", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("gallery.delete", role: .destructive) {
                if !photoManager.photos.isEmpty {
                    photoManager.deletePhotos(ids: [photoManager.photos[currentIndex].id])
                    if photoManager.photos.isEmpty {
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        if currentIndex >= photoManager.photos.count {
                            currentIndex = photoManager.photos.count - 1
                        }
                        // Refresh window after delete
                        updateSlidingWindow(at: currentIndex)
                    }
                }
            }
            Button("gallery.cancel", role: .cancel) { }
        }
        .navigationBarHidden(true)
        .sheet(item: $urlToShare) { identifiableURL in
            ShareSheet(items: [identifiableURL.url])
        }
        .sheet(isPresented: $showFilterAdjustView) {
            ZStack {
                Color.darkGray.ignoresSafeArea()
                FilterAdjustView(
                    selectedFilter: $selectedFilter,
                    filterIntensity: $filterIntensity,
                    textureIntensity: $textureIntensity,
                    exposureIntensity: $exposureIntensity,
                    showFilterBar: $showFilterAdjustView
                )
            }
            .presentationDetents([.height(210)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProScreen) {
            ProScreen()
        }
    }
    
    // MARK: - Live Preview
    private func schedulePreviewUpdate() {
        updateTask?.cancel()
        updateTask = Task {
            do {
                try await Task.sleep(nanoseconds: 30_000_000) // 30ms
                guard !photoManager.photos.isEmpty else { return }
                let photo = photoManager.photos[currentIndex]
                let originalURL = photoManager.originalURL(for: photo.id)
                guard let original = UIImage(contentsOfFile: originalURL.path) else { return }
                
                let adjusted = FilterUtils.applyAdjustedFilter(
                    to: original,
                    with: selectedFilter,
                    filterIntensity: filterIntensity,
                    textureIntensity: textureIntensity,
                    exposureIntensity: exposureIntensity
                )
                try Task.checkCancellation()
                await MainActor.run {
                    if let img = adjusted { loadedImages[photo.id] = img }
                }
            } catch { }
        }
    }
}

// MARK: - Helpers

/// This helper completely avoids Kingfisher.
/// It takes a native UIImage and applies the Zoomable modifier.
struct ZoomableImageView: View {
    let image: UIImage
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .zoomable() // Uses the Zoomable package
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct FilterRectKey: PreferenceKey {
    static var defaultValue: [FilterType: CGRect] = [:]
    static func reduce(value: inout [FilterType: CGRect], nextValue: () -> [FilterType: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FilterAdjustView: View {
    @Binding var selectedFilter: FilterType
    @Binding var filterIntensity: Double
    @Binding var textureIntensity: Double
    @Binding var exposureIntensity: Double
    @Binding var showFilterBar: Bool
    
    var body: some View {
        ZStack {
            VStack {
                VStack {
                    HStack(spacing: 4) {
                        selectedFilter.icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        Text(selectedFilter.title)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 50).fill(Color.black))
                }
                .padding(.top)
                
                VStack {
                    filterRow(label: "editor.filter", value: $filterIntensity)
                    filterRow(label: "editor.texture", value: $textureIntensity)
                    filterRow(label: "editor.light", value: $exposureIntensity)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .background(.darkGray)
    }
    
    private func filterRow(label: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 70, alignment: .leading)
            
            Slider(value: value, in: 0...1)
                .frame(height: 30)
            
            Text("\(Int(value.wrappedValue * 100))%")
                .foregroundColor(.white)
                .font(.system(size: 14))
                .frame(width: 45, alignment: .trailing)
        }
    }
}

#Preview {
    GalleryView()
}

