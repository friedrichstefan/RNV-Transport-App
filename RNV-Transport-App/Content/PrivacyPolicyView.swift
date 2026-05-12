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
            body: "Verantwortlich im Sinne der DSGVO:\n\nStefan Friedrich\nErnst-Reuter-Straße 17\n64823 Groß-Umstadt\nE-Mail: delta.corelabs@gmail.com\n\nDiese App ist ein nicht-kommerzielles Privatprojekt und steht in keiner Verbindung zur rnv GmbH oder anderen Verkehrsbetrieben. Ein Datenschutzbeauftragter ist nicht bestellt (§ 38 BDSG)."
        ),
        PolicySection(
            title: "2. Verarbeitete Daten & Zweck",
            body: "Die App verarbeitet folgende Daten:\n\n• Standortdaten (GPS) – zur Suche nahegelegener Haltestellen. Nur während der aktiven Nutzung erhoben, nicht dauerhaft gespeichert.\n• Abfragedaten (Start-/Zielhaltestelle, Uhrzeit) – für die Verbindungssuche über die öffentliche RNV-API.\n\nEs werden keine Nutzungsprofile erstellt und keine Werbung ausgespielt."
        ),
        PolicySection(
            title: "3. Rechtsgrundlagen (DSGVO)",
            body: "Die Verarbeitung deiner Standortdaten erfolgt auf Grundlage deiner ausdrücklichen Einwilligung (Art. 6 Abs. 1 lit. a DSGVO), die du über den iOS-Berechtigungsdialog erteilst. Du kannst diese Einwilligung jederzeit in den iOS-Systemeinstellungen widerrufen, ohne dass die Rechtmäßigkeit der bis dahin erfolgten Verarbeitung berührt wird."
        ),
        PolicySection(
            title: "4. API-Zugriffe auf externe Dienste",
            body: "Verbindungssuche und Abfahrtszeiten werden über die öffentliche GraphQL-API der rnv GmbH (rnv-online.de) abgerufen. Dabei werden Anfragen – einschließlich der gewählten Haltestellen – an deren Server übertragen. Es gelten die Datenschutzbestimmungen der rnv GmbH. Die App betreibt keine eigenen Server."
        ),
        PolicySection(
            title: "5. Lokal gespeicherte Daten",
            body: "Folgende Daten werden ausschließlich lokal auf deinem Gerät gespeichert (UserDefaults) und verlassen es nicht:\n\n• Zuletzt verwendete Haltestellen\n• App-Einstellungen (Suchradius, Verkehrsmittel-Filter)\n• Aktive Live-Activity-Informationen\n\nDu kannst diese Daten jederzeit über Einstellungen → Datenverwaltung → Cache leeren löschen."
        ),
        PolicySection(
            title: "6. Live Activities & Dynamic Island",
            body: "Live Activities zeigen Echtzeit-Fahrtinformationen auf dem Sperrbildschirm und in der Dynamic Island an. Die Verarbeitung erfolgt vollständig lokal auf deinem Gerät. Eine Übertragung an externe Dienste findet nicht statt."
        ),
        PolicySection(
            title: "7. Keine Weitergabe an Dritte",
            body: "Personenbezogene Daten werden nicht verkauft, vermietet oder für Werbezwecke an Dritte weitergegeben. Die App enthält keine Analyse-SDKs, Tracking-Bibliotheken oder eingebettete Social-Media-Plugins."
        ),
        PolicySection(
            title: "8. Deine Rechte (Art. 15–21 DSGVO)",
            body: "Du hast das Recht auf:\n\n• Auskunft über gespeicherte Daten (Art. 15)\n• Berichtigung unrichtiger Daten (Art. 16)\n• Löschung deiner Daten (Art. 17)\n• Einschränkung der Verarbeitung (Art. 18)\n• Datenübertragbarkeit (Art. 20)\n• Widerspruch gegen die Verarbeitung (Art. 21)\n• Widerruf einer Einwilligung – ohne Auswirkung auf bisherige Verarbeitung (Art. 7 Abs. 3)\n\nAnfragen richtest du bitte an: delta.corelabs@gmail.com"
        ),
        PolicySection(
            title: "9. Beschwerderecht (Art. 77 DSGVO)",
            body: "Du hast das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren. Zuständig ist:\n\nDer Hessische Beauftragte für Datenschutz und Informationsfreiheit (HBDI)\nGustav-Stresemann-Ring 1, 65189 Wiesbaden\ndatenschutz.hessen.de"
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
