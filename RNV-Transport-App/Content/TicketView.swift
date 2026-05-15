//
//  TicketView.swift
//  RNV-Transport-App
//

import SwiftUI
import PhotosUI
import PassKit
import Vision
import Accelerate
import ZXingCpp

// MARK: - Data Model

struct DeutschlandTicket: Codable {
    var ticketLabel: String = "Deutschlandticket"
    var holderName: String = ""
    var customerNumber: String = ""
    var validFrom: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    var validUntil: Date = {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = cal.range(of: .day, in: .month, for: Date())?.count ?? 28
        return cal.date(from: comps) ?? Date()
    }()
    var issuer: String = ""
}

// MARK: - OCR Service

private struct TicketScanService {
    struct ScanResult {
        var ticket = DeutschlandTicket()
        var barcodeImage: UIImage? = nil
    }

    private static let ciContext = CIContext()
    private static let dateRegex = try? NSRegularExpression(pattern: #"(\d{2}[./]\d{2}[./]\d{4})"#)

    func scan(_ images: [UIImage]) async -> ScanResult {
        var result = ScanResult()
        for image in images {
            async let cropped = extractBarcode(from: image)
            async let lines = recognizeText(in: image)
            let (croppedResult, linesResult) = await (cropped, lines)

            parseInto(&result.ticket, lines: linesResult)

            if let croppedResult {
                result.barcodeImage = croppedResult
            } else if looksLikeBarcodeImage(lines: linesResult) {
                result.barcodeImage = image
            }
        }
        if result.barcodeImage == nil, images.count == 1 {
            result.barcodeImage = images[0]
        }
        return result
    }

    private func looksLikeBarcodeImage(lines: [String]) -> Bool {
        lines.filter { $0.count > 3 }.count < 6
    }

    // MARK: Barcode Extraction
    // Same approach as qr-wallet: ZXingCpp detect → perspective correct → Otsu binarize.
    // No re-encoding — we extract the original pixels so binary Aztec (VDV) data survives intact.

    private func extractBarcode(from image: UIImage) async -> UIImage? {
        let normalized = normalizedOrientation(image)
        guard let cgImage = normalized.cgImage else { return nil }

        // Pass 1: ZXingCpp on original
        if let result = zxingExtract(cgImage) { return result }

        // Pass 2: ZXingCpp on contrast-enhanced grayscale
        if let enhanced = enhancedForBarcode(cgImage),
           let result = zxingExtract(enhanced) { return result }

        // Pass 3: Vision fallback (handles edge cases ZXing misses)
        return await visionFallback(cgImage)
    }

    // MARK: ZXingCpp (primary — matches qr-wallet's zxingcpp approach)

    private func zxingExtract(_ cgImage: CGImage) -> UIImage? {
        let options = ZXIReaderOptions()
        options.formats = [NSNumber(value: ZXIFormat.AZTEC.rawValue),
                           NSNumber(value: ZXIFormat.QR_CODE.rawValue),
                           NSNumber(value: ZXIFormat.DATA_MATRIX.rawValue)]
        options.tryRotate = true
        options.tryDownscale = true
        options.tryInvert = true

        let reader = ZXIBarcodeReader(options: options)
        guard let results = try? reader.read(cgImage),
              let result = results.first else { return nil }

        #if DEBUG
        print("✅ ZXing detected: \(result.format.rawValue), text length: \(result.text.count)")
        #endif

        return perspectiveCorrectedAndBinarized(cgImage, position: result.position)
    }

    // Perspective-correct using the 4 exact corner points, then Otsu-binarize.
    // Equivalent to cv2.getPerspectiveTransform + cv2.warpPerspective + cv2.THRESH_OTSU in qr-wallet.
    private func perspectiveCorrectedAndBinarized(_ cgImage: CGImage, position: ZXIPosition) -> UIImage? {
        let h = CGFloat(cgImage.height)

        // ZXingCpp: y=0 at top (image space). CIPerspectiveCorrection: y=0 at bottom (CIImage space).
        func toCI(_ p: ZXIPoint) -> CIVector {
            CIVector(x: CGFloat(p.x), y: h - CGFloat(p.y))
        }

        let ciInput = CIImage(cgImage: cgImage)
        guard let perspFilter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        perspFilter.setValue(ciInput, forKey: kCIInputImageKey)
        perspFilter.setValue(toCI(position.topLeft),     forKey: "inputTopLeft")
        perspFilter.setValue(toCI(position.topRight),    forKey: "inputTopRight")
        perspFilter.setValue(toCI(position.bottomLeft),  forKey: "inputBottomLeft")
        perspFilter.setValue(toCI(position.bottomRight), forKey: "inputBottomRight")

        guard var corrected = perspFilter.outputImage else { return nil }

        // Scale to 600×600 output with 24px quiet zone (same as qr-wallet: out_size=600, quiet=24)
        let outSize: CGFloat = 600, quiet: CGFloat = 24
        let inner = outSize - 2 * quiet
        let scale = inner / max(corrected.extent.width, corrected.extent.height)
        corrected = corrected.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Desaturate
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(corrected, forKey: kCIInputImageKey)
            f.setValue(0.0, forKey: kCIInputSaturationKey)
            if let out = f.outputImage { corrected = out }
        }

        // Otsu threshold — adaptive, same as cv2.THRESH_OTSU in qr-wallet
        guard let grayForHistogram = Self.ciContext.createCGImage(corrected, from: corrected.extent) else { return nil }
        let otsuT = Float(computeOtsuThreshold(grayForHistogram)) / 255.0

        if let f = CIFilter(name: "CIColorThreshold") {
            f.setValue(corrected, forKey: kCIInputImageKey)
            f.setValue(otsuT, forKey: "inputThreshold")
            if let out = f.outputImage { corrected = out }
        }

        guard let cgResult = Self.ciContext.createCGImage(corrected, from: corrected.extent) else { return nil }
        return UIImage(cgImage: cgResult)
    }

