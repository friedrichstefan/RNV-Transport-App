//
//  EncryptionService.swift
//  RNV-Transport-App
//
//  AES-256-GCM Verschlüsselung zusätzlich zu Apple Keychain
//

import Foundation
import CryptoKit
import Security

/// Verschlüsselungsservice mit AES-256-GCM (Standard-Algorithmus)
/// Verwendet zusätzlich zur nativen Apple Keychain-Verschlüsselung
class EncryptionService {
    
    static let shared = EncryptionService()
    
    private let keychainService = "com.stefanfriedrich.rnvapp.encryption"
    private let masterKeyTag = "masterEncryptionKey"
    
    private init() {}
    
    // MARK: - Master Key Management
    
    /// Generiert oder lädt den Master-Verschlüsselungsschlüssel aus dem Keychain
    func getMasterKey() throws -> SymmetricKey {
        // Versuche, existierenden Key zu laden
        if let existingKey = try? loadKeyFromKeychain() {
            return existingKey
        }
        
        // Wenn kein Key existiert, generiere neuen
        let newKey = SymmetricKey(size: .bits256)
        try saveKeyToKeychain(newKey)
        return newKey
    }
    
    /// Speichert einen Schlüssel sicher im Keychain (Apple's native Verschlüsselung)
    private func saveKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Lösche alten Key falls vorhanden
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status: status)
        }
        
        #if DEBUG
        print("🔐 [Encryption] Master Key gespeichert im Keychain")
        #endif
    }
    
    /// Lädt den Schlüssel aus dem Keychain
    private func loadKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw EncryptionError.keychainError(status: status)
        }
        
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - AES-256-GCM Encryption/Decryption
    
    /// Verschlüsselt einen String mit AES-256-GCM
    func encrypt(_ plaintext: String) throws -> String {
        let key = try getMasterKey()
        let data = Data(plaintext.utf8)
        
        // AES-GCM Verschlüsselung
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        // Base64 kodieren für einfache Speicherung
        return combined.base64EncodedString()
    }
    
    /// Entschlüsselt einen AES-256-GCM verschlüsselten String
    func decrypt(_ ciphertext: String) throws -> String {
        let key = try getMasterKey()
        
        guard let combined = Data(base64Encoded: ciphertext) else {
            throw EncryptionError.invalidCiphertext
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decodingFailed
        }
        
        return plaintext
    }
    
    // MARK: - Batch Operations
    
    /// Verschlüsselt ein Dictionary von Strings
    func encryptDictionary(_ dict: [String: String]) throws -> [String: String] {
        var encrypted: [String: String] = [:]
        for (key, value) in dict {
            encrypted[key] = try encrypt(value)
        }
        return encrypted
    }
    
    /// Entschlüsselt ein Dictionary von Strings
    func decryptDictionary(_ dict: [String: String]) throws -> [String: String] {
        var decrypted: [String: String] = [:]
        for (key, value) in dict {
            decrypted[key] = try decrypt(value)
        }
        return decrypted
    }
}

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case keychainError(status: OSStatus)
    case encryptionFailed
    case decryptionFailed
    case invalidCiphertext
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain Fehler: \(status)"
        case .encryptionFailed:
            return "Verschlüsselung fehlgeschlagen"
        case .decryptionFailed:
            return "Entschlüsselung fehlgeschlagen"
        case .invalidCiphertext:
            return "Ungültiger verschlüsselter Text"
        case .decodingFailed:
            return "Dekodierung fehlgeschlagen"
        }
    }
}
