//
//  RequestSigningHelper.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on $(date +%d.%m.%y)
//

import Foundation
import CryptoKit

class RequestSigningHelper {
    
    // ✅ App-spezifischer Signing Key (in Produktion aus Keychain)
    private let signingKey = "RNV_APP_SIGNING_KEY_2026"
    
    // MARK: - Request Signing
    
    func signRequest(_ request: inout URLRequest, withBody body: Data? = nil) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        
        // Signature Payload erstellen
        var signatureComponents: [String] = [
            request.httpMethod ?? "GET",
            request.url?.absoluteString ?? "",
            timestamp,
            nonce
        ]
        
        // Body hinzufügen wenn vorhanden
        if let body = body {
            let bodyHash = SHA256.hash(data: body)
            let bodyHashString = bodyHash.compactMap { String(format: "%02x", $0) }.joined()
            signatureComponents.append(bodyHashString)
        }
        
        let signaturePayload = signatureComponents.joined(separator: "|")
        
        // HMAC-SHA256 Signature
        let signature = generateHMACSignature(payload: signaturePayload)
        
        // Headers setzen
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.setValue("1.0", forHTTPHeaderField: "X-API-Version")
        
        print("🔐 [SIGN] Request signiert: \(request.url?.host ?? "unknown")")
    }
    
    private func generateHMACSignature(payload: String) -> String {
        let key = SymmetricKey(data: Data(signingKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(signature).base64EncodedString()
    }
    
    // MARK: - Request Validation
    
    func validateResponse(_ response: URLResponse, data: Data) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        // 1. Status Code prüfen
        guard 200...299 ~= httpResponse.statusCode else {
            print("⚠️ [VALIDATE] Ungültiger Status Code: \(httpResponse.statusCode)")
            return false
        }
        
        // 2. Content-Type prüfen
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().contains("application/json") else {
            print("⚠️ [VALIDATE] Ungültiger Content-Type")
            return false
        }
        
        // 3. Response Size Limit
        guard data.count < 10_000_000 else { // 10MB Limit
            print("⚠️ [VALIDATE] Response zu groß: \(data.count) bytes")
            return false
        }
        
        // 4. JSON Struktur validieren
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            if let dict = json as? [String: Any] {
                // Erwartete GraphQL Struktur prüfen
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
    private let minimumRequestInterval: TimeInterval = 0.5 // 500ms zwischen Requests
    
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
