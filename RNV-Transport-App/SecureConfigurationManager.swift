//
//  SecureConfigurationManager.swift
//  RNV-Transport-App
//
//  Verwaltet verschlüsselte Konfigurationswerte
//

import Foundation

/// Verwaltet verschlüsselte App-Secrets
/// Secrets sind in EncryptedSecrets.json verschlüsselt gespeichert
class SecureConfigurationManager {
    
    static let shared = SecureConfigurationManager()
    
    private var decryptedSecrets: [String: String] = [:]
    private let encryptionService = EncryptionService.shared
    
    private init() {
        loadAndDecryptSecrets()
    }
    
    // MARK: - Public Accessors
    
    var clientID: String? {
        decryptedSecrets["RNV_CLIENT_ID"]
    }
    
    var clientSecret: String? {
        decryptedSecrets["RNV_CLIENT_SECRET"]
    }
    
    var tenantID: String? {
        decryptedSecrets["RNV_TENANT_ID"]
    }
    
    var resource: String? {
        decryptedSecrets["RNV_RESOURCE"]
    }
    
    var graphQLURL: String? {
        decryptedSecrets["RNV_GRAPHQL_URL"]
    }
    
    var signingKey: String? {
        decryptedSecrets["RNV_SIGNING_KEY"]
    }
    
    // MARK: - Loading & Decryption
    
    private func loadAndDecryptSecrets() {
        // 1. Versuche verschlüsselte Datei zu laden
        guard let encryptedData = loadEncryptedSecretsFile() else {
            #if DEBUG
            print("⚠️ [SecureConfig] Keine verschlüsselte Secrets-Datei gefunden - verwende Fallback")
            #endif
            loadFallbackFromInfoPlist()
            return
        }
        
        // 2. Entschlüssele
        do {
            let decrypted = try encryptionService.decryptDictionary(encryptedData)
            self.decryptedSecrets = decrypted
            #if DEBUG
            print("✅ [SecureConfig] \(decrypted.count) Secrets erfolgreich entschlüsselt")
            #endif
        } catch {
            #if DEBUG
            print("❌ [SecureConfig] Entschlüsselung fehlgeschlagen: \(error.localizedDescription)")
            #endif
            loadFallbackFromInfoPlist()
        }
    }
    
    /// Lädt verschlüsselte Secrets aus EncryptedSecrets.json
    private func loadEncryptedSecretsFile() -> [String: String]? {
        guard let url = Bundle.main.url(forResource: "EncryptedSecrets", withExtension: "json") else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        
        return json
    }
    
    /// Fallback: Lädt Secrets aus Info.plist (für Entwicklung)
    private func loadFallbackFromInfoPlist() {
        #if DEBUG
        print("🔓 [SecureConfig] Verwende unverschlüsselte Werte aus Info.plist (nur für Entwicklung!)")
        #endif
        
        decryptedSecrets = [
            "RNV_CLIENT_ID": Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") as? String ?? "",
            "RNV_CLIENT_SECRET": Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_SECRET") as? String ?? "",
            "RNV_TENANT_ID": Bundle.main.object(forInfoDictionaryKey: "RNV_TENANT_ID") as? String ?? "",
            "RNV_RESOURCE": Bundle.main.object(forInfoDictionaryKey: "RNV_RESOURCE") as? String ?? "",
            "RNV_GRAPHQL_URL": Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") as? String ?? "",
            "RNV_SIGNING_KEY": Bundle.main.object(forInfoDictionaryKey: "RNV_SIGNING_KEY") as? String ?? ""
        ]
    }
    
    // MARK: - Encryption Helper (für Entwickler)
    
    /// Hilfsfunktion: Verschlüsselt die aktuellen Secrets aus Info.plist
    /// Nur für Setup - nicht in Production verwenden!
    func generateEncryptedSecretsFile() throws -> String {
        let secrets = [
            "RNV_CLIENT_ID": Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") as? String ?? "",
            "RNV_CLIENT_SECRET": Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_SECRET") as? String ?? "",
            "RNV_TENANT_ID": Bundle.main.object(forInfoDictionaryKey: "RNV_TENANT_ID") as? String ?? "",
            "RNV_RESOURCE": Bundle.main.object(forInfoDictionaryKey: "RNV_RESOURCE") as? String ?? "",
            "RNV_GRAPHQL_URL": Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") as? String ?? "",
            "RNV_SIGNING_KEY": Bundle.main.object(forInfoDictionaryKey: "RNV_SIGNING_KEY") as? String ?? ""
        ]
        
        let encrypted = try encryptionService.encryptDictionary(secrets)
        let jsonData = try JSONEncoder().encode(encrypted)
        
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EncryptionError.encodingFailed
        }
        
        return jsonString
    }
}

extension EncryptionError {
    static let encodingFailed = EncryptionError.decodingFailed
}
