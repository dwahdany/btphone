import StoreKit
import SwiftUI

/// Shown when a free session hits the 15-minute limit, or from the unlock
/// row. Buying is optional — free sessions restart forever.
struct PaywallView: View {
    @EnvironmentObject private var store: EntitlementStore
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss

    /// True when the sheet appeared because the running session just ended.
    let sessionEnded: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "infinity.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .padding(.top, 28)

            (sessionEnded ? Text("Your free session just ended") : Text("Unlock unlimited sessions"))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Free sessions run for 15 minutes — restart as often as you like. Or buy once and never think about it again: Family Sharing covers both phones with one purchase. No subscription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let product = store.product {
                Button {
                    Task {
                        await store.buy(using: purchase)
                        if store.gate == .unlocked { dismiss() }
                    }
                } label: {
                    buyLabel(price: product.displayPrice)
                }
                .buttonStyle(.plain)
            } else if IntercomController.demoScene != nil {
                // Screenshot rig: StoreKit products don't load in the
                // Simulator; render the button with the real price text.
                buyLabel(price: Locale.current.identifier.hasPrefix("de") ? "9,99 €" : "€9.99")
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Restore Purchases") {
                Task {
                    await store.restore()
                    if store.gate == .unlocked { dismiss() }
                }
            }
            .font(.subheadline)

            Button("Not now") { dismiss() }
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }

    private func buyLabel(price: String) -> some View {
        Text("Unlock forever — \(price)")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 14))
    }
}
