import Foundation
import StoreKit

enum ProductID {
    static let monthly = Constants.MONTHLY
    static let lifetime = Constants.LIFETIME
}

enum StoreError: Error {
    case failedVerification
}

@MainActor
class StoreManager: ObservableObject {
    
    static let shared = StoreManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool = false
    
    private var transactionListener: Task<Void, Error>? = nil
    
    // 🔹 Key for caching the pro status in UserDefaults
    private let proStatusKey = "isProUser"
    
    private init() {
        print("🛒 StoreManager: Initializing...")
        
        // 🔹 1. Read the cached pro status immediately on initialization
        self.isPro = UserDefaults.standard.bool(forKey: proStatusKey)
        print("🛒 StoreManager: Initialized with cached isPro status: \(self.isPro)")
        
        transactionListener = Task.detached {
            print("🛒 StoreManager: Transaction listener started.")
            await self.listenForTransactions()
        }
    }
    
    deinit {
        print("🛒 StoreManager: Cancelling transaction listener.")
        transactionListener?.cancel()
    }
    
    /// **(NEW)** Checks the App Store for all current entitlements to sync the user's status.
    /// This is the key function to call on app launch.
    /// Checks the App Store for all current entitlements to sync the user's status.
    func updateCustomerProductStatus() async {
        print("🛒 StoreManager: 🔄 Starting full sync of customer entitlements...")
        
        var validIDs: Set<String> = []
        
        // Iterate through all of the user's current entitlements.
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    // If there's no revocation date, the purchase is active.
                    print("🛒 StoreManager: ➕ Found active entitlement for product: \(transaction.productID)")
                    validIDs.insert(transaction.productID)
                } else {
                    // The purchase was revoked or refunded.
                    print("🛒 StoreManager: ➖ Found revoked entitlement for product: \(transaction.productID)")
                }
            }
        }
        
        self.purchasedProductIDs = validIDs
        
        // After syncing, update the isPro flag and cache the result.
        await updateProStatus()
        print("🛒 StoreManager: ✅ Full sync of entitlements complete.")
    }
    
    func fetchProducts() async {
        print("🛒 StoreManager: Fetching products from App Store...")
        do {
            let storeProducts = try await Product.products(for: [ProductID.monthly, ProductID.lifetime])
            print("🛒 StoreManager: ✅ Successfully fetched \(storeProducts.count) products.")
            self.products = storeProducts
        } catch {
            print("🛒 StoreManager: ❌ Failed to fetch products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws {
        print("🛒 StoreManager: ▶️ Initiating purchase for product: \(product.id)")
        let result = try await product.purchase()
        
        switch result {
            case .success(let verification):
                print("🛒 StoreManager: ✅ Purchase successful, verifying transaction...")
                let transaction = try checkVerified(verification)
                print("🛒 StoreManager: ✅ Verification successful for transaction ID \(transaction.id). Processing...")
                
                // Add the new purchase to our set
                self.purchasedProductIDs.insert(transaction.productID)
                // Update the pro status
                await self.updateProStatus()
                // Finish the transaction
                await transaction.finish()
                
                print("🛒 StoreManager: ✅ Transaction finished for product: \(transaction.productID).")
            case .userCancelled:
                print("🛒 StoreManager: ⚠️ User cancelled the purchase.")
            case .pending:
                print("🛒 StoreManager: ⏳ Purchase is pending.")
            @unknown default:
                print("🛒 StoreManager: ❓ Unknown purchase result.")
        }
    }
    
    func restorePurchases() async {
        print("🛒 StoreManager: 🔄 Attempting to restore purchases...")
        try? await AppStore.sync()
        print("🛒 StoreManager: ✅ Restore check completed.")
    }
    
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                print("🛒 StoreManager (Listener): 📩 Received transaction update.")
                let transaction = try checkVerified(result)
                
                // Perform a full resync to handle any new purchases, refunds, etc.
                await updateCustomerProductStatus()
                
                await transaction.finish()
                print("🛒 StoreManager (Listener): ✅ Processed transaction ID \(transaction.id).")
            } catch {
                print("🛒 StoreManager (Listener): ❌ Transaction verification failed: \(error)")
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
            case .unverified:
                print("🛒 StoreManager: ❌ Transaction verification failed.")
                throw StoreError.failedVerification
            case .verified(let safe):
                print("🛒 StoreManager: ✅ Transaction is verified.")
                return safe
        }
    }
    
    /// **(MODIFIED)** This function now ONLY updates the `isPro` flag based on the current `purchasedProductIDs`.
    private func updateProStatus() async {
        print("🛒 StoreManager: ⚙️ Setting isPro flag...")
        print("🛒 StoreManager: Current purchased IDs: \(self.purchasedProductIDs)")
        
        let hasProEntitlement = !self.purchasedProductIDs.isEmpty
        print("🛒 StoreManager: Does user have pro entitlement? \(hasProEntitlement)")
        
        if self.isPro != hasProEntitlement {
            self.isPro = hasProEntitlement
            UserDefaults.standard.set(hasProEntitlement, forKey: proStatusKey)
            print("🛒 StoreManager: 🚀 User isPro status changed to: \(self.isPro)")
        } else {
            print("🛒 StoreManager: User isPro status remains: \(self.isPro)")
        }
    }
}
