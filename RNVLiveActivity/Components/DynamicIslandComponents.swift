//
//  DynamicIslandComponents.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import SwiftUI
import ActivityKit
import AppIntents

// ========================================
// MARK: - Dynamic Island: Expanded Leading
// ========================================

struct DynamicIslandExpandedLeading: View {
    let serviceType: String
    let lineName: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: StyleHelper.getIcon(for: serviceType))
                .font(.system(size: 12, weight: .medium))
            Text(StyleHelper.getShortName(from: lineName))
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(StyleHelper.getColor(for: serviceType)))
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
    }
}

// ========================================
// MARK: - Dynamic Island: Expanded Trailing
// ========================================

struct DynamicIslandExpandedTrailing: View {
    let delay: Int?
    let phase: TripPhase
    
    var body: some View {
        Group {
            if phase == .arrived {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    Text("Angekommen").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                .foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(Color.green))
                .frame(width: 110, alignment: .trailing)
            } else if let delay = delay, delay > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 10))
                    Text("+\(delay) min").font(.system(size: 12, weight: .bold)).lineLimit(1)
                }
                .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.red))
                .frame(width: 110, alignment: .trailing)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    Text("Pünktlich").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                .foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(Color.green))
                .frame(width: 110, alignment: .trailing)
            }
        }
        .padding(.trailing, 8)
    }
}

// ========================================
// MARK: - Dynamic Island: Angekommen Bottom View
// ========================================

struct DynamicIslandArrivedBottom: View {
    let startStation: String
    let endStation: String
    let tripId: String
    
    var body: some View {
        VStack(spacing: 12) {
            // Strecken-Info
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VON").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                    Text(startStation).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right").font(.system(size: 11))
                    .foregroundColor(.secondary).padding(.top, 8)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NACH").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                    Text(endStation).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            
            // ✅ Beenden-Button (beendet ALLE Activities)
            if #available(iOS 16.0, *) {
                Button(intent: EndAllActivitiesIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Beenden")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 0)
    }
}

// ========================================
// MARK: - Dynamic Island: Expanded Bottom
// ========================================

struct DynamicIslandExpandedBottom: View {
    let startStation: String
    let endStation: String
    let departureTimeISO: String
    let arrivalTimeISO: String
    let serviceType: String
    let delay: Int?
    let phase: TripPhase
    let tripId: String  // ✅ NEU
    
    var body: some View {
        if phase == .arrived {
            DynamicIslandArrivedBottom(
                startStation: startStation,
                endStation: endStation,
                tripId: tripId  // ✅ NEU
            )
        } else {
            regularBottomView
        }
    }
    
    private var regularBottomView: some View {
        VStack(spacing: 10) {
            stationRow
            progressBar
        }
        .padding(.top, 0)
    }
    
    private var stationRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VON").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                Text(startStation).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Image(systemName: "arrow.right").font(.system(size: 11))
                .foregroundColor(.secondary).padding(.top, 8)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("NACH").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                Text(endStation).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }
    
    private var progressBar: some View {
        JourneyProgressView(
            departureTimeISO: departureTimeISO,
            arrivalTimeISO: arrivalTimeISO,
            serviceType: serviceType,
            delay: delay
        )
        .frame(height: 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// ========================================
// MARK: - Dynamic Island: Compact Leading
// ========================================

struct DynamicIslandCompactLeading: View {
    let serviceType: String
    let lineName: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: StyleHelper.getIcon(for: serviceType)).font(.caption)
            Text(StyleHelper.getShortName(from: lineName)).font(.caption2).fontWeight(.bold)
        }
        .foregroundColor(StyleHelper.getColor(for: serviceType))
    }
}

// ========================================
// MARK: - Dynamic Island: Compact Trailing
// ========================================

struct DynamicIslandCompactTrailing: View {
    let departureTimeISO: String
    let arrivalTimeISO: String
    let delay: Int?
    let currentTime: Date
    let phase: TripPhase
    