    // MARK: Otsu's Method via vImage

    private func computeOtsuThreshold(_ cgImage: CGImage) -> Int {
        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        ) else { return 128 }

        var buffer = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&buffer, &format, nil, cgImage,
                                           vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return 128 }
        defer { free(buffer.data) }

        var histogram = [vImagePixelCount](repeating: 0, count: 256)
        let error = histogram.withUnsafeMutableBufferPointer { ptr -> vImage_Error in
            vImageHistogramCalculation_Planar8(&buffer, ptr.baseAddress!, vImage_Flags(kvImageNoFlags))
        }
        guard error == kvImageNoError else { return 128 }

        let total = Int(buffer.width) * Int(buffer.height)
        return otsuFromHistogram(histogram, total: total)
    }

    private func otsuFromHistogram(_ histogram: [vImagePixelCount], total: Int) -> Int {
        var sum = 0
        for i in 0..<256 { sum += i * Int(histogram[i]) }

        var sumB = 0, wB = 0, maxVariance: Double = 0, threshold = 128

        for t in 0..<256 {
            wB += Int(histogram[t])
            guard wB > 0 else { continue }
            let wF = total - wB
            guard wF > 0 else { break }

            sumB += t * Int(histogram[t])
            let mB = Double(sumB) / Double(wB)
            let mF = Double(sum - sumB) / Double(wF)
            let variance = Double(wB) * Double(wF) * (mB - mF) * (mB - mF)

            if variance > maxVariance {
                maxVariance = variance
                threshold = t
            }
        }
        return threshold
    }

    // MARK: Vision Fallback (for cases ZXingCpp misses)

    private func visionFallback(_ cgImage: CGImage) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (UIImage?) -> Void = { img in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: img)
            }

            let request = VNDetectBarcodesRequest { req, _ in
                guard let obs = req.results?
                    .compactMap({ $0 as? VNBarcodeObservation })
                    .first(where: { $0.symbology == .aztec || $0.symbology == .qr || $0.symbology == .dataMatrix })
                else { finish(nil); return }

                // Approximate perspective correction from bounding box corners
                let imgW = CGFloat(cgImage.width), imgH = CGFloat(cgImage.height)
                let box = obs.boundingBox
                let pad: CGFloat = 0.05
                let x = max(0, (box.minX - pad) * imgW)
                let y = max(0, (1.0 - box.maxY - pad) * imgH)
                let w = min(imgW - x, (box.width + pad * 2) * imgW)
                let h = min(imgH - y, (box.height + pad * 2) * imgH)

                guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
                    finish(nil); return
                }

                var ci = CIImage(cgImage: cropped)
                    .transformed(by: CGAffineTransform(scaleX: 576 / w, y: 576 / h))
                if let f = CIFilter(name: "CIColorControls") {
                    f.setValue(ci, forKey: kCIInputImageKey); f.setValue(0.0, forKey: kCIInputSaturationKey)
                    if let out = f.outputImage { ci = out }
                }
                guard let gray = Self.ciContext.createCGImage(ci, from: ci.extent) else { finish(nil); return }
                let t = Float(self.computeOtsuThreshold(gray)) / 255.0
                if let f = CIFilter(name: "CIColorThreshold") {
                    f.setValue(ci, forKey: kCIInputImageKey); f.setValue(t, forKey: "inputThreshold")
                    if let out = f.outputImage, let cg = Self.ciContext.createCGImage(out, from: out.extent) {
                        finish(UIImage(cgImage: cg)); return
                    }
                }
                finish(UIImage(cgImage: gray))
            }
            request.symbologies = [.aztec, .qr, .dataMatrix]
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }

    // Grayscale + contrast boost + sharpening
    private func enhancedForBarcode(_ cgImage: CGImage) -> CGImage? {
        var ci = CIImage(cgImage: cgImage)
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(0.0, forKey: kCIInputSaturationKey)
            f.setValue(1.4, forKey: kCIInputContrastKey)
            if let out = f.outputImage { ci = out }
        }
        if let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(0.5, forKey: kCIInputSharpnessKey)
            if let out = f.outputImage { ci = out }
        }
        return Self.ciContext.createCGImage(ci, from: ci.extent)
    }

    private func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    // MARK: Text Recognition

    private func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let results = req.results?
                    .compactMap { ($0 as? VNRecognizedTextObservation)?.topCandidates(1).first?.string }
                    ?? []
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }

    // MARK: Parsing

    private func parseInto(_ ticket: inout DeutschlandTicket, lines: [String]) {
        let joined = lines.joined(separator: "\n")

        let ticketTypes: [(String, String)] = [
            ("D-Ticket Job", "D-Ticket Job"), ("Job-Ticket", "D-Ticket Job"),
            ("Schüler", "D-Ticket Schüler"), ("65+", "D-Ticket 65+"),
            ("Semesterticket", "D-Ticket Semesterticket"),
        ]
        for (keyword, label) in ticketTypes where joined.localizedCaseInsensitiveContains(keyword) {
            ticket.ticketLabel = label
            break
        }

        let knownIssuers = ["RNV", "VRN", "DB", "BVG", "HVV", "MVV", "KVB", "VGN", "VRR"]
        for issuer in knownIssuers where joined.contains(issuer) && ticket.issuer.isEmpty {
            ticket.issuer = issuer
        }

        let nameKeywords = ["VOR & NACHNAME", "NACHNAME", "INHABER", "NAME"]
        for keyword in nameKeywords {
            if let name = lineAfter(keyword: keyword, in: lines), isLikelyName(name) {
                ticket.holderName = name
                break
            }
        }
        if ticket.holderName.isEmpty {
            ticket.holderName = lines.first(where: isLikelyName) ?? ""
        }

        if let num = lineAfter(keyword: "KUNDENNUMMER", in: lines) {
            ticket.customerNumber = num
        }
        if ticket.customerNumber.isEmpty {
            let pattern = #"\b\d{7,10}[-–]\d{4}\b"#
            if let match = joined.range(of: pattern, options: .regularExpression) {
                ticket.customerNumber = String(joined[match])
            }
        }

        let helper = DateFormattingHelper.shared
        let dates = allDateMatches(in: joined)
            .compactMap { helper.parseGermanDate($0) }
            .sorted()
        if dates.count >= 2 {
            ticket.validFrom = dates[0]
            ticket.validUntil = dates[1]
        } else if let single = dates.first {
            ticket.validFrom = single
            ticket.validUntil = lastDayOfMonth(for: single)
        }
    }

    private func lineAfter(keyword: String, in lines: [String]) -> String? {
        for (i, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains(keyword), i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !next.isEmpty { return next }
            }
        }
        return nil
    }

    private func isLikelyName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count >= 2, words.count <= 4 else { return false }
        return words.allSatisfy { $0.first?.isUppercase == true }
            && text.rangeOfCharacter(from: .decimalDigits) == nil
            && text.rangeOfCharacter(from: CharacterSet(charactersIn: "/@#%^&*()=+[]{}|<>")) == nil
    }

    private func allDateMatches(in text: String) -> [String] {
        guard let regex = Self.dateRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private func lastDayOfMonth(for date: Date) -> Date {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: date) else { return date }
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = range.count
        return cal.date(from: comps) ?? date
    }
}

