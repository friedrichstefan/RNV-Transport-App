//
//  WalletService.swift
//  RNV-Transport-App
//
// Generates and signs a .pkpass for the Deutschlandticket.
//
// Setup required before use:
//   1. Register a Pass Type ID at developer.apple.com → Certificates, IDs & Profiles → Identifiers
//   2. Create & download the Pass Type ID certificate, export it as PassCertificate.p12
//   3. Drag PassCertificate.p12 into the Xcode target (check "Add to target")
//   4. Fill in passTypeIdentifier and teamIdentifier below

import Foundation
import PassKit
import Security
import CommonCrypto
import UIKit
import ZXingCpp

// MARK: - Configuration

enum WalletConfig {
    // Pass Type ID registered at developer.apple.com (e.g. "pass.de.rnv.deutschlandticket")
    static let passTypeIdentifier = "pass.com.stefanfriedrich.dticket"
    // 10-character Apple Team ID (visible in Xcode → Signing & Capabilities or developer.apple.com)
    static let teamIdentifier     = "A4HCRKN53K"
    // Filename of the .p12 certificate in the main bundle (without extension)
    static let certFileName       = "Zertifikat D-Ticket"
    // Password used when exporting the .p12 (empty string if none)
    static let certPassword       = ""
    // Apple WWDR intermediate certificate (required in the CMS signature chain)
    static let wwdrCertFileName   = "AppleWWDRCAG4"
}

// MARK: - Error

enum WalletPassError: LocalizedError {
    case noCertificate
    case importFailed(OSStatus)
    case signingFailed
    case packagingFailed

    var errorDescription: String? {
        switch self {
        case .noCertificate:
            return "Zertifikat-Datei nicht gefunden.\n\nDatei '\(WalletConfig.certFileName).p12' ist nicht im App-Bundle."
        case .importFailed(let status):
            return "Zertifikat konnte nicht importiert werden (OSStatus \(status)).\n\nPasswort prüfen oder .p12 neu exportieren."
        case .signingFailed:
            return "Pass konnte nicht signiert werden. Zertifikat und Team-ID prüfen."
        case .packagingFailed:
            return "Pass konnte nicht erstellt werden."
        }
    }
}

// MARK: - Generator

final class WalletPassGenerator {

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    /// Builds a signed `.pkpass` Data ready for `PKPass(data:)`.
    func generatePass(for ticket: DeutschlandTicket, barcodeImage: UIImage?) throws -> Data {
        let barcodeText = barcodeImage.flatMap { decodeBarcode(from: $0) }
        var files: [String: Data] = [:]

        // pass.json
        let passDict = makePassJSON(ticket: ticket, barcodeText: barcodeText)
        guard let passData = try? JSONSerialization.data(withJSONObject: passDict, options: [.prettyPrinted, .sortedKeys]) else {
            throw WalletPassError.packagingFailed
        }
        files["pass.json"] = passData
        #if DEBUG
        print("📋 [WALLET] pass.json:\n\(String(data: passData, encoding: .utf8) ?? "")")
        #endif

        // icon.png (required by PassKit — must be present)
        if let icon = makeIconData() {
            files["icon.png"]    = icon
            files["icon@2x.png"] = icon
            files["icon@3x.png"] = icon
        }

        // logo.png (some PassKit implementations require it alongside logoText)
        if let logo = makeIconData() {
            files["logo.png"]    = logo
            files["logo@2x.png"] = logo
        }

        // thumbnail = extracted barcode image
        if let barcodeImage, let png = barcodeImage.pngData() {
            files["thumbnail.png"]    = png
            files["thumbnail@2x.png"] = png
        }

        // manifest.json — SHA1 hashes of every other file (PassKit spec)
        let manifest = files.mapValues { sha1Hex($0) }
        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys) else {
            throw WalletPassError.packagingFailed
        }
        files["manifest.json"] = manifestData
        #if DEBUG
        print("📋 [WALLET] manifest.json:\n\(String(data: manifestData, encoding: .utf8) ?? "")")
        #endif

        // signature — detached CMS signature of manifest.json
        let signature = try signManifest(manifestData)
        files["signature"] = signature
        #if DEBUG
        print("✅ [WALLET] Signatur erstellt: \(signature.count) Bytes")
        print("📦 [WALLET] Pass enthält \(files.count) Dateien: \(files.keys.sorted().joined(separator: ", "))")
        #endif

