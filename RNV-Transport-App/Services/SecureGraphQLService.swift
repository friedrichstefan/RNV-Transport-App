//
//  SecureGraphQLService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on $(date +%d.%m.%y)
//

import Foundation
import Combine

@MainActor
class SecureGraphQLService: GraphQLService {

    private let sslDelegate = SSLPinningDelegate()
    private let requestSigner = RequestSigningHelper()

    private lazy var secureSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfiguration.requestTimeout
        config.timeoutIntervalForResource = AppConfiguration.resourceTimeout
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        config.httpAdditionalHeaders = [
            "User-Agent": "OEPNVMannheim/1.1 iOS",
            "Accept": "application/json",
            "Cache-Control": "no-cache"
        ]

        return URLSession(configuration: config, delegate: sslDelegate, delegateQueue: nil)
    }()

    // MARK: - Override: Secure Query Execution

    override internal func executeQuery(query: String, accessToken: String) async throws -> Data {

        guard let url = URL(string: baseURL) else {
            throw GraphQLError(message: "Ungültige URL: \(baseURL)")
        }

        guard requestSigner.canMakeRequest(to: url.host ?? "") else {
            throw GraphQLError(message: "Rate Limit erreicht, bitte warten")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["query": query]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw GraphQLError(message: "JSON Serialization fehlgeschlagen")
        }

        request.httpBody = bodyData
        requestSigner.signRequest(&request, withBody: bodyData)

        #if DEBUG
        print("🔒 [SECURE_GQL] Sichere Anfrage an: \(url.host ?? "")")
        #endif

        let (data, response) = try await secureSession.data(for: request)

        guard requestSigner.validateResponse(response, data: data) else {
            throw GraphQLError(message: "Response Validation fehlgeschlagen")
        }

        if let httpResponse = response as? HTTPURLResponse {
            #if DEBUG
            print("📡 [SECURE_GQL] Response Status: \(httpResponse.statusCode)")
            #endif
            guard (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                if let body = String(data: data, encoding: .utf8) {
                    print("❌ [SECURE_GQL] Error body (\(httpResponse.statusCode)): \(body)")
                }
                #endif
                throw GraphQLError(message: "HTTP-Fehler: \(httpResponse.statusCode)")
            }
        }

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 [SECURE_GQL] Response: \(jsonString.prefix(200))...")
        }
        #endif

        return data
    }

    // MARK: - Certificate Hash Setup

    func setupCertificatePinning() {
        #if DEBUG
        print("🔧 [SETUP] Certificate Pinning wird konfiguriert...")
        #endif

        SSLPinningDelegate.extractCertificateHash(for: "graphql-sandbox-dds.rnv-online.de") { hash in
            if let hash = hash {
                #if DEBUG
                print("📋 [SETUP] GraphQL Certificate Hash: \(hash)")
                #endif
            }
        }

        SSLPinningDelegate.extractCertificateHash(for: "login.microsoftonline.com") { hash in
            if let hash = hash {
                #if DEBUG
                print("📋 [SETUP] Microsoft Certificate Hash: \(hash)")
                #endif
            }
        }
    }
}