// MARK: - Barcode Storage

private enum BarcodeStorage {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TicketBarcodes/barcode.jpg")
    }

    static func save(_ image: UIImage) {
        let dest = url
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.95)?.write(to: dest)
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - TicketView

struct TicketView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("deutschlandTicketData") private var storedJSON = ""

    @State private var ticket: DeutschlandTicket? = nil
    @State private var barcodeImage: UIImage? = nil

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var showImportOptions = false

    @State private var isScanning = false
    @State private var pendingScan: (ticket: DeutschlandTicket, barcode: UIImage?)? = nil
    @State private var showConfirmSheet = false
    @State private var showManualSheet = false
    @State private var showFullscreen = false
    @State private var showDeleteConfirm = false
    @State private var walletPass: PKPass? = nil
    @State private var showWalletSheet = false
    @State private var walletError: String? = nil
    @State private var showWalletError = false

    private let scanner = TicketScanService()
    private var canvas: Color { AppTheme.canvasAdaptive(colorScheme) }

    var body: some View {
        NavigationView {
            ZStack {
                canvas.ignoresSafeArea()
                if isScanning {
                    scanningOverlay
                } else if let ticket {
                    ticketDetailView(ticket)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Mein Ticket")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItems, maxSelectionCount: 2, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importAndScan(items) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource(),
                  let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else { return }
            url.stopAccessingSecurityScopedResource()
            Task { await runScan([img]) }
        }
        .confirmationDialog("Ticket-Screenshot importieren", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Aus Fotos (1–2 Screenshots)") { showPhotosPicker = true }
            Button("Aus Dateien") { showFileImporter = true }
            Button("Manuell eingeben") { showManualSheet = true }
            Button("Abbrechen", role: .cancel) { }
        }
        .sheet(isPresented: $showConfirmSheet) {
            if let pending = pendingScan {
                TicketConfirmSheet(draft: pending.ticket, barcodeImage: pending.barcode) { saved, barcode in
                    applyTicket(saved, barcode: barcode)
                }
            }
        }
        .sheet(isPresented: $showManualSheet) {
            TicketConfirmSheet(draft: ticket ?? DeutschlandTicket(), barcodeImage: barcodeImage) { saved, barcode in
                applyTicket(saved, barcode: barcode)
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            if let ticket { TicketFullscreenView(ticket: ticket, barcodeImage: barcodeImage) }
        }
        .alert("Ticket entfernen?", isPresented: $showDeleteConfirm) {
            Button("Entfernen", role: .destructive) { deleteTicket() }
            Button("Abbrechen", role: .cancel) { }
        }
        .sheet(isPresented: $showWalletSheet) {
            if let pass = walletPass {
                PKAddPassView(pass: pass, isPresented: $showWalletSheet)
                    .ignoresSafeArea()
            }
        }
        .alert("Wallet-Fehler", isPresented: $showWalletError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(walletError ?? "Unbekannter Fehler")
        }
        .onAppear {
            guard ticket == nil else { return }
            loadTicket()
        }
    }

    // MARK: - Scanning Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.4)
            Text("Ticket wird erkannt…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedAdaptive(colorScheme))
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 32) {
            Spacer()
            ticketIllustration
            VStack(spacing: 8) {
                Text("Kein Ticket hinterlegt")
                    .font(.title3).fontWeight(.semibold)
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                Text("Importiere einen oder zwei Screenshots\ndeines Tickets — die Daten werden\nautomatisch erkannt.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedAdaptive(colorScheme))
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                Button { showImportOptions = true } label: {
                    Label("Aus Screenshot importieren", systemImage: "photo.badge.plus")
                        .font(AppTheme.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 15)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button { showManualSheet = true } label: {
                    Text("Manuell eingeben")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedAdaptive(colorScheme))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var ticketIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 240, height: 148)
                .shadow(color: AppTheme.shadowColor(), radius: 14, y: 7)
            HStack(alignment: .center) {
                DTicketLogoView(width: 66)
                Spacer()
                Text("D-TICKET")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Color(hex: "#1a1a1a"))
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Ticket Detail

    private func ticketDetailView(_ t: DeutschlandTicket) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                TicketCardView(ticket: t, barcodeImage: barcodeImage)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button { showFullscreen = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("Vorzeigen").font(AppTheme.buttonFont)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#1a1a1a"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button { showManualSheet = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil").font(.system(size: 13))
                            Text("Bearbeiten").font(AppTheme.buttonFont)
                        }
                        .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.surfaceCardAdaptive(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)

                if PKAddPassesViewController.canAddPasses() {
                    walletButton
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if ticket != nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Neu scannen", systemImage: "photo.badge.plus") { showImportOptions = true }
                    Button("Bearbeiten", systemImage: "pencil") { showManualSheet = true }
                    Button("Entfernen", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    // MARK: - Wallet Button

    private var walletButton: some View {
        AddToWalletButton {
            Task { await addToWallet() }
        }
        .frame(height: 50)
        .padding(.horizontal, 20)
    }

    // MARK: - Apple Wallet

    private func addToWallet() async {
        guard let ticket else { return }
        do {
            let generator = WalletPassGenerator()
            let passData  = try generator.generatePass(for: ticket, barcodeImage: barcodeImage)
            #if DEBUG
            // Write pass to tmp for debugging (can be AirDrop'd to Mac for inspection)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("debug_ticket.pkpass")
            try? passData.write(to: tmpURL)
            print("💾 [WALLET] Debug-Pass geschrieben: \(tmpURL.path)")
            #endif
            let pass = try PKPass(data: passData)
            await MainActor.run {
                walletPass      = pass
                showWalletSheet = true
            }
        } catch {
            #if DEBUG
            print("❌ [WALLET] Fehler: \(error)")
            #endif
            await MainActor.run {
                walletError      = error.localizedDescription
                showWalletError  = true
            }
        }
    }

    // MARK: - Import & Scan

    private func importAndScan(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        await withTaskGroup(of: UIImage?.self) { group in
            for item in items {
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                    return UIImage(data: data)
                }
            }
            for await img in group { img.map { images.append($0) } }
        }
        photoItems = []
        await runScan(images)
    }

    private func runScan(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isScanning = true
        let result = await scanner.scan(images)
        isScanning = false
        pendingScan = (ticket: result.ticket, barcode: result.barcodeImage)
        showConfirmSheet = true
    }

    // MARK: - Persistence

    private func applyTicket(_ t: DeutschlandTicket, barcode: UIImage?) {
        ticket = t
        barcodeImage = barcode
        persist(t)
        if let img = barcode { BarcodeStorage.save(img) } else { BarcodeStorage.delete() }
    }

    private func persist(_ t: DeutschlandTicket) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        storedJSON = (try? String(data: enc.encode(t), encoding: .utf8)) ?? ""
    }

    private func loadTicket() {
        guard !storedJSON.isEmpty, let data = storedJSON.data(using: .utf8) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        ticket = try? dec.decode(DeutschlandTicket.self, from: data)
        barcodeImage = BarcodeStorage.load()
    }

    private func deleteTicket() {
        ticket = nil
        barcodeImage = nil
        storedJSON = ""
        BarcodeStorage.delete()
    }
}

// MARK: - Ticket Card View

struct TicketCardView: View {
    let ticket: DeutschlandTicket
    let barcodeImage: UIImage?

    @Environment(\.colorScheme) private var colorScheme

    // Static: one instance shared across all TicketCardView instances
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            perforatedLine
            barcodeSection
            perforatedLine
            infoSection
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        .shadow(color: AppTheme.shadowColor(), radius: 12, y: 6)
    }

    private var cardHeader: some View {
        HStack(alignment: .center) {
            DTicketLogoView(width: 70)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("D-TICKET")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color(hex: "#1a1a1a"))
                if ticket.ticketLabel != "Deutschlandticket" {
                    Text(ticket.ticketLabel.replacingOccurrences(of: "D-Ticket ", with: "").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemBackground))
    }

    private var perforatedLine: some View {
        ZStack {
            AppTheme.surfaceCardAdaptive(colorScheme)
            // Dashed line
            Rectangle()
                .fill(.clear)
                .overlay(
                    GeometryReader { geo in
                        Path { p in
                            p.move(to: CGPoint(x: 20, y: 0))
                            p.addLine(to: CGPoint(x: geo.size.width - 20, y: 0))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(AppTheme.hairlineAdaptive(colorScheme))
                    }
                )
            // Notches at edges — overlay on the parent so they're not clipped to the 1pt line
            HStack {
                Circle()
                    .fill(AppTheme.canvasAdaptive(colorScheme))
                    .frame(width: 20, height: 20)
                    .offset(x: -10)
                Spacer()
                Circle()
                    .fill(AppTheme.canvasAdaptive(colorScheme))
                    .frame(width: 20, height: 20)
                    .offset(x: 10)
            }
        }
        .frame(height: 20)
    }

    private var barcodeSection: some View {
        VStack(spacing: 10) {
            if let img = barcodeImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.black.opacity(0.1))
                    Text("Kein Barcode")
                        .font(.caption2)
                        .foregroundStyle(Color.gray)
                }
                .frame(width: 160, height: 100)
            }
            if !ticket.customerNumber.isEmpty {
                Text(chunked(ticket.customerNumber))
                    .font(AppTheme.monoFont(size: 16, weight: .regular))
                    .tracking(3)
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private func chunked(_ raw: String) -> String {
        let d = raw.filter(\.isNumber)
        guard d.count >= 4 else { return raw }
        return stride(from: 0, to: d.count, by: 4).map {
            let start = d.index(d.startIndex, offsetBy: $0)
            let end = d.index(start, offsetBy: min(4, d.count - $0))
            return String(d[start..<end])
        }.joined(separator: " ")
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            if !ticket.holderName.isEmpty {
                infoRow("INHABER", ticket.holderName)
                Divider().padding(.horizontal, 20)
            }
            if !ticket.customerNumber.isEmpty {
                infoRow("KUNDENNUMMER", ticket.customerNumber)
                Divider().padding(.horizontal, 20)
            }
            infoRow("GELTUNGSBEREICH", "Bundesweit im Nahverkehr")
            Divider().padding(.horizontal, 20)
            infoRow("GÜLTIGKEIT", "\(Self.df.string(from: ticket.validFrom)) – \(Self.df.string(from: ticket.validUntil))")
            if !ticket.issuer.isEmpty {
                Divider().padding(.horizontal, 20)
                infoRow("ANBIETER", ticket.issuer)
            }
            Text("Nur mit gültigem Lichtbildausweis · Nicht übertragbar")
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedAdaptive(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .background(AppTheme.surfaceCardAdaptive(colorScheme))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.mutedAdaptive(colorScheme))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Confirm / Edit Sheet

struct TicketConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: DeutschlandTicket
    @State private var barcodePreview: UIImage?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showPhotosPicker = false
    @State private var showBarcodeOptions = false

    let onSave: (DeutschlandTicket, UIImage?) -> Void

    private let ticketTypes = ["Deutschlandticket", "D-Ticket Job", "D-Ticket Schüler", "D-Ticket 65+", "D-Ticket Semesterticket"]
    private let issuers = ["RNV", "VRN", "DB", "BVG", "HVV", "MVV", "KVB", "VGN", "VRR"]

    init(draft: DeutschlandTicket, barcodeImage: UIImage?, onSave: @escaping (DeutschlandTicket, UIImage?) -> Void) {
        self._draft = State(initialValue: draft)
        self._barcodePreview = State(initialValue: barcodeImage)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Bitte prüfe die erkannten Daten und korrigiere sie falls nötig.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Ticket") {
                    Picker("Art", selection: $draft.ticketLabel) {
                        ForEach(ticketTypes, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Anbieter", selection: $draft.issuer) {
                        Text("Nicht angegeben").tag("")
                        ForEach(issuers, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Inhaber") {
                    TextField("Vor- und Nachname", text: $draft.holderName)
                        .textContentType(.name)
                    TextField("Kundennummer (optional)", text: $draft.customerNumber)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section("Gültigkeit") {
                    DatePicker("Von", selection: $draft.validFrom, displayedComponents: .date)
                    DatePicker("Bis", selection: $draft.validUntil, displayedComponents: .date)
                }
                Section {
                    if let barcode = barcodePreview {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(uiImage: barcode)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 220)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button("Ersetzen") { showBarcodeOptions = true }
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button { showBarcodeOptions = true } label: {
                            Label("Barcode importieren", systemImage: "qrcode.viewfinder")
                        }
                    }
                } header: {
                    Text("Barcode")
                } footer: {
                    Text("Importiere die Barcode-Seite aus deiner Ticket-App.")
                }
            }
            .navigationTitle("Daten prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(draft, barcodePreview); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(draft.holderName.isEmpty)
                }
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItems, maxSelectionCount: 1, matching: .images)
        .onChange(of: photoItems) { _, items in
            Task {
                if let item = items.first,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) { barcodePreview = img }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource(),
                  let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else { return }
            barcodePreview = img
            url.stopAccessingSecurityScopedResource()
        }
        .confirmationDialog("Barcode importieren", isPresented: $showBarcodeOptions, titleVisibility: .visible) {
            Button("Aus Fotos") { showPhotosPicker = true }
            Button("Aus Dateien") { showFileImporter = true }
            if barcodePreview != nil { Button("Entfernen", role: .destructive) { barcodePreview = nil } }
            Button("Abbrechen", role: .cancel) { }
        }
    }
}

// MARK: - Fullscreen

struct TicketFullscreenView: View {
    let ticket: DeutschlandTicket
    let barcodeImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                flagStripe.frame(height: 5).ignoresSafeArea(edges: .top)
                ScrollView {
                    TicketCardView(ticket: ticket, barcodeImage: barcodeImage)
                        .padding(20)
                        .padding(.top, 40)
                }
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            .padding(.top, 8)
        }
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
        }
    }
}

// MARK: - Shared UI

private var flagStripe: some View {
    HStack(spacing: 0) {
        Rectangle().fill(Color(hex: "#000000"))
        Rectangle().fill(Color(hex: "#DD0000"))
        Rectangle().fill(Color(hex: "#FFCE00"))
    }
}

private struct DTicketLogoView: View {
    let width: CGFloat

    private struct BarSpec: Identifiable {
        let id: Int
        let relWidth: CGFloat
        let left: Color
        let right: Color
        var xOffset: CGFloat = 0
        var leftGhost: CGFloat = 0.28
        var rightGhost: CGFloat = 0.28
        var ghostOpacity: Double = 0.22
        var leftGhostOffset: CGFloat = 0
        var rightGhostOffset: CGFloat = 0
    }

    private var bars: [BarSpec] { [
        //        relWidth  xOffset  leftGhost  rightGhost  leftGhostOffset  rightGhostOffset
        BarSpec(id: 0, relWidth: 0.33, left: Color(hex: "#111111"), right: Color(hex: "#111111"), xOffset: 20, leftGhost: 0.5, rightGhost: 0.68, leftGhostOffset:  -16, rightGhostOffset:  50),
        BarSpec(id: 1, relWidth: 0.91, left: Color(hex: "#111111"), right: Color(hex: "#111111"), xOffset:  9, leftGhost: 0.15, rightGhost: 0.68, leftGhostOffset: -3, rightGhostOffset:  66),
        BarSpec(id: 2, relWidth: 1,    left: Color(hex: "#111111"), right: Color(hex: "#111111"), xOffset:  7, leftGhost: 0.6, rightGhost: 1, leftGhostOffset: -38, rightGhostOffset:  85),
        // Red
        BarSpec(id: 3, relWidth: 1.2,  left: Color(hex: "#5E0000"), right: Color(hex: "#CC1A00"), xOffset:  3, leftGhost: 0.28, rightGhost: 1, leftGhostOffset: -26, rightGhostOffset:  77),
        BarSpec(id: 4, relWidth: 1.3,  left: Color(hex: "#5E0000"), right: Color(hex: "#CC1A00"), xOffset:  0, leftGhost: 0.8, rightGhost: 0.15, leftGhostOffset: -50, rightGhostOffset:  95),
        BarSpec(id: 5, relWidth: 0.9,  left: Color(hex: "#5E0000"), right: Color(hex: "#C01800"), xOffset:  3, leftGhost: 0.15, rightGhost: 0.85, leftGhostOffset: -14, rightGhostOffset:  70),
        // Yellow
        BarSpec(id: 6, relWidth: 1,    left: Color(hex: "#DE4400"), right: Color(hex: "#F8CC00"), xOffset:  7, leftGhost: 0.5, rightGhost: 0.15, leftGhostOffset: -24, rightGhostOffset:  81),
        BarSpec(id: 7, relWidth: 0.95, left: Color(hex: "#DE4400"), right: Color(hex: "#F8CC00"), xOffset: 20, leftGhost: 0.28, rightGhost: 0, leftGhostOffset:  -4, rightGhostOffset:  91),
        BarSpec(id: 8, relWidth: 0.8,  left: Color(hex: "#E04800"), right: Color(hex: "#F8CC00"), xOffset: 16, leftGhost: 0.38, rightGhost: 0.5, leftGhostOffset:  -19, rightGhostOffset:  76),
    ]}

    var body: some View {
        let barH: CGFloat = 9
        let gap: CGFloat = 4
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(bars) { bar in
                ZStack(alignment: .topLeading) {
                    // Linker Geist-Strich
                    if bar.leftGhost > 0 {
                        pill(barH, width * bar.leftGhost, bar.left, bar.right)
                            .opacity(bar.ghostOpacity)
                            .offset(x: bar.leftGhostOffset)
                    }
                    // Haupt-Strich
                    pill(barH, width * bar.relWidth, bar.left, bar.right)
                        .offset(x: bar.xOffset)
                    // Rechter Geist-Strich
                    if bar.rightGhost > 0 {
                        pill(barH, width * bar.rightGhost, bar.left, bar.right)
                            .opacity(bar.ghostOpacity)
                            .offset(x: bar.rightGhostOffset)
                    }
                }
                .frame(height: barH)
            }
        }
    }

    private func pill(_ h: CGFloat, _ w: CGFloat, _ l: Color, _ r: Color) -> some View {
        RoundedRectangle(cornerRadius: h / 2)
            .fill(LinearGradient(colors: [l, r], startPoint: .leading, endPoint: .trailing))
            .frame(width: w, height: h)
    }
}

// MARK: - PassKit UIViewControllerRepresentable

private struct PKAddPassView: UIViewControllerRepresentable {
    let pass: PKPass
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        // PKAddPassesViewController(passes:) is the modern init (iOS 6+)
        PKAddPassesViewController(passes: [pass]) ?? UIViewController() as! PKAddPassesViewController
    }

    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        @Binding var isPresented: Bool
        init(isPresented: Binding<Bool>) { _isPresented = isPresented }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            isPresented = false
        }
    }
}

// MARK: - Official "Add to Apple Wallet" Button

private struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

// MARK: - Previews

#Preview("Leer") {
    TicketView()
}

#Preview("Mit Ticket") {
    let t = DeutschlandTicket(
        ticketLabel: "Deutschlandticket",
        holderName: "Max Mustermann",
        customerNumber: "123456789012",
        validFrom: Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
        validUntil: Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 31))!,
        issuer: "RNV"
    )
    TicketCardView(ticket: t, barcodeImage: nil)
        .padding()
}

#Preview("Logo") {
    DTicketLogoView(width: 80)
        .padding()
}
