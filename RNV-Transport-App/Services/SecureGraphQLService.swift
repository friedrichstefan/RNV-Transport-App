//
//  SecureGraphQLService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on $(date +%d.%m.%y)
//

import Foundation
import Combine

class SecureGraphQLService: GraphQLService {
    
    private let sslDelegate = SSLPinningDelegate()
    private let requestSigner = RequestSigningHelper()
    
    private lazy var secureSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // Security Headers
        config.httpAdditionalHeaders = [
            "User-Agent": "RNVApp/1.0 iOS",
            "Accept": "application/json",
            "Cache-Control": "no-cache"
        ]
        
        return URLSession(configuration: config, delegate: sslDelegate, delegateQueue: nil)
    }()
    
    // MARK: - Override: Sichere Query Execution
    
    override internal func executeQuery(query: String, accessToken: String, completion: @escaping (Data) -> Void) async {
        
        guard let url = URL(string: baseURL) else {
            print("❌ [SECURE_GQL] Ungültige URL")
            await MainActor.run { self.isLoading = false }
            return
        }
        
        // Rate Limiting prüfen
        guard requestSigner.canMakeRequest(to: url.host ?? "") else {
            print("⚠️ [SECURE_GQL] Rate Limit erreicht")
            await MainActor.run { self.isLoading = false }
            return
        }
        
        // Request erstellen
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Body erstellen und signieren
        let body = ["query": query]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ [SECURE_GQL] JSON Serialization Fehler")
            await MainActor.run { self.isLoading = false }
            return
        }
        
        request.httpBody = bodyData
        
        // Request signieren
        requestSigner.signRequest(&request, withBody: bodyData)
        
        do {
            print("🔒 [SECURE_GQL] Sichere Anfrage an: \(url.host ?? "")")
            
            let (data, response) = try await secureSession.data(for: request)
            
            // Response validieren
            guard requestSigner.validateResponse(response, data: data) else {
                print("❌ [SECURE_GQL] Response Validation fehlgeschlagen")
                await MainActor.run { self.isLoading = false }
                return
            }
            
            // Response-Logging (nur in Debug)
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📡 [SECURE_GQL] Response: \(jsonString.prefix(200))...")
            }
            #endif
            
            completion(data)
            
        } catch {
            print("❌ [SECURE_GQL] Netzwerkfehler: \(error.localizedDescription)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    // MARK: - Certificate Hash Setup (für Entwicklung)
    
    func setupCertificatePinning() {
        print("🔧 [SETUP] Certificate Pinning wird konfiguriert...")
        
        SSLPinningDelegate.extractCertificateHash(for: "graphql-sandbox-dds.rnv-online.de") { hash in
            if let hash = hash {
                print("📋 [SETUP] RNV GraphQL Certificate Hash: \(hash)")
                print("📋 [SETUP] Fügen Sie diesen Hash in SSLPinningDelegate.swift ein")
            }
        }
        
        SSLPinningDelegate.extractCertificateHash(for: "login.microsoftonline.com") { hash in
            if let hash = hash {
                print("📋 [SETUP] Microsoft Certificate Hash: \(hash)")
                print("📋 [SETUP] Fügen Sie diesen Hash in SSLPinningDelegate.swift ein")
            }
        }
    }
}
