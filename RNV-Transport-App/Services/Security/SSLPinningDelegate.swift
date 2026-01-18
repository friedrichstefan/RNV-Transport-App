//
//  SSLPinningDelegate.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on $(date +%d.%m.%y)
//

import Foundation
import Network
import CryptoKit

class SSLPinningDelegate: NSObject, URLSessionDelegate {
    
    // ✅ RNV GraphQL Server Certificate Fingerprint
    // HINWEIS: In Produktion würden Sie den echten Certificate Hash verwenden
    private let expectedCertificateHashes: [String: String] = [
        "graphql-sandbox-dds.rnv-online.de": "SHA256_HASH_PLACEHOLDER",
        "login.microsoftonline.com": "SHA256_HASH_PLACEHOLDER"
    ]
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        
        print("🔒 [SSL] Certificate validation für: \(challenge.protectionSpace.host)")
        
        // 1. Nur HTTPS-Verbindungen zulassen
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            print("❌ [SSL] Ungültige Authentifizierungsmethode")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // 2. Server Trust prüfen
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            print("❌ [SSL] Kein Server Trust verfügbar")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // 3. Basic Trust Evaluation
        var result: SecTrustResultType = .invalid
        let status = SecTrustEvaluate(serverTrust, &result)
        
        guard status == errSecSuccess else {
            print("❌ [SSL] Trust Evaluation fehlgeschlagen: \(status)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // 4. Für Development: Allowlist bekannter Hosts
        let trustedHosts = [
            "graphql-sandbox-dds.rnv-online.de",
            "login.microsoftonline.com"
        ]
        
        if trustedHosts.contains(challenge.protectionSpace.host) {
            print("✅ [SSL] Vertrauenswürdiger Host: \(challenge.protectionSpace.host)")
            
            // Certificate Pinning (vereinfacht für Demo)
            if validateCertificateChain(serverTrust: serverTrust, host: challenge.protectionSpace.host) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                print("⚠️ [SSL] Certificate Pinning fehlgeschlagen, verwende Standard-Validierung")
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            print("❌ [SSL] Nicht vertrauenswürdiger Host: \(challenge.protectionSpace.host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func validateCertificateChain(serverTrust: SecTrust, host: String) -> Bool {
        // 1. Certificate aus Trust Chain extrahieren
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            print("❌ [SSL] Kann Server-Zertifikat nicht extrahieren")
            return false
        }
        
        // 2. Certificate Data holen
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let data = CFDataGetBytePtr(serverCertData)
        let size = CFDataGetLength(serverCertData)
        let certData = Data(bytes: data!, count: size)
        
        // 3. SHA256 Hash berechnen
        let hash = SHA256.hash(data: certData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        print("📋 [SSL] Zertifikat Hash für \(host): \(hashString)")
        
        // 4. Mit erwarteten Hash vergleichen (für Demo: immer true)
        // In Produktion: return expectedCertificateHashes[host] == hashString
        return true
    }
    
    // MARK: - Certificate Hash Extractor (für Setup)
    
    static func extractCertificateHash(for host: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://\(host)") else {
            completion(nil)
            return
        }
        
        let session = URLSession(configuration: .default, delegate: CertificateHashExtractor { hash in
            completion(hash)
        }, delegateQueue: nil)
        
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
        
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completion(nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let data = CFDataGetBytePtr(serverCertData)
        let size = CFDataGetLength(serverCertData)
        let certData = Data(bytes: data!, count: size)
        
        let hash = SHA256.hash(data: certData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        completion(hashString)
        completionHandler(.performDefaultHandling, nil)
    }
}
