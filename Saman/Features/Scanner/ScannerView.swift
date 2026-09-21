import SwiftUI
import VisionKit
import SwiftData

struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [Product]

    /// Reports the scanned barcode and a looked-up name (when known) back to Add Item.
    let onPick: (_ barcode: String, _ name: String?) -> Void

    @State private var scannedBarcode: String?
    @State private var foundProduct: FoundProduct?
    @State private var isLooking = false
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

                    // Saag corner brackets
                    ScannerCornerBrackets(color: .brandSaag)
                        .ignoresSafeArea()

                    // Dim overlay when not scanning
                    if !scannerActive {
                        Color.black.opacity(0.45).ignoresSafeArea()
                    }

                    // Top wordmark
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Samaan")
                                    .font(.pantryDisplay)
                                    .foregroundStyle(.white)
                                Text("Tap a barcode to scan")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Close scanner")
                        }
                        .padding(.horizontal, Samaan.Space.md)
                        .padding(.top, 8)
                        Spacer()
                    }

                    // Result / status card at bottom
                    VStack {
                        Spacer()
                        resultCard
                            .padding(.horizontal, Samaan.Space.md)
                            .padding(.bottom, 48)
                    }

                } else {
                    VStack(spacing: 16) {
                        SamaanEmptyState(
                            emoji: "📷",
                            title: "Scanner unavailable",
                            message: "This device doesn't support the camera scanner."
                        )
                        Button("Close") { dismiss() }
                            .buttonStyle(SamaanSecondaryButtonStyle())
                            .padding(.horizontal, Samaan.Space.md)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Result card

    @ViewBuilder
    private var resultCard: some View {
        if isLooking {
            HStack(spacing: 12) {
                ProgressView().tint(Color.brandSaag)
                Text("Looking up product…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.inkKohl)
                Spacer()
            }
            .padding(16)
            .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: Samaan.Radius.lg))
        } else if let barcode = scannedBarcode {
            VStack(spacing: 14) {
                // Product info
                HStack(spacing: 12) {
                    Text(pickedName == nil ? "❓" : "🛍️")
                        .font(.system(size: 28))
                        .frame(width: 52, height: 52)
                        .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        if let name = pickedName {
                            Text(name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.inkKohl)
                            if let brand = foundProduct?.brand {
                                Text(brand)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.inkKohlSoft)
                            }
                        } else {
                            Text("Unknown product")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.inkKohl)
                            Text(barcode)
                                .font(.samaanMono(12))
                                .foregroundStyle(Color.inkKohlSoft)
                        }
                    }
                    Spacer()
                }

                // Actions — fill the open Add Item form; do not present another AddItemView
                HStack(spacing: 10) {
                    Button("Scan Again") { resetScanner() }
                        .buttonStyle(SamaanSecondaryButtonStyle())
                    Button("Use this") { pickCurrent() }
                        .buttonStyle(SamaanPrimaryButtonStyle())
                }
            }
            .padding(16)
            .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: Samaan.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Samaan.Radius.lg).stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1))
        } else {
            // Hint
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .foregroundStyle(Color.brandSaag)
                Text("Point at a barcode and tap to scan")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohl)
            }
            .padding(14)
            .background(Color.surfaceMalai.opacity(0.92), in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
        }
    }

    /// Looked-up or local catalog name, never the raw barcode.
    private var pickedName: String? {
        if let name = foundProduct?.name, !name.isEmpty { return name }
        if !resultName.isEmpty, resultName != scannedBarcode { return resultName }
        return nil
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
            resultName = result?.name ?? ""
            isLooking = false
        }
    }

    private func pickCurrent() {
        guard let barcode = scannedBarcode else { return }
        onPick(barcode, pickedName)
        dismiss()
    }

    private func resetScanner() {
        scannedBarcode = nil
        foundProduct = nil
        resultName = ""
        scannerActive = true
    }
}

#Preview { ScannerView { _, _ in }.modelContainer(.preview) }
