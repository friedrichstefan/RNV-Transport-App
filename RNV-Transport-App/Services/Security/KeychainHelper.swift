//
//  KeychainHelper.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on $(date +%d.%m.%y)
//

import Foundation
import Security

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
