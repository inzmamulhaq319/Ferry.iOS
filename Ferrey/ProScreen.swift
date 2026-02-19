//
//  ProScreen.swift
//  Ferrey
//
//  Created by Junaid on 03/08/2025.
//

import SwiftUI
import StoreKit

// NEW: Enum to manage the selected purchase option.
enum PurchaseOption {
    case monthly
    case lifetime
}

struct ProScreen: View {
    
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var storeManager: StoreManager
    
    // State to hold the fetched products from the App Store.
    @State private var monthlyProduct: Product?
    @State private var lifetimeProduct: Product?
    @State private var isPurchasing = false
    
    // State to manage the loading view of the purchase buttons.
    @State private var isLoadingProducts = true
    
    // NEW: State to track the currently selected purchase option. Defaults to monthly.
    @State private var selectedOption: PurchaseOption = .monthly
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                }
                
                VStack(spacing: 0) {
                    
                    
                    Spacer(minLength: 30)
                    
                    VStack(spacing: 2) {
                        Text("FERREY")
                            .font(.druk(size: 30))
                            .kerning(4)
                            .foregroundColor(.white)
                        Text("proScreen.proBadge")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 20)
                    }
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 18) {
                        featureRow(image: "sparkles", text: "proScreen.feature1")
                        featureRow(image: "camera", text: "proScreen.feature2")
                        featureRow(image: "arrow.triangle.2.circlepath", text: "proScreen.feature3")
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    
                    Spacer()
                    
                    // MODIFIED: Replaced the two buttons with selectable options and a single purchase button.
                    VStack(spacing: 14) {
                        
                        // Monthly Selection Option
                        selectionOptionView(for: monthlyProduct, option: .monthly, isLoading: isLoadingProducts)
                        
                        // Lifetime Selection Option
                        selectionOptionView(for: lifetimeProduct, option: .lifetime, isLoading: isLoadingProducts)
                        
                        // Single Purchase Button
                        Button(action: {
                            if selectedOption == .monthly, let product = monthlyProduct {
                                purchase(product: product)
                            } else if selectedOption == .lifetime, let product = lifetimeProduct {
                                purchase(product: product)
                            }
                        }) {
                            Text(selectedOption == .monthly ? "proScreen.trialButton" : "proScreen.purchaseButton")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    Group {
                                        if selectedOption == .monthly {
                                            LinearGradient(gradient: Gradient(colors: [Color.purple, Color.blue]),
                                                           startPoint: .leading,
                                                           endPoint: .trailing)
                                        } else {
                                            LinearGradient(gradient: Gradient(colors: [Color.purple, Color.blue]),
                                                           startPoint: .leading,
                                                           endPoint: .trailing)
                                        }
                                    }
                                )
                                .cornerRadius(100)
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .disabled(isPurchasing)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(FilterType.allCases.filter { $0 != .normal }, id: \.self) { filter in
                                VStack(spacing: 4) {
                                    ZStack {
                                        filter.icon
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        if filter.isPro {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Color.black.opacity(0.5))
                                                .clipShape(Circle())
                                        }
                                    }
                                    Text(filter.title)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(width: 50)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                    
                    VStack(spacing: 4) {
                        Text("proScreen.paymentDisclaimer")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        
                        HStack(spacing: 18) {
                            Button("proScreen.termsLink") {
                                UtilityManager.openURL(Constants.TERMS_OF_SERVICE_URL)
                            }
                            Button("proScreen.privacyLink") {
                                UtilityManager.openURL(Constants.PRIVACY_POLICY_URL)
                            }
                            Button("proScreen.restoreLink") {
                                Task {
                                    isPurchasing = true
                                    await storeManager.restorePurchases()
                                    isPurchasing = false
                                }
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 18)
                }
                .task {
                    await storeManager.fetchProducts()
                    self.monthlyProduct = storeManager.products.first(where: { $0.id == ProductID.monthly })
                    self.lifetimeProduct = storeManager.products.first(where: { $0.id == ProductID.lifetime })
                    isLoadingProducts = false
                }
                .onChange(of: storeManager.isPro) { isPro in
                    if isPro {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.automatic)
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
        
    }
    
    func purchase(product: Product) {
        Task {
            isPurchasing = true
            do {
                try await storeManager.purchase(product)
            } catch {
                print("Purchase failed: \(error)")
            }
            isPurchasing = false
        }
    }
    
    @ViewBuilder
    private func featureRow(image: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: image)
            Text(text)
        }
    }
    
    // NEW: Replaces the old purchaseButton. This view displays product info and handles selection.
    @ViewBuilder
    private func selectionOptionView(for product: Product?, option: PurchaseOption, isLoading: Bool) -> some View {
        Button(action: {
            // This button's only job is to change the selection state.
            selectedOption = option
        }) {
            HStack {
                if isLoading {
                    Text("proScreen.loading")
                } else if let product = product {
                    if product.id == ProductID.monthly {
                        Text("\(product.displayPrice) / \(Text("proScreen.monthly"))")
                    } else if product.id == ProductID.lifetime {
                        Text("\(product.displayPrice) \(Text("proScreen.lifetime"))")
                    }
                } else {
                    Text("proScreen.unavailable")
                }
                Spacer()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                // Show a border if this option is selected.
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedOption == option ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .disabled(isLoading || product == nil)
    }
}


#Preview {
    ProScreen()
        .environmentObject(StoreManager.shared)
}
