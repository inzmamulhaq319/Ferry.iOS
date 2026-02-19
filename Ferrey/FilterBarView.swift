//
//  FilterBarView.swift
//  Ferrey
//
//  Created by Junaid on 10/08/2025.
//

import SwiftUI


struct FilterBarView: View {
    @Binding var selectedFilter: FilterType
    @Binding var showFilterBar: Bool
    
    @StateObject private var storeManager = StoreManager.shared
    @State private var showProScreen = false
    @State private var showExamples = false
    
    let filters: [FilterType] = FilterType.allCases
    
    @State private var filterRects: [FilterType: CGRect] = [:]
    @State private var didInitialScroll = false   // ensures we scroll only once
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    
                    Text("filter.sample")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white)
                }
                .onTapGesture { showExamples = true }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 50).fill(Color.black))
            }
            .padding(.top)
            .padding(.horizontal)
            .padding(.horizontal)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        if let rect = filterRects[selectedFilter] {
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.white)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rect)
                        }
                        
                        HStack(spacing: 24) {
                            ForEach(filters, id: \.self) { filter in
                                Button(action: {
                                    // change selection without auto-scrolling
                                    if filter.isPro && !storeManager.isPro {
                                        showProScreen = true
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            selectedFilter = filter
                                        }
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
                                            .padding(.vertical, 4)
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
                                .id(filter) // needed only for the initial one-time scroll
                            }
                        }
                        .padding(.horizontal)
                    }
                    .coordinateSpace(name: "filterHStack")
                    .onPreferenceChange(FilterRectKey.self) { prefs in
                        filterRects = prefs
                        // One-time centering after we know frames/ids
                        if !didInitialScroll {
                            didInitialScroll = true
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    proxy.scrollTo(selectedFilter, anchor: .center)
                                }
                            }
                        }
                    }
                }
                // IMPORTANT: No onChange(selectedFilter) here — no auto-scroll on tap
            }
        }
        .clipped()
        .background(.darkGray)
        .sheet(isPresented: $showExamples) {
            SamplesView(initialFilter: selectedFilter)
                .presentationDetents([.fraction(0.94)])
                .presentationDragIndicator(.visible)
                .environmentObject(storeManager)
        }
        .sheet(isPresented: $showProScreen) {
            ProScreen()
        }
    }
}


struct SamplesView: View {
    
    let initialFilter: FilterType
    @State private var previewFilter: FilterType
    
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.presentationMode) var presentationMode
    @State private var showProScreen = false
    
    let filters: [FilterType] = FilterType.allCases
    @State private var filterRects: [FilterType: CGRect] = [:]
    @State private var didInitialScroll = false
    
    let horizontalPadding: CGFloat = 16
    let verticalPadding: CGFloat = 4
    var imageWidth: CGFloat {
        UIScreen.main.bounds.width - (horizontalPadding * 2)
    }
    var imageHeight: CGFloat {
        imageWidth * 16 / 12
    }
    
    init(initialFilter: FilterType) {
        self.initialFilter = initialFilter
        self._previewFilter = State(initialValue: initialFilter)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top filter bar
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        if let rect = filterRects[previewFilter] {
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.white)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rect)
                        }
                        
                        HStack(spacing: 24) {
                            ForEach(filters, id: \.self) { filter in
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        previewFilter = filter
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
                                            .foregroundColor(previewFilter == filter ? .black : .white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: FilterRectKey.self,
                                                        value: [filter: geo.frame(in: .named("samplesFilterHStack"))]
                                                    )
                                                }
                                            )
                                    }
                                }
                                .id(filter)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .coordinateSpace(name: "samplesFilterHStack")
                    .onPreferenceChange(FilterRectKey.self) { prefs in
                        filterRects = prefs
                        if !didInitialScroll {
                            didInitialScroll = true
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    proxy.scrollTo(previewFilter, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 110)
            .padding(.top, 24)
            
            // Samples
            ZStack {
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        
                        ForEach(previewFilter.samples, id: \.self) { imageName in
                            Image(imageName) // Loads from Asset Catalog
                                .resizable()
                                .scaledToFill()
                                .frame(width: imageWidth, height: imageHeight)
                                .clipped()
                                .padding(.horizontal, horizontalPadding)
                                .padding(.bottom, verticalPadding)
                        }
                        
                    }
                    
                    Spacer().frame(height: 100)
                }
                
                VStack {
                    Spacer()
                    
                    if previewFilter.isPro && !storeManager.isPro {
                        Button("proCard.button.upgrade") {
                            showProScreen = true
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 50))
                        
                    }
                }
                
            }
            
        }
        .background(Color(.darkGray).ignoresSafeArea())
        .sheet(isPresented: $showProScreen) {
            ProScreen()
        }
    }
}



#Preview {
    FilterBarView(
        selectedFilter: .constant(.normal),
        showFilterBar: .constant(true)
    )
}
