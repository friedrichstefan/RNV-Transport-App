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
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Altes Item löschen (ignoriere "nicht gefunden")
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            #if DEBUG
            print("⚠️ [Keychain] Löschen fehlgeschlagen: \(deleteStatus)")
            #endif
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }

        #if DEBUG
        print("🔐 Token sicher im Keychain gespeichert")
        #endif
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

        #if DEBUG
        print("🗑️ Token aus Keychain gelöscht")
        #endif
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
        #if DEBUG
        print("⚠️ [SIGN] RNV_SIGNING_KEY nicht konfiguriert – Signing deaktiviert")
        #endif
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

        #if DEBUG
        print("🔐 [SIGN] Request signiert: \(request.url?.host ?? "unknown")")
        #endif
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
            #if DEBUG
            print("⚠️ [VALIDATE] Ungültiger Status Code: \(httpResponse.statusCode)")
            #endif
            return false
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().contains("application/json") else {
            #if DEBUG
            print("⚠️ [VALIDATE] Ungültiger Content-Type")
            #endif
            return false
        }

        guard data.count < 10_000_000 else {
            #if DEBUG
            print("⚠️ [VALIDATE] Response zu groß: \(data.count) bytes")
            #endif
            return false
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            if let dict = json as? [String: Any] {
                return dict.keys.contains("data") || dict.keys.contains("errors")
            }
            return false
        } catch {
            #if DEBUG
            print("⚠️ [VALIDATE] JSON Parsing Fehler: \(error)")
            #endif
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
                #if DEBUG
                print("⚠️ [RATE_LIMIT] Request zu schnell für \(host)")
                #endif
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
        #if DEBUG
        print("🔒 [SSL] Certificate validation für: \(challenge.protectionSpace.host)")
        #endif

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            #if DEBUG
            print("❌ [SSL] Ungültige Authentifizierungsmethode")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            #if DEBUG
            print("❌ [SSL] Kein Server Trust verfügbar")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var trustError: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &trustError)

        guard isTrusted else {
            #if DEBUG
            if let error = trustError {
                print("❌ [SSL] Trust Evaluation fehlgeschlagen: \(error)")
            }
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        if trustedHosts.contains(host) {
            #if DEBUG
            print("✅ [SSL] Vertrauenswürdiger Host: \(host)")
            #endif

            let pinningResult = validateCertificateChain(serverTrust: serverTrust, host: host)
            switch pinningResult {
            case .valid:
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .placeholderHash:
                #if DEBUG
                print("⚠️ [SSL] Certificate Pinning noch nicht konfiguriert (Placeholder), verwende Standard-Validierung")
                #endif
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .mismatch(let actual, let expected):
                #if DEBUG
                print("❌ [SSL] Zertifikat-Hash stimmt nicht überein! Erwartet: \(expected), Gefunden: \(actual)")
                #endif
                completionHandler(.cancelAuthenticationChallenge, nil)
            case .extractionFailed:
                #if DEBUG
                print("❌ [SSL] Konnte Zertifikat nicht extrahieren")
                #endif
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            #if DEBUG
            print("❌ [SSL] Nicht vertrauenswürdiger Host: \(host)")
            #endif
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

        #if DEBUG
        print("📋 [SSL] Zertifikat Hash für \(host): \(hashString)")
        #endif

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
        let task = session.dataTask(with: url)
        task.resume()
        // Session nach Aufgabenabschluss invalidieren, damit der Retain-Cycle
        // (URLSession → delegate → completion) aufgelöst wird.
        session.finishTasksAndInvalidate()
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