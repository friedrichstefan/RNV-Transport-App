//
//  AuthService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import Combine

class AuthService: ObservableObject {
    @Published var accessToken: String?
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    
    private var clientID: String {
            guard let id = Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") as? String,
                  !id.isEmpty else {
                fatalError("🚨 CONFIGURATION ERROR: RNV_CLIENT_ID ist nicht konfiguriert!\n" +
                          "Überprüfe deine .xcconfig Datei und stelle sicher, dass RNV_CLIENT_ID gesetzt ist.")
            }
            return id
        }
        
        private var clientSecret: String {
            guard let secret = Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_SECRET") as? String,
                  !secret.isEmpty else {
                fatalError("🚨 CONFIGURATION ERROR: RNV_CLIENT_SECRET ist nicht konfiguriert!\n" +
                          "Überprüfe deine .xcconfig Datei und stelle sicher, dass RNV_CLIENT_SECRET gesetzt ist.")
            }
            return secret
        }
        
        private var tenantID: String {
            guard let tenant = Bundle.main.object(forInfoDictionaryKey: "RNV_TENANT_ID") as? String,
                  !tenant.isEmpty else {
                fatalError("🚨 CONFIGURATION ERROR: RNV_TENANT_ID ist nicht konfiguriert!\n" +
                          "Überprüfe deine .xcconfig Datei und stelle sicher, dass RNV_TENANT_ID gesetzt ist.")
            }
            return tenant
        }
        
        private var resource: String {
            guard let res = Bundle.main.object(forInfoDictionaryKey: "RNV_RESOURCE") as? String,
                  !res.isEmpty else {
                fatalError("🚨 CONFIGURATION ERROR: RNV_RESOURCE ist nicht konfiguriert!\n" +
                          "Überprüfe deine .xcconfig Datei und stelle sicher, dass RNV_RESOURCE gesetzt ist.")
            }
            return res
        }
        
        // ✅ Optional: Validierung beim Service-Start
        init() {
            validateConfiguration()
        }
        
        // ✅ Configuration Validation (nur in Debug)
        private func validateConfiguration() {
            #if DEBUG
            print("🔐 [AUTH] Validiere RNV Konfiguration...")
            
            // Teste alle Required Keys ohne die Werte zu loggen
            let requiredConfigs = [
                ("RNV_CLIENT_ID", clientID),
                ("RNV_CLIENT_SECRET", clientSecret),
                ("RNV_TENANT_ID", tenantID),
                ("RNV_RESOURCE", resource)
            ]
            
            for (key, value) in requiredConfigs {
                if value.isEmpty {
                    print("❌ [AUTH] \(key): LEER!")
                } else {
                    // Nur ersten 8 Zeichen für Debug, Rest als ***
                    let preview = String(value.prefix(8)) + "***"
                    print("✅ [AUTH] \(key): \(preview) (konfiguriert)")
                }
            }
            
            print("✅ [AUTH] Alle Konfigurationen sind vorhanden")
            #endif
        }
    
    // ✅ Auto-Login beim Start
    func autoAuthenticate() async {
        guard !isAuthenticated else {
            print("ℹ️ [AUTH] Bereits angemeldet")
            return
        }
        
        await authenticate()
    }
    
    func authenticate() async {
        await MainActor.run {
            isAuthenticating = true
        }
        
        let urlString = "https://login.microsoftonline.com/\(tenantID)/oauth2/token"
        
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                isAuthenticating = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)&resource=\(resource)"
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                
                await MainActor.run {
                    self.accessToken = token
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                }
                
                print("✅ [AUTH] Anmeldung erfolgreich")
            }
        } catch {
            print("❌ [AUTH] Fehler: \(error)")
            await MainActor.run {
                isAuthenticating = false
            }
        }
    }
}



