//
//  PrivacyPolicyView.swift
//  RNV-Transport-App
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(sections, id: \.title) { section in
                        privacySection(section)
                    }

                    Text("Stand: Mai 2026")
                        .font(.caption)
                        .foregroundColor(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(AppTheme.canvasAdaptive(colorScheme).ignoresSafeArea())
            .navigationTitle("Datenschutzerklärung")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(AppTheme.primaryColor)
                }
            }
        }
    }

    private func privacySection(_ section: PolicySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.inkAdaptive(colorScheme))

            Text(section.body)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.bodyTextAdaptive(colorScheme))
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }

    private let sections: [PolicySection] = [
        PolicySection(
            title: "1. Verantwortliche Stelle",
            body: "Diese App ist ein nicht-kommerzielles Studentenprojekt. Sie steht in keiner Verbindung zur rnv GmbH oder anderen Verkehrsbetrieben. Kontakt über das App-Store-Entwicklerprofil."
        ),
        PolicySection(
            title: "2. Standortdaten",
            body: "Die App fragt deinen Standort (\"Während der Nutzung\") an, um Haltestellen in deiner Nähe zu finden. Der Standort wird ausschließlich für die API-Anfrage an den RNV-Fahrplanserver verwendet und weder dauerhaft gespeichert noch an Dritte weitergegeben."
        ),
        PolicySection(
            title: "3. Keine eigenen Server",
            body: "Die App sendet Anfragen direkt an die öffentliche GraphQL-API der RNV (rnv-online.de). Es werden keine Daten an eigene Server des Entwicklers übertragen. Die Datenschutzbestimmungen der RNV gelten für diese API-Zugriffe."
        ),
        PolicySection(
            title: "4. Lokal gespeicherte Daten",
            body: "Folgende Daten werden ausschließlich lokal auf deinem Gerät gespeichert (UserDefaults):\n• Zuletzt verwendete Haltestellen\n• App-Einstellungen (Suchradius, Verkehrsmittel-Filter)\n• Aktive Live-Activity-Informationen\n\nDiese Daten verlassen dein Gerät nicht."
        ),
        PolicySection(
            title: "5. Live Activities & Dynamic Island",
            body: "Live Activities zeigen Echtzeit-Fahrtinformationen auf dem Sperrbildschirm und im Dynamic Island an. Diese Daten werden lokal verarbeitet und nicht an externe Dienste übertragen."
        ),
        PolicySection(
            title: "6. Keine Weitergabe an Dritte",
            body: "Personenbezogene Daten werden nicht an Dritte weitergegeben, verkauft oder für Werbezwecke genutzt. Die App enthält keine Tracking-SDKs oder Analyse-Bibliotheken."
        ),
        PolicySection(
            title: "7. Deine Rechte",
            body: "Du kannst alle lokal gespeicherten Daten jederzeit über Einstellungen → Datenverwaltung → Cache leeren entfernen. Den Standortzugriff kannst du in den iOS-Systemeinstellungen jederzeit widerrufen."
        )
    ]
}

private struct PolicySection {
    let title: String
    let body: String
}

#Preview {
    PrivacyPolicyView()
}
