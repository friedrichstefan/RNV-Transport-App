//
//  SecurityHelpers.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 21.01.26.
//

import Foundation
import Security
import CryptoKit

// MARK: - Keychain Helper

class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    private let service = "com.stefanfriedrich.rnvapp"

    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case invalidItemFormat
        case unexpectedStatus(OSStatus)
    }

    // MARK: - Token Storage

    func store(token: String, account: String) throws {
        let tokenData = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }

        print("🔐 Token sicher im Keychain gespeichert")
    }

    func retrieveToken(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            } else {
                throw KeychainError.unexpectedStatus(status)
            }
        }

        guard let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw KeychainError.invalidItemFormat
        }

        return token
    }

    func deleteToken(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }

        print("🗑️ Token aus Keychain gelöscht")
    }
}

// MARK: - Request Signing Helper

class RequestSigningHelper {

    /// Signing Key aus xcconfig/Info.plist laden (nie hardcoded im Source Code)
    private var signingKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "RNV_SIGNING_KEY") as? String,
           !key.isEmpty, !key.hasPrefix("$(") {
            return key
        }
        print("⚠️ [SIGN] RNV_SIGNING_KEY nicht konfiguriert – Signing deaktiviert")
        return ""
    }

    // MARK: - Request Signing

    func signRequest(_ request: inout URLRequest, withBody body: Data? = nil) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString

        var signatureComponents: [String] = [
            request.httpMethod ?? "GET",
            request.url?.absoluteString ?? "",
            timestamp,
            nonce
        ]

        if let body = body {
            let bodyHash = SHA256.hash(data: body)
            let bodyHashString = bodyHash.compactMap { String(format: "%02x", $0) }.joined()
            signatureComponents.append(bodyHashString)
        }

        let signaturePayload = signatureComponents.joined(separator: "|")
        let signature = generateHMACSignature(payload: signaturePayload)

        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.setValue("1.0", forHTTPHeaderField: "X-API-Version")

        print("🔐 [SIGN] Request signiert: \(request.url?.host ?? "unknown")")
    }

    private func generateHMACSignature(payload: String) -> String {
        let keyString = signingKey
        guard !keyString.isEmpty else { return "" }
        let key = SymmetricKey(data: Data(keyString.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    // MARK: - Response Validation

    func validateResponse(_ response: URLResponse, data: Data) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }

        guard 200...299 ~= httpResponse.statusCode else {
            print("⚠️ [VALIDATE] Ungültiger Status Code: \(httpResponse.statusCode)")
            return false
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().contains("application/json") else {
            print("⚠️ [VALIDATE] Ungültiger Content-Type")
            return false
        }

        guard data.count < 10_000_000 else {
            print("⚠️ [VALIDATE] Response zu groß: \(data.count) bytes")
            return false
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            if let dict = json as? [String: Any] {
                return dict.keys.contains("data") || dict.keys.contains("errors")
            }
            return false
        } catch {
            print("⚠️ [VALIDATE] JSON Parsing Fehler: \(error)")
            return false
        }
    }

    // MARK: - Rate Limiting

    private var lastRequestTimes: [String: Date] = [:]
    private let minimumRequestInterval: TimeInterval = 0.5

    func canMakeRequest(to host: String) -> Bool {
        let now = Date()
        if let lastRequest = lastRequestTimes[host] {
            let timeSinceLastRequest = now.timeIntervalSince(lastRequest)
            if timeSinceLastRequest < minimumRequestInterval {
                print("⚠️ [RATE_LIMIT] Request zu schnell für \(host)")
                return false
            }
        }
        lastRequestTimes[host] = now
        return true
    }
}

// MARK: - SSL Pinning Delegate

class SSLPinningDelegate: NSObject, URLSessionDelegate {

    // MARK: - Certificate Hashes
    // SHA256-Hashes der erwarteten Serverzertifikate (DER-Format, Hex-Kodiert)
    // TODO: Ersetze die Platzhalter durch echte Zertifikat-Hashes
    private let expectedCertificateHashes: [String: String] = [
        "graphql-sandbox-dds.rnv-online.de": "SHA256_HASH_PLACEHOLDER",
        "login.microsoftonline.com": "SHA256_HASH_PLACEHOLDER"
    ]

    private let trustedHosts = [
        "graphql-sandbox-dds.rnv-online.de",
        "login.microsoftonline.com"
    ]

    // MARK: - URLSession Delegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        print("🔒 [SSL] Certificate validation für: \(challenge.protectionSpace.host)")

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            print("❌ [SSL] Ungültige Authentifizierungsmethode")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            print("❌ [SSL] Kein Server Trust verfügbar")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var trustError: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &trustError)

        guard isTrusted else {
            if let error = trustError {
                print("❌ [SSL] Trust Evaluation fehlgeschlagen: \(error)")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        if trustedHosts.contains(host) {
            print("✅ [SSL] Vertrauenswürdiger Host: \(host)")

            let pinningResult = validateCertificateChain(serverTrust: serverTrust, host: host)
            switch pinningResult {
            case .valid:
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .placeholderHash:
                print("⚠️ [SSL] Certificate Pinning noch nicht konfiguriert (Placeholder), verwende Standard-Validierung")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .mismatch(let actual, let expected):
                print("❌ [SSL] Zertifikat-Hash stimmt nicht überein! Erwartet: \(expected), Gefunden: \(actual)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            case .extractionFailed:
                print("❌ [SSL] Konnte Zertifikat nicht extrahieren")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            print("❌ [SSL] Nicht vertrauenswürdiger Host: \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Zertifikat-Validierung

    private enum PinningResult {
        case valid
        case placeholderHash
        case mismatch(actual: String, expected: String)
        case extractionFailed
    }

    private func validateCertificateChain(serverTrust: SecTrust, host: String) -> PinningResult {
        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCertificate = certChain.first else {
            return .extractionFailed
        }

        let serverCertData = SecCertificateCopyData(serverCertificate) as Data
        let hash = SHA256.hash(data: serverCertData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        print("📋 [SSL] Zertifikat Hash für \(host): \(hashString)")

        guard let expectedHash = expectedCertificateHashes[host] else {
            return .placeholderHash
        }

        if expectedHash == "SHA256_HASH_PLACEHOLDER" {
            return .placeholderHash
        }

        if hashString == expectedHash {
            return .valid
        } else {
            return .mismatch(actual: hashString, expected: expectedHash)
        }
    }

    // MARK: - Hash-Extraktion (Hilfsmethode zum Konfigurieren)

    static func extractCertificateHash(for host: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://\(host)") else {
            completion(nil)
            return
        }

        let extractor = CertificateHashExtractor(completion: completion)
        let session = URLSession(configuration: .default, delegate: extractor, delegateQueue: nil)
        session.dataTask(with: url).resume()
    }
}

// MARK: - Certificate Hash Extractor Helper

private class CertificateHashExtractor: NSObject, URLSessionDelegate {
    let completion: (String?) -> Void

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completion(nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCertificate = certChain.first else {
            completion(nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let serverCertData = SecCertificateCopyData(serverCertificate) as Data
        let hash = SHA256.hash(data: serverCertData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        completion(hashString)
        completionHandler(.performDefaultHandling, nil)
    }
}