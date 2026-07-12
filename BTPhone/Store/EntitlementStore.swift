import StoreKit
import SwiftUI
import os

/// One non-consumable "lifetime unlock" (Family Sharing enabled) gates the
/// 15-minute free-session limit.
///
/// The gate fails OPEN: the limit applies only when the App Store positively
/// knows the product (products(for:) returned it) and this Apple ID has no
/// entitlement. If the store is unreachable or the product isn't configured
/// yet (dev builds before App Store Connect setup), nothing is limited — a
/// paying rider in airplane mode must never be locked out, and
/// currentEntitlements reads a local cache so ownership works offline anyway.
@MainActor
final class EntitlementStore: ObservableObject {
    static let lifetimeProductID = "com.wahdany.twoup.lifetime"
    private static let log = Logger(subsystem: "com.wahdany.twoup", category: "Store")

    enum Gate {
        case unknown
        case unlocked
        case locked
        case storeUnavailable
    }

    @Published private(set) var gate: Gate = .unknown
    @Published private(set) var product: Product?
    @Published var purchaseError: String?

    var limitsSessions: Bool { gate == .locked }

    private var updatesTask: Task<Void, Never>?
    // MainActor reentrancy lets refresh() calls interleave across the two
    // awaits; only the newest call may write the outcome, or a stale fetch
    // could overwrite .unlocked with .locked for a paying user.
    private var refreshGeneration = 0

    /// Call once at launch, before any purchase UI. Family members'
    /// purchases, Ask-to-Buy approvals, refunds, and revocations arrive only
    /// through Transaction.updates, and unfinished transactions are
    /// redelivered every launch until finished.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refresh()
            }
        }
        Task {
            for await result in Transaction.unfinished {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
            await self.refresh()
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        if await ownsLifetime() {
            gate = .unlocked
            return
        }
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            if let first = products.first {
                // An entitlement may have landed while the network call was
                // in flight (Ask to Buy approval, family purchase).
                let owned = await ownsLifetime()
                guard generation == refreshGeneration else { return }
                product = first
                gate = owned ? .unlocked : .locked
            } else {
                // Empty array is not an error: the product simply doesn't
                // exist in App Store Connect (yet). Fail open.
                guard generation == refreshGeneration else { return }
                Self.log.info("store: product not configured, failing open")
                gate = .storeUnavailable
            }
        } catch {
            guard generation == refreshGeneration else { return }
            Self.log.error("store: products(for:) failed: \(error, privacy: .public)")
            gate = .storeUnavailable
        }
    }

    /// A verified, unrevoked entitlement — includes family-shared purchases
    /// (ownershipType .familyShared) with no extra code. Revocations (refund,
    /// purchaser leaves the family group) disappear from this sequence and
    /// also arrive via Transaction.updates, which re-runs refresh().
    private func ownsLifetime() async -> Bool {
        for await result in Transaction.currentEntitlements(for: Self.lifetimeProductID) {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// PurchaseAction comes from @Environment(\.purchase) so the confirmation
    /// sheet anchors to the caller's scene without UIKit plumbing.
    func buy(using purchase: PurchaseAction) async {
        guard let product else { return }
        purchaseError = nil
        do {
            switch try await purchase(product) {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refresh()
            case .pending:
                // Ask to Buy: the approved transaction lands via
                // Transaction.updates whenever the parent gets to it.
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// App Review requires an explicit restore control for non-consumables.
    /// Only call on user tap: sync() can prompt for App Store sign-in.
    func restore() async {
        do {
            try await AppStore.sync()
            purchaseError = nil
        } catch {
            purchaseError = error.localizedDescription
        }
        await refresh()
    }
}
