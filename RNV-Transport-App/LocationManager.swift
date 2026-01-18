//
//  LocationManager.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // ✅ Auto-Request mit Permission-Check
    func autoRequestLocation() async {
        await requestPermission()
    }
    
    func requestPermission() async {
        await MainActor.run {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    func startLocationUpdates() {
        DispatchQueue.main.async {
            self.isLocating = true
        }
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        
        DispatchQueue.main.async {
            self.location = location.coordinate
            self.isLocating = false
            print("📍 [LOCATION] Standort aktualisiert: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
        
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startLocationUpdates()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [LOCATION] Fehler: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isLocating = false
        }
    }
}