        return try packageAsZip(files)
    }

    // MARK: - pass.json

    private func makePassJSON(ticket: DeutschlandTicket, barcodeText: String?) -> [String: Any] {
        let serial = "DT-\(ticket.customerNumber.isEmpty ? UUID().uuidString : ticket.customerNumber)-\(df.string(from: ticket.validFrom))"

        var dict: [String: Any] = [
            "formatVersion":      1,
            "passTypeIdentifier": WalletConfig.passTypeIdentifier,
            "serialNumber":       serial,
            "teamIdentifier":     WalletConfig.teamIdentifier,
            "organizationName":   "Deutschlandticket",
            "description":        ticket.ticketLabel,
            "logoText":           "D-TICKET",
            "foregroundColor":    "rgb(26, 26, 26)",
            "backgroundColor":    "rgb(255, 255, 255)",
            "labelColor":         "rgb(130, 130, 130)",
        ]

        var primaryFields: [[String: Any]] = []
        if !ticket.holderName.isEmpty {
            primaryFields.append(["key": "holder", "label": "INHABER", "value": ticket.holderName.uppercased()])
        }

        var secondaryFields: [[String: Any]] = [
            ["key": "validFrom",  "label": "GÜLTIG AB",  "value": df.string(from: ticket.validFrom)],
            ["key": "validUntil", "label": "GÜLTIG BIS", "value": df.string(from: ticket.validUntil)],
        ]
        if !ticket.issuer.isEmpty {
            secondaryFields.append(["key": "issuer", "label": "ANBIETER", "value": ticket.issuer])
        }

        let auxiliaryFields: [[String: Any]] = [
            ["key": "scope", "label": "GELTUNGSBEREICH", "value": "Bundesweit im Nahverkehr"],
        ]

        dict["generic"] = [
            "primaryFields":   primaryFields,
            "secondaryFields": secondaryFields,
            "auxiliaryFields": auxiliaryFields,
        ] as [String: Any]

        if let text = barcodeText {
            let barcode: [String: Any] = [
                "message":         text,
                "format":          "PKBarcodeFormatAztec",
                "messageEncoding": "iso-8859-1",
            ]
            dict["barcode"]  = barcode
            dict["barcodes"] = [barcode]
        }

        return dict
    }

    // MARK: - Signing (manual PKCS7/CMS — CMSEncoder is macOS-only)

    private func signManifest(_ data: Data) throws -> Data {
        let (identity, chain) = try loadSigningIdentity()

        var leafCertRef: SecCertificate?
        var privateKeyRef: SecKey?
        guard SecIdentityCopyCertificate(identity, &leafCertRef) == errSecSuccess, let leafCert = leafCertRef,
              SecIdentityCopyPrivateKey(identity, &privateKeyRef) == errSecSuccess, let privateKey = privateKeyRef
        else { throw WalletPassError.signingFailed }

        let manifestDigest = sha1Data(data)

        let oidContentType   = asnOID([1,2,840,113549,1,9,3])
        let oidMessageDigest = asnOID([1,2,840,113549,1,9,4])
        let oidSigningTime   = asnOID([1,2,840,113549,1,9,5])
        let oidData          = asnOID([1,2,840,113549,1,7,1])
        let signingTime      = asnUTCTime(Date())
        let attrsBody = asnSeq([oidContentType,   asnSet([oidData])]) +
                        asnSeq([oidSigningTime,   asnSet([signingTime])]) +
                        asnSeq([oidMessageDigest, asnSet([asnOctetString(manifestDigest)])])
        let attrsForSigning = asnTLV(0x31, attrsBody)
        let attrsField      = asnTLV(0xa0, attrsBody)

        var cfErr: Unmanaged<CFError>?
        guard let sigBytes = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA1, attrsForSigning as CFData, &cfErr
        ) as Data? else { throw WalletPassError.signingFailed }

        let leafDER   = SecCertificateCopyData(leafCert) as Data
        let chainDERs = chain.map { SecCertificateCopyData($0) as Data }

        guard let issuerSeq = SecCertificateCopyNormalizedIssuerSequence(leafCert) as Data? else {
            throw WalletPassError.signingFailed
        }
        var cfErr2: Unmanaged<CFError>?
        guard let serialBytes = SecCertificateCopySerialNumberData(leafCert, &cfErr2) as Data? else {
            throw WalletPassError.signingFailed
        }

        return buildPKCS7(sig: sigBytes, signedAttrs: attrsField, leafDER: leafDER,
                          chainDERs: chainDERs, issuerSeq: issuerSeq, serialBytes: serialBytes)
    }

    private func loadSigningIdentity() throws -> (SecIdentity, [SecCertificate]) {
        guard let url = Bundle.main.url(forResource: WalletConfig.certFileName, withExtension: "p12"),
              let p12Data = try? Data(contentsOf: url) else {
            #if DEBUG
            let bundleContents = (try? FileManager.default.contentsOfDirectory(
                at: Bundle.main.bundleURL, includingPropertiesForKeys: nil
            )) ?? []
            print("❌ [WALLET] '\(WalletConfig.certFileName).p12' nicht gefunden. Bundle-Inhalt:")
            bundleContents.forEach { print("  - \($0.lastPathComponent)") }
            #endif
            throw WalletPassError.noCertificate
        }

        // Always pass the passphrase — even an empty string is different from omitting it.
        // Omitting causes iOS to expect interactive input which fails programmatically.
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: WalletConfig.certPassword
        ]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        #if DEBUG
        print("🔐 [WALLET] SecPKCS12Import status: \(status)")
        #endif
        guard status == errSecSuccess else {
            throw WalletPassError.importFailed(status)
        }
        guard let itemArray = items as? [[String: Any]],
              let first = itemArray.first,
              let rawIdentity = first[kSecImportItemIdentity as String] else {
            throw WalletPassError.importFailed(-1)
        }
        let identity = rawIdentity as! SecIdentity
        var chain = first[kSecImportItemCertChain as String] as? [SecCertificate] ?? []

        // Apple Wallet requires the WWDR intermediate in the signature chain.
        if let wwdr = loadWWDRCertificate() {
            let wwdrData = SecCertificateCopyData(wwdr) as Data
            let alreadyPresent = chain.contains { SecCertificateCopyData($0) as Data == wwdrData }
            if !alreadyPresent {
                chain.append(wwdr)
            }
        }
        #if DEBUG
        print("🔐 [WALLET] Chain hat \(chain.count) Zertifikat(e)")
        for (i, cert) in chain.enumerated() {
            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "?"
            print("   [\(i)] \(summary)")
        }
        #endif

        return (identity, chain)
    }

    private func loadWWDRCertificate() -> SecCertificate? {
        guard let url = Bundle.main.url(forResource: WalletConfig.wwdrCertFileName, withExtension: "cer"),
              let data = try? Data(contentsOf: url),
              let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            #if DEBUG
            print("⚠️ [WALLET] WWDR-Zertifikat '\(WalletConfig.wwdrCertFileName).cer' nicht gefunden")
            #endif
            return nil
        }
        return cert
    }

    // MARK: - PKCS7 SignedData builder (DER)

    private func buildPKCS7(sig: Data, signedAttrs: Data, leafDER: Data, chainDERs: [Data],
                            issuerSeq: Data, serialBytes: Data) -> Data {
        let oidSignedData = asnOID([1,2,840,113549,1,7,2])
        let oidData       = asnOID([1,2,840,113549,1,7,1])
        let oidSHA1       = asnOID([1,3,14,3,2,26])
        let oidRSASHA1    = asnOID([1,2,840,113549,1,1,5])
        let null          = Data([0x05, 0x00])

        let digestAlgos     = asnSet([asnSeq([oidSHA1, null])])
        let encapContent    = asnSeq([oidData])  // detached — no eContent
        let allCerts        = asnTagImplicit(0xa0, ([leafDER] + chainDERs).reduce(Data(), +))
        let issuerAndSerial = asnSeq([issuerSeq, asnIntBytes(serialBytes)])
        let signerInfo      = asnSeq([
            asnIntVal(1),
            issuerAndSerial,
            asnSeq([oidSHA1, null]),      // digestAlgorithm
            signedAttrs,                   // [0] IMPLICIT signedAttrs
            asnSeq([oidRSASHA1, null]),   // signatureAlgorithm
            asnOctetString(sig),
        ])
        let signedData = asnSeq([asnIntVal(1), digestAlgos, encapContent, allCerts, asnSet([signerInfo])])
        return asnSeq([oidSignedData, asnTagExplicit(0, signedData)])
    }

    // MARK: - ASN.1/DER helpers

    private func asnLen(_ n: Int) -> Data {
        guard n >= 128 else { return Data([UInt8(n)]) }
        var bytes = [UInt8](); var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data([UInt8(0x80 | bytes.count)] + bytes)
    }
    private func asnTLV(_ tag: UInt8, _ body: Data) -> Data { Data([tag]) + asnLen(body.count) + body }
    private func asnSeq(_ parts: [Data]) -> Data { asnTLV(0x30, parts.reduce(Data(), +)) }
    private func asnSet(_ parts: [Data]) -> Data { asnTLV(0x31, parts.reduce(Data(), +)) }
    private func asnOctetString(_ d: Data) -> Data { asnTLV(0x04, d) }
    private func asnTagImplicit(_ tag: UInt8, _ body: Data) -> Data { asnTLV(tag, body) }
    private func asnTagExplicit(_ tag: Int, _ body: Data) -> Data { asnTLV(UInt8(0xa0 | tag), body) }

    private func asnUTCTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        let str = f.string(from: date) + "Z"
        return asnTLV(0x17, Data(str.utf8))
    }

    private func asnIntVal(_ v: Int) -> Data {
        var bytes = [UInt8](); var n = v
        repeat { bytes.insert(UInt8(n & 0xff), at: 0); n >>= 8 } while n != 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return asnTLV(0x02, Data(bytes))
    }
    private func asnIntBytes(_ raw: Data) -> Data {
        var b = raw
        while b.count > 1 && b[0] == 0 { b = b.dropFirst() }
        if b[0] & 0x80 != 0 { b = Data([0]) + b }
        return asnTLV(0x02, b)
    }
    private func asnOID(_ parts: [Int]) -> Data {
        var bytes = [UInt8(40 * parts[0] + parts[1])]
        for c in parts.dropFirst(2) {
            var n = c; var enc = [UInt8(n & 0x7f)]; n >>= 7
            while n > 0 { enc.insert(UInt8(0x80 | (n & 0x7f)), at: 0); n >>= 7 }
            bytes.append(contentsOf: enc)
        }
        return asnTLV(0x06, Data(bytes))
    }

    // MARK: - Barcode Decoding

    private func decodeBarcode(from image: UIImage) -> String? {
        guard let cgImage = normalizedOrientation(image).cgImage else { return nil }
        let options = ZXIReaderOptions()
        options.formats = [
            NSNumber(value: ZXIFormat.AZTEC.rawValue),
            NSNumber(value: ZXIFormat.QR_CODE.rawValue),
            NSNumber(value: ZXIFormat.DATA_MATRIX.rawValue),
        ]
        options.tryRotate    = true
        options.tryDownscale = true
        let reader = ZXIBarcodeReader(options: options)
        guard let results = try? reader.read(cgImage), let result = results.first else { return nil }
        return result.text
    }

    private func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    // MARK: - Icon (programmatic "D" on red background)

    private func makeIconData() -> Data? {
        let size = CGSize(width: 58, height: 58)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor(red: 0.82, green: 0.0, blue: 0.0, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 13).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .black),
                .foregroundColor: UIColor.white,
            ]
            let text = "D" as NSString
            let ts = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2),
                withAttributes: attrs
            )
        }
        return image.pngData()
    }

    // MARK: - SHA1 (PassKit manifest spec requires SHA1)

    private func sha1Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sha1Data(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        return Data(digest)
    }

    // MARK: - ZIP (stored, no compression — PassKit only needs a valid ZIP structure)

    private func packageAsZip(_ files: [String: Data]) throws -> Data {
        var localSection = Data()
        var centralDir   = Data()

        struct Entry { let nameData: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }
        var entries: [Entry] = []

        for name in files.keys.sorted() {
            guard let content = files[name], let nameData = name.data(using: .utf8) else { continue }
            let crc    = crc32(content)
            let size   = UInt32(content.count)
            let offset = UInt32(localSection.count)
            entries.append(Entry(nameData: nameData, crc: crc, size: size, offset: offset))

            localSection += u32(0x04034B50)              // local file header signature
            localSection += u16(20)                      // version needed: 2.0
            localSection += u16(0)                       // general purpose flags
            localSection += u16(0)                       // compression: stored
            localSection += u16(0) + u16(0)              // last mod time + date
            localSection += u32(crc)
            localSection += u32(size) + u32(size)        // compressed + uncompressed size
            localSection += u16(UInt16(nameData.count))
            localSection += u16(0)                       // extra field length
            localSection += nameData
            localSection += content
        }

        let cdOffset = UInt32(localSection.count)

        for e in entries {
            centralDir += u32(0x02014B50)                // central dir signature
            centralDir += u16(20) + u16(20)              // version made / version needed
            centralDir += u16(0)                         // flags
            centralDir += u16(0)                         // compression
            centralDir += u16(0) + u16(0)                // mod time + date
            centralDir += u32(e.crc)
            centralDir += u32(e.size) + u32(e.size)      // compressed + uncompressed
            centralDir += u16(UInt16(e.nameData.count))
            centralDir += u16(0) + u16(0)                // extra + comment length
            centralDir += u16(0)                         // disk number start
            centralDir += u16(0) + u32(0)                // internal + external attrs
            centralDir += u32(e.offset)                  // offset of local header
            centralDir += e.nameData
        }

        var eocd = Data()
        eocd += u32(0x06054B50)                          // end of central dir signature
        eocd += u16(0) + u16(0)                          // disk + start disk
        eocd += u16(UInt16(entries.count)) + u16(UInt16(entries.count))
        eocd += u32(UInt32(centralDir.count))
        eocd += u32(cdOffset)
        eocd += u16(0)                                   // comment length

        return localSection + centralDir + eocd
    }

    // MARK: - CRC-32 (ISO 3309 / ZIP standard)

    private func crc32(_ data: Data) -> UInt32 {
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            (0..<8).reduce(UInt32(i)) { c, _ in (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        }
        return data.reduce(0xFFFFFFFF) { crc, byte in
            table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        } ^ 0xFFFFFFFF
    }

    private func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
