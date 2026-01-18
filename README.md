> 👉 **English version below:** [Jump to English](#rnv-transport-app-english-🚌💨)

# <a name="rnv-app"></a>RNV-Transport-App 🚌💨


![App Logo Placeholder](https://via.placeholder.com/150/007AFF/FFFFFF?text=RNV)

**Deine Echtzeit-RNV-Reisebegleitung mit Live Activities**

Diese iOS-App bietet eine nahtlose Möglichkeit, Verbindungen im RNV-Netz zu suchen, detaillierte Reiseinformationen abzurufen und ausgewählte Fahrten in Echtzeit über **Apple Live Activities** zu verfolgen – direkt auf deinem Sperrbildschirm oder in der Dynamic Island.

> [!NOTE]
> Dies ist ein **Studentenprojekt**, das darauf abzielt, die Nutzung von Live-Daten der RNV-API in einer modernen iOS-Applikation zu demonstrieren und die Möglichkeiten von Live Activities in der Praxis zu erforschen.

---

## 🌟 Features

### 🔍 Intelligente Verbindungssuche
* **Standortbasiert:** Suche nach Haltestellen in deiner Nähe basierend auf deinem aktuellen GPS-Standort.
* **Live-Vorschläge:** Textbasierte Haltestellensuche mit Debounce-Funktion für eine flüssige Eingabe.
* **Einfaches UI:** Intuitive Auswahl von Start- und Zielhaltestellen.

### ⚡ Live Activities (Sperrbildschirm & Dynamic Island)
* **Echtzeit-Tracking:** Verfolge den Status deiner Verbindung mit automatischen Updates.
* **Phasenbasierte Darstellung:**
    * **Vor Abfahrt:** Countdown bis zur Abfahrt & Statusanzeige (Pünktlich/Verspätet).
    * **Während der Fahrt:** Fortschrittsanzeige, aktuelle Station, ETA und Verspätungsmeldungen.
    * **Angekommen:** Ziel-Bestätigung mit interaktivem "Beenden"-Button.
* **Direkte Interaktion:** Beende eine Live Activity direkt aus der Dynamic Island, ohne die App zu öffnen.
* **Synchronisation:** Automatischer Abgleich zwischen App-Toggle und Activity-Status.

### 📋 Detaillierte Reiseinformationen
* Übersicht über Start-/Endzeiten, Umstiege und einzelne Fahrtabschnitte (Legs).
* Anzeige von Service-Typen (Straßenbahn, Bus, S-Bahn) inklusive Liniennamen.
* Echtzeit-Verspätungsanzeige für jeden einzelnen Abschnitt.

### ⚙️ Benutzerfreundliche Einstellungen
* Anpassung von Suchradius und maximaler Anzahl von Verbindungen.
* Auswahl bevorzugter Verkehrsmittel.
* **Entwicklermodus:** Test-Koordinaten für die Haltestellensuche verwenden.
* Volle Unterstützung für **Dark Mode**.

---

## 🛠️ Technologie-Stack

| Technologie | Einsatzbereich |
| :--- | :--- |
| **SwiftUI** | Deklaratives UI-Framework |
| **ActivityKit** | Implementierung von Live Activities |
| **AppIntents** | Interaktion mit Live Activities & Widgets |
| **CoreLocation** | GPS-basierte Standortbestimmung |
| **GraphQL** | Anbindung an die RNV-API |
| **Combine** | Reaktive Datenflüsse & Asynchronität |
| **Azure AD** | Client Credentials Flow (Authentifizierung) |

* **Mindest-iOS-Version:** iOS 16.2+

---

## 🚀 Einrichtung des Projekts

Befolge diese Schritte, um das Projekt lokal einzurichten:

### 1. Klonen des Repositorys
```bash
git clone [https://github.com/dein-github-name/RNV-Transport-App.git](https://github.com/dein-github-name/RNV-Transport-App.git)
cd RNV-Transport-App
```

### 2. API-Authentifizierung einrichten

Ersetze die Platzhalter in der Datei `RNV-Transport-App/AuthService.swift` mit deinen tatsächlichen Anmeldedaten aus dem Azure Portal:

```swift
// RNV-Transport-App/AuthService.swift
private let clientID = "DEIN_CLIENT_ID_HIER" 
private let clientSecret = "DEIN_CLIENT_SECRET_HIER"
private let tenantID = "DEIN_TENANT_ID_HIER"
private let resource = "DEINE_RESOURCE_ID_HIER"
```

### 3. App Groups konfigurieren

Damit die Haupt-App und die Live Activity Extension Daten austauschen können (z. B. für den Status-Sync), ist eine gemeinsame App Group erforderlich:

* [ ] **Haupt-Target einstellen:** Wähle das Target `RNV-Transport-App` -> **Signing & Capabilities**.
* [ ] **Capability hinzufügen:** Klicke auf das **+** Symbol (Capability) und füge eine **App Group** hinzu (z. B. `group.com.yourcompany.rnvapp`).
* [ ] **Extension-Target einstellen:** Wiederhole diesen Vorgang für das Target `RNVLiveActivity` und stelle sicher, dass du **exakt dieselbe** Group-ID auswählst.
* [ ] **Code aktualisieren:** Hinterlege die ID in der Datei `LiveActivityState.swift`:

```swift
// RNV-Transport-App/LiveActivityState.swift
private let appGroupID = "group.com.yourcompany.rnvapp"
```
### 4. Standortdienste (Info.plist)

Füge die folgenden Keys zu deiner `Info.plist` hinzu, um den GPS-Zugriff zu ermöglichen:

* **Privacy - Location When In Use Usage Description**: "Wir benötigen deinen Standort, um nahegelegene Haltestellen zu finden."
* **Privacy - Location Always and When In Use Usage Description**: "Wir benötigen deinen Standort für Live-Updates während deiner Fahrt."

---

## 👨‍💻 Verwendung

* **Suche:** Nutze deinen aktuellen GPS-Standort oder die manuelle Suche, um deine Route zu finden.
* **Tracken:** Aktiviere bei der gewünschten Verbindung den **"Live-Verfolgung" Toggle**.
* **Live Activity:** Verfolge Echtzeit-Updates direkt auf dem Sperrbildschirm oder in der Dynamic Island.
* **Beenden:** Klicke auf den roten **"Beenden"-Button** in der Dynamic Island oder deaktiviere den Toggle direkt in der App.

---

## 📸 Screenshots

*(Coming Soon!)*

---

## 🤝 Contributing

Beiträge sind herzlich willkommen! Fühl dich frei, das Projekt zu **forken**, **Issues** zu erstellen oder **Pull Requests** mit Verbesserungen einzureichen. Jeder Beitrag hilft, die App besser zu machen!

---

## 📄 License

Dieses Projekt ist unter der **MIT-Lizenz** lizenziert – siehe die [LICENSE](LICENSE) Datei für Details.



# RNV Transport App (English) 🚌💨

![App Logo Placeholder](https://via.placeholder.com/150/007AFF/FFFFFF?text=RNV)

**Your real-time RNV travel companion with Live Activities**

This iOS app provides a seamless way to search for connections within the RNV network, access detailed trip information, and track selected journeys in real time using **Apple Live Activities** — directly on your lock screen or in the Dynamic Island.

> [!NOTE]
> This is a **student project** aimed at demonstrating the use of live data from the RNV API in a modern iOS application and exploring the practical capabilities of Live Activities.

---

## 🌟 Features

### 🔍 Smart Connection Search
* **Location-based:** Find nearby stops using your current GPS location.
* **Live suggestions:** Text-based stop search with debounce for smooth input.
* **Simple UI:** Intuitive selection of origin and destination stops.

### ⚡ Live Activities (Lock Screen & Dynamic Island)
* **Real-time tracking:** Monitor your trip status with automatic updates.
* **Phase-based display:**
    * **Before departure:** Countdown to departure & status (on time/delayed).
    * **During the trip:** Progress indicator, current stop, ETA, and delay notices.
    * **Arrived:** Destination confirmation with an interactive “End” button.
* **Direct interaction:** End a Live Activity directly from the Dynamic Island without opening the app.
* **Synchronization:** Automatic sync between the in-app toggle and the Live Activity state.

### 📋 Detailed Trip Information
* Overview of start/end times, transfers, and individual journey legs.
* Display of transport types (tram, bus, suburban train) including line names.
* Real-time delay information for each leg.

### ⚙️ User-Friendly Settings
* Adjust search radius and maximum number of connections.
* Select preferred modes of transport.
* **Developer mode:** Use test coordinates for stop search.
* Full **Dark Mode** support.

## 🛠️ Technology Stack

| Technology | Purpose |
| :--- | :--- |
| **SwiftUI** | Declarative UI framework |
| **ActivityKit** | Live Activities implementation |
| **AppIntents** | Interaction with Live Activities & widgets |
| **CoreLocation** | GPS-based location services |
| **GraphQL** | RNV API integration |
| **Combine** | Reactive data streams & async handling |
| **Azure AD** | Client Credentials Flow (authentication) |

* **Minimum iOS version:** iOS 16.2+

---

## 🚀 Project Setup

Follow these steps to set up the project locally:

### 1. Clone the Repository
```bash
git clone https://github.com/your-github-name/RNV-Transport-App.git
cd RNV-Transport-App
```
### 2. Configure API Authentication

Replace the placeholders in  
`RNV-Transport-App/AuthService.swift`  
with your actual credentials from the Azure Portal:

```swift
private let clientID = "YOUR_CLIENT_ID"
private let clientSecret = "YOUR_CLIENT_SECRET"
private let tenantID = "YOUR_TENANT_ID"
private let resource = "YOUR_RESOURCE_ID"
```

### 3. Configure App Groups

To allow data sharing between the main app and the Live Activity extension (e.g. for state synchronization), a shared App Group is required:

* Open **Signing & Capabilities** for the `RNV-Transport-App` target
* Add an **App Group** (e.g. `group.com.yourcompany.rnvapp`)
* Repeat the same steps for the `RNVLiveActivity` target and make sure to select **exactly the same** App Group ID
* Update the App Group ID in `LiveActivityState.swift`:

```swift
private let appGroupID = "group.com.yourcompany.rnvapp"
```
### 4. Location Services (Info.plist)

Add the following keys to your `Info.plist` to enable GPS access:

* **Privacy - Location When In Use Usage Description**  
  "We need your location to find nearby stops."
* **Privacy - Location Always and When In Use Usage Description**  
  "We need your location for live updates during your trip."
## 👨‍💻 Usage

* **Search:** Find routes using your current GPS location or manual input
* **Track:** Enable the **“Live Tracking” toggle** for a selected connection
* **Live Activity:** View real-time updates on the lock screen or in the Dynamic Island
* **End:** Tap the red **“End” button** in the Dynamic Island or disable the toggle in the app


## 📸 Screenshots

*(Coming Soon!)*

---

## 🤝 Contributing

Contributions are welcome!  
Feel free to **fork** the project, open **issues**, or submit **pull requests** with improvements.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
