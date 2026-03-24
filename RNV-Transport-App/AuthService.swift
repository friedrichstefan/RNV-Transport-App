//  AuthService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import Combine

@MainActor
class AuthService: ObservableObject {
    @Published var accessToken: String?
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authError: String?

    private var tokenExpiryDate: Date?
    
    /// Laufende Authentifizierungs-Task – verhindert parallele Token-Requests
    private var activeAuthTask: Task<Void, Never>?

    // MARK: - Konfiguration (sicher, kein fatalError)

    private var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }

    private var clientSecret: String? {
        guard let secret = Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_SECRET") as? String,
              !secret.isEmpty, !secret.hasPrefix("$(") else { return nil }
        return secret
    }

    private var tenantID: String? {
        guard let tenant = Bundle.main.object(forInfoDictionaryKey: "RNV_TENANT_ID") as? String,
              !tenant.isEmpty, !tenant.hasPrefix("$(") else { return nil }
        return tenant
    }

    private var resource: String? {
        guard let res = Bundle.main.object(forInfoDictionaryKey: "RNV_RESOURCE") as? String,
              !res.isEmpty, !res.hasPrefix("$(") else { return nil }
        return res
    }

    // MARK: - Token Gültigkeit

    var isTokenValid: Bool {
        guard isAuthenticated, accessToken != nil else { return false }
        guard let expiry = tokenExpiryDate else { return false }
        // Token als ungültig betrachten 60 Sekunden vor Ablauf
        return Date() < expiry.addingTimeInterval(-60)
    }

    // MARK: - Auto Login

    func autoAuthenticate() async {
        if isTokenValid {
            #if DEBUG
            print("ℹ️ [AUTH] Token noch gültig, kein erneuter Login nötig")
            #endif
            return
        }
        if isAuthenticated && !isTokenValid {
            #if DEBUG
            print("🔄 [AUTH] Token abgelaufen, erneuere...")
            #endif
        }
        await authenticate()
    }

    // MARK: - Authentication

    func authenticate() async {
        // Wenn bereits eine Authentifizierung läuft, auf deren Ergebnis warten
        if let existingTask = activeAuthTask {
            await existingTask.value
            return
        }

        isAuthenticating = true
        authError = nil
        
        let task = Task { @MainActor [weak self] in
            await self?.performAuthentication()
            return
        }
        activeAuthTask = task
        await task.value
        activeAuthTask = nil
    }
    
    private func performAuthentication() async {

        // Konfiguration prüfen
        guard let id = clientID else {
            setError("RNV_CLIENT_ID ist nicht konfiguriert. Überprüfe die .xcconfig-Datei.")
            return
        }
        guard let secret = clientSecret else {
            setError("RNV_CLIENT_SECRET ist nicht konfiguriert. Überprüfe die .xcconfig-Datei.")
            return
        }
        guard let tenant = tenantID else {
            setError("RNV_TENANT_ID ist nicht konfiguriert. Überprüfe die .xcconfig-Datei.")
            return
        }
        guard let res = resource else {
            setError("RNV_RESOURCE ist nicht konfiguriert. Überprüfe die .xcconfig-Datei.")
            return
        }

        let urlString = "https://login.microsoftonline.com/\(tenant)/oauth2/token"

        guard let url = URL(string: urlString) else {
            setError("Ungültige Auth-URL.")
            return
        }

        // URL-encode alle Werte, um Sonderzeichen im Request-Body zu vermeiden
        guard let encodedID     = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedRes    = res.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            setError("Fehler beim URL-Encoding der Credentials.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "grant_type=client_credentials&client_id=\(encodedID)&client_secret=\(encodedSecret)&resource=\(encodedRes)"
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                setError("Auth-Server antwortete mit Status \(httpResponse.statusCode).")
                return
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["access_token"] as? String {
                    // Token-Ablaufzeit berechnen (Standard: 3600 Sekunden)
                    let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
                    let expiry = Date().addingTimeInterval(expiresIn)

                    self.accessToken = token
                    self.tokenExpiryDate = expiry
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                    self.authError = nil
                    #if DEBUG
                    print("✅ [AUTH] Anmeldung erfolgreich. Token läuft ab um: \(expiry)")
                    #endif
                } else if let errorDesc = json["error_description"] as? String {
                    setError("Auth-Fehler: \(errorDesc)")
                } else {
                    setError("Unbekannte Auth-Antwort vom Server.")
                }
            } else {
                // JSON konnte nicht als Dictionary geparst werden (z.B. leere oder unerwartete Antwort)
                setError("Ungültiges Antwortformat vom Auth-Server.")
            }
        } catch {
            setError("Netzwerkfehler: \(error.localizedDescription)")
        }
    }

    // MARK: - Hilfsfunktionen

    private func setError(_ message: String) {
        #if DEBUG
        print("❌ [AUTH] \(message)")
        #endif
        self.authError = message
        self.isAuthenticating = false
        self.isAuthenticated = false
    }

    func logout() {
        accessToken = nil
        tokenExpiryDate = nil
        isAuthenticated = false
        authError = nil
        #if DEBUG
        print("🔓 [AUTH] Abgemeldet")
        #endif
    }
}
