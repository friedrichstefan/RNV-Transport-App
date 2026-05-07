#!/usr/bin/env ruby
# Fügt den watchOS-Target "RNVWatch" zum Xcode-Projekt hinzu.

require 'xcodeproj'

PROJECT_PATH  = File.join(__dir__, 'Mannheim ÖPNV.xcodeproj')
WATCH_DIR     = File.join(__dir__, 'RNVWatch')
BUNDLE_PREFIX = 'com.stefanfriedrich.rnvapp'
APP_GROUP     = 'group.com.stefanfriedrich.rnvapp'
DEPLOYMENT    = '7.0'
SWIFT_VERSION = '5.9'

proj = Xcodeproj::Project.open(PROJECT_PATH)

# ---------------------------------------------------------------
# 1. Bereits vorhandenen Target entfernen (idempotent)
# ---------------------------------------------------------------
proj.targets.select { |t| t.name == 'RNVWatch' }.each { |t| t.remove_from_project }

# ---------------------------------------------------------------
# 2. watchOS App-Target anlegen
# ---------------------------------------------------------------
watch_target = proj.new_target(
  :watch2_app,
  'RNVWatch',
  :watchos,
  DEPLOYMENT
)

# ---------------------------------------------------------------
# 3. Build-Settings
# ---------------------------------------------------------------
watch_target.build_configurations.each do |config|
  s = config.build_settings
  s['SWIFT_VERSION']                   = SWIFT_VERSION
  s['PRODUCT_BUNDLE_IDENTIFIER']       = "#{BUNDLE_PREFIX}.watch"
  s['TARGETED_DEVICE_FAMILY']          = '4'   # watchOS only
  s['WATCHOS_DEPLOYMENT_TARGET']       = DEPLOYMENT
  s['ENABLE_BITCODE']                  = 'NO'
  s['SWIFT_EMIT_LOC_STRINGS']          = 'YES'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['LD_RUNPATH_SEARCH_PATHS']         = ['$(inherited)', '@executable_path/Frameworks']
  # App Group
  s['ENABLE_USER_SCRIPT_SANDBOXING']   = 'NO'
end

# ---------------------------------------------------------------
# 4. Gruppe im Projekt-Navigator anlegen
# ---------------------------------------------------------------
watch_group = proj.main_group.find_subpath('RNVWatch', true)
watch_group.set_source_tree('<group>')
watch_group.set_path('RNVWatch')

views_group = watch_group.find_subpath('Views', true)
views_group.set_source_tree('<group>')
views_group.set_path('Views')

# ---------------------------------------------------------------
# 5. Swift-Quelldateien eintragen
# ---------------------------------------------------------------
root_files = %w[
  WatchApp.swift
  WatchModels.swift
  WatchDataManager.swift
  WatchConnectivityManager.swift
]

view_files = %w[
  ContentView.swift
  ActiveTripView.swift
  SavedTripsView.swift
  DeparturesView.swift
]

root_files.each do |name|
  path = File.join(WATCH_DIR, name)
  ref  = watch_group.new_file(path)
  watch_target.add_file_references([ref])
end

view_files.each do |name|
  path = File.join(WATCH_DIR, 'Views', name)
  ref  = views_group.new_file(path)
  watch_target.add_file_references([ref])
end

# ---------------------------------------------------------------
# 6. WatchConnectivity framework verknüpfen
# ---------------------------------------------------------------
watch_target.add_system_framework('WatchConnectivity')
watch_target.add_system_framework('Foundation')
watch_target.add_system_framework('SwiftUI')

# ---------------------------------------------------------------
# 7. App Group Entitlement (wird als Info in Settings gesetzt)
#    – eigene .entitlements-Datei anlegen
# ---------------------------------------------------------------
entitlements_path = File.join(WATCH_DIR, 'RNVWatch.entitlements')
unless File.exist?(entitlements_path)
  File.write(entitlements_path, <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>com.apple.security.application-groups</key>
        <array>
            <string>#{APP_GROUP}</string>
        </array>
    </dict>
    </plist>
  XML
  puts "✅ Entitlements-Datei erstellt: #{entitlements_path}"
end

entitlements_ref = watch_group.new_file(entitlements_path)
watch_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "RNVWatch/RNVWatch.entitlements"
end

# ---------------------------------------------------------------
# 8. Info.plist anlegen
# ---------------------------------------------------------------
info_plist_path = File.join(WATCH_DIR, 'Info.plist')
unless File.exist?(info_plist_path)
  File.write(info_plist_path, <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDisplayName</key>
        <string>Mannheim ÖPNV</string>
        <key>CFBundleExecutable</key>
        <string>$(EXECUTABLE_NAME)</string>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>CFBundleName</key>
        <string>$(PRODUCT_NAME)</string>
        <key>CFBundlePackageType</key>
        <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>WKApplication</key>
        <true/>
        <key>WKWatchOnly</key>
        <false/>
    </dict>
    </plist>
  XML
  puts "✅ Info.plist erstellt: #{info_plist_path}"
end

watch_target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'RNVWatch/Info.plist'
end

# ---------------------------------------------------------------
# 9. WatchConnectivity auch zum iPhone-Target hinzufügen
# ---------------------------------------------------------------
iphone_target = proj.targets.find { |t| t.name == 'RNV-Transport-App' }
if iphone_target
  existing_frameworks = iphone_target.frameworks_build_phase.files.map { |f| f.file_ref.name rescue nil }.compact
  unless existing_frameworks.include?('WatchConnectivity.framework')
    iphone_target.add_system_framework('WatchConnectivity')
    puts "✅ WatchConnectivity zum iPhone-Target hinzugefügt"
  else
    puts "ℹ️  WatchConnectivity bereits im iPhone-Target vorhanden"
  end

  # PhoneConnectivityManager.swift liegt im RNV-Transport-App-Verzeichnis.
  # Bei PBXFileSystemSynchronizedRootGroup übernimmt Xcode die Datei automatisch –
  # kein manuelles Hinzufügen nötig.
  puts "ℹ️  PhoneConnectivityManager.swift wird durch Synchronized-Gruppe automatisch eingebunden"
end

# ---------------------------------------------------------------
# 10. Projekt speichern
# ---------------------------------------------------------------
proj.save
puts "✅ Projekt gespeichert: #{PROJECT_PATH}"
puts ""
puts "Nächste Schritte in Xcode:"
puts "  1. Signing & Capabilities → App Groups aktivieren (#{APP_GROUP})"
puts "  2. Watch-Target als Companion des iPhone-Targets konfigurieren"
puts "  3. Build & Run auf Simulator (watchOS)"
