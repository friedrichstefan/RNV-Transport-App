//
//  EncryptSecretsScript.swift
//  RNV-Transport-App
//
//  EINMALIG AUSFÜHREN: Verschlüsselt Secrets aus Secrets.xcconfig
//  Danach die generierte EncryptedSecrets.json ins Projekt kopieren
//

import Foundation

/// WICHTIG: Diese Funktion nur einmal während des Setups aufrufen!
/// Danach die Ausgabe in EncryptedSecrets.json speichern
func generateEncryptedSecretsJSON() {
    do {
        let jsonString = try SecureConfigurationManager.shared.generateEncryptedSecretsFile()
        print("📄 Verschlüsselte Secrets (als EncryptedSecrets.json speichern):\n")
        print(jsonString)
        print("\n✅ Kopiere diesen Inhalt in eine neue Datei 'EncryptedSecrets.json' im Projekt")
    } catch {
        print("❌ Fehler beim Verschlüsseln: \(error.localizedDescription)")
    }
}

// Nur in Debug-Builds verfügbar
#if DEBUG
// Aufrufen in einem Test oder temporär in AppDelegate/SceneDelegate:
// generateEncryptedSecretsJSON()
#endif
