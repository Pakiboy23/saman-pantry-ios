import SwiftUI
import VisionKit
import SwiftData

struct ScannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query private var products: [Product]
    @Query private var allItems: [Item]

    @State private var scannedBarcode: String?
    @State private var foundProduct: FoundProduct?
    @State private var isLooking = false
    @State private var showAddItem = false
    @State private var showPaywall = false
    @State private var resultName = ""
    @State private var scannerActive = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    // Full-bleed camera
                    if scannerActive {
                        BarcodeScannerRepresentable { barcode in
                            scannerActive = false
                            handle(barcode: barcode)
                        }
                        .ignoresSafeArea()
                    }

                    // Amber corner brackets
                    ScannerCornerBrackets(color: .samanAccent)
                        .ignoresSafeArea()

                    // Dim overlay when not scanning
                    if !scannerActive {
                        Color.black.opacity(0.45).ignoresSafeArea()
                    }

                    // Top wordmark
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Saman")
                                    .font(.cormorant(24))
                                    .foregroundStyle(.white)
                                Text("Tap a barcode to scan")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Saman.Space.md)
                        .padding(.top, 8)
                        Spacer()
                    }

                    // Result / status card at bottom
                    VStack {
                        Spacer()
                        resultCard
                            .padding(.horizontal, Saman.Space.md)
                            .padding(.bottom, 48)
                    }

                } else {
                    SamanEmptyState(
                        emoji: "📷",
                        title: "Scanner unavailable",
                        message: "This device doesn't support the camera scanner."
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddItem, onDismiss: resetScanner) {
                AddItemView(prefillBarcode: scannedBarcode, prefillName: resultName)
            }
            .sheet(isPresented: $showPaywall) { SamanPaywallView() }
        }
    }

    // MARK: - Result card

    @ViewBuilder
    private var resultCard: some View {
        if isLooking {
            HStack(spacing: 12) {
                ProgressView().tint(Color.samanAccent)
                Text("Looking up product…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.samanPrimary)
                Spacer()
            }
            .padding(16)
            .background(Color.samanCard, in: RoundedRectangle(cornerRadius: Saman.Radius.lg))
        } else if let barcode = scannedBarcode {
            VStack(spacing: 14) {
                // Product info
                HStack(spacing: 12) {
                    Text(foundProduct != nil ? "🛍️" : "❓")
                        .font(.system(size: 28))
                        .frame(width: 52, height: 52)
                        .background(Color.samanDeep, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        if let product = foundProduct {
                            Text(product.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.samanPrimary)
                            if let brand = product.brand {
                                Text(brand)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.samanMuted)
                            }
                        } else {
                            Text("Unknown product")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.samanPrimary)
                            Text(barcode)
                                .font(.samanMono(12))
                                .foregroundStyle(Color.samanMuted)
                        }
                    }
                    Spacer()
                }

                // Actions
                HStack(spacing: 10) {
                    Button("Scan Again") { resetScanner() }
                        .buttonStyle(SamanSecondaryButtonStyle())
                    Button("Add to Pantry") {
                        if allItems.count >= 30 && !appEnv.purchases.isPro {
                            showPaywall = true
                        } else {
                            showAddItem = true
                        }
                    }
                    .buttonStyle(SamanPrimaryButtonStyle())
                }
            }
            .padding(16)
            .background(Color.samanCard, in: RoundedRectangle(cornerRadius: Saman.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Saman.Radius.lg).stroke(Color.samanBorder, lineWidth: 1))
        } else {
            // Hint
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .foregroundStyle(Color.samanAccent)
                Text("Point at a barcode and tap to scan")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.samanSecondary)
            }
            .padding(14)
            .background(Color.samanCard.opacity(0.92), in: RoundedRectangle(cornerRadius: Saman.Radius.md))
        }
    }

    // MARK: - Logic

    private func handle(barcode: String) {
        scannedBarcode = barcode
        if let local = products.first(where: { $0.barcode == barcode }) {
            resultName = local.name
            return
        }
        isLooking = true
        Task {
            let result = await ProductLookupService.shared.lookup(barcode: barcode)
            foundProduct = result
            resultName = result?.name ?? barcode
            isLooking = false
        }
    }

    private func resetScanner() {
        scannedBarcode = nil
        foundProduct = nil
        resultName = ""
        scannerActive = true
    }
}

#Preview { ScannerView().modelContainer(.preview) }