    var body: some View {
        if phase == .arrived {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 40, alignment: .trailing)
        } else {
            let isBeforeDeparture = DateCalculationHelper.isBeforeDeparture(departureTimeISO, at: currentTime)
            
            if isBeforeDeparture {
                beforeDepartureCompactTimer
            } else {
                duringJourneyCompactTimer
            }
        }
    }
    
    @ViewBuilder
    private var beforeDepartureCompactTimer: some View {
        if let delay = delay, delay > 0 {
            if let totalRange = DateCalculationHelper.safeCalculateEstimatedDepartureDate(
                from: departureTimeISO, delayMinutes: delay, currentTime: currentTime
            ) {
                Text(timerInterval: totalRange, countsDown: true)
                    .font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.red).frame(width: 40, alignment: .trailing)
            } else {
                Text("--:--").font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.red).frame(width: 40, alignment: .trailing)
            }
        } else {
            if let timeRange = DateCalculationHelper.safeCalculateDepartureDate(
                from: departureTimeISO, currentTime: currentTime
            ) {
                Text(timerInterval: timeRange, countsDown: true)
                    .font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.green).frame(width: 40, alignment: .trailing)
            } else {
                Text("--:--").font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.green).frame(width: 40, alignment: .trailing)
            }
        }
    }
    
    @ViewBuilder
    private var duringJourneyCompactTimer: some View {
        if let delay = delay, delay > 0 {
            if let totalRange = DateCalculationHelper.safeCalculateDelayedArrivalDate(
                from: arrivalTimeISO,
                delayMinutes: delay,
                currentTime: currentTime
            ) {
                Text(timerInterval: totalRange, countsDown: true)
                    .font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.blue).frame(width: 40, alignment: .trailing)
            } else {
                Text("--:--").font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.blue).frame(width: 40, alignment: .trailing)
            }
        } else {
            if let timeRange = DateCalculationHelper.safeCalculateRealArrivalDate(
                from: arrivalTimeISO,
                currentTime: currentTime
            ) {
                Text(timerInterval: timeRange, countsDown: true)
                    .font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.blue).frame(width: 40, alignment: .trailing)
            } else {
                Text("--:--").font(.caption2).fontWeight(.semibold).monospacedDigit()
                    .foregroundColor(.blue).frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// ========================================
// MARK: - Dynamic Island: Minimal View
// ========================================

struct DynamicIslandMinimalView: View {
    let departureTimeISO: String
    let serviceType: String
    let delay: Int?
    let currentTime: Date
    let phase: TripPhase
    
    var body: some View {
        if phase == .arrived {
            ZStack {
                Circle().fill(Color.black).frame(width: 20, height: 20)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundColor(.green)
            }
        } else {
            let isBeforeDeparture = DateCalculationHelper.isBeforeDeparture(departureTimeISO, at: currentTime)
            let hasDelay = delay != nil && delay! > 0
            
            ZStack {
                if isBeforeDeparture {
                    beforeDepartureIcon(hasDelay: hasDelay)
                } else {
                    duringJourneyIcon(hasDelay: hasDelay)
                }
            }
        }
    }
    
    @ViewBuilder
    private func beforeDepartureIcon(hasDelay: Bool) -> some View {
        if hasDelay {
            Circle().fill(Color.black).frame(width: 20, height: 20)
            Image(systemName: "clock.fill").font(.system(size: 19)).foregroundColor(.red)
        } else {
            Circle().fill(Color.black).frame(width: 20, height: 20)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundColor(.green)
        }
    }
    
    @ViewBuilder
    private func duringJourneyIcon(hasDelay: Bool) -> some View {
        if hasDelay {
            Circle().fill(Color.black).frame(width: 25, height: 20)
            Image(systemName: StyleHelper.getIcon(for: serviceType)).font(.caption).foregroundColor(.red)
        } else {
            Circle().fill(Color.black).frame(width: 25, height: 20)
            Image(systemName: StyleHelper.getIcon(for: serviceType)).font(.caption).foregroundColor(.blue)
        }
    }
}
