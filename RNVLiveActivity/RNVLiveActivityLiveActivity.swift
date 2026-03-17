//
//  RNVLiveActivityLiveActivity.swift
//  RNVLiveActivity
//
//  Created by Friedrich, Stefan on 10.01.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RNVLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripLiveActivityAttributes.self) { context in
            
            // MARK: Lock Screen Widget
            ContentMediumView(
                context: context,
                isBeforeDeparture: DateCalculationHelper.isBeforeDeparture(
                    context.attributes.departureTimeISO,
                    at: Date(),
                    delay: context.state.delay
                ),
                currentTime: Date()
            )

        } dynamicIsland: { context in
            DynamicIsland {
                
                // MARK: Expanded - Leading
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandExpandedLeading(
                        serviceType: context.state.serviceType,
                        lineName: context.state.lineName
                    )
                }

                // MARK: Expanded - Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandExpandedTrailing(
                        delay: context.state.delay,
                        phase: context.state.phase
                    )
                }
                
                // MARK: Expanded - Center
                DynamicIslandExpandedRegion(.center) {
                    Spacer().frame(height: 20)
                }
                
                // MARK: Expanded - Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandExpandedBottom(
                        startStation: context.attributes.startStation,
                        endStation: context.attributes.endStation,
                        departureTimeISO: context.attributes.departureTimeISO,
                        arrivalTimeISO: context.attributes.arrivalTimeISO,
                        serviceType: context.state.serviceType,
                        delay: context.state.delay,
                        phase: context.state.phase,
                        tripId: context.attributes.tripId
                    )
                }
                
            } compactLeading: {
                
                // MARK: Compact - Leading
                DynamicIslandCompactLeading(
                    serviceType: context.state.serviceType,
                    lineName: context.state.lineName
                )
                
            } compactTrailing: {
                
                // MARK: Compact - Trailing
                DynamicIslandCompactTrailing(
                    departureTimeISO: context.attributes.departureTimeISO,
                    arrivalTimeISO: context.attributes.arrivalTimeISO,
                    delay: context.state.delay,
                    phase: context.state.phase
                )
                .animation(.easeInOut(duration: 0.3), value: context.state.phase)
            } minimal: {
                
                // MARK: Minimal
                // ✅ OHNE TimelineView - DynamicIslandMinimalView hat bereits eine intern!
                DynamicIslandMinimalView(
                    departureTimeISO: context.attributes.departureTimeISO,
                    serviceType: context.state.serviceType,
                    delay: context.state.delay,
                    phase: context.state.phase
                )
                .animation(.easeInOut(duration: 0.3), value: context.state.phase)
            }
            .keylineTint(StyleHelper.getColor(for: context.state.serviceType))
        }
    }
}

// MARK: - Previews

#Preview("1. Vor Abfahrt (Pünktlich)", as: .dynamicIsland(.compact), using: TripLiveActivityAttributes.previewBeforeDeparture) {
   RNVLiveActivityLiveActivity()
} contentStates: {
    TripLiveActivityAttributes.ContentState.onTime
}

#Preview("2. Vor Abfahrt (Verspätet)", as: .dynamicIsland(.compact), using: TripLiveActivityAttributes.previewBeforeDeparture) {
   RNVLiveActivityLiveActivity()
} contentStates: {
    TripLiveActivityAttributes.ContentState.delayed
}

#Preview("3. Während Fahrt (Pünktlich)", as: .dynamicIsland(.compact), using: TripLiveActivityAttributes.previewDuringJourney) {
   RNVLiveActivityLiveActivity()
} contentStates: {
    TripLiveActivityAttributes.ContentState.onTime
}

#Preview("4. Während Fahrt (Verspätet)", as: .dynamicIsland(.compact), using: TripLiveActivityAttributes.previewDuringJourney) {
   RNVLiveActivityLiveActivity()
} contentStates: {
    TripLiveActivityAttributes.ContentState.delayed
}

#Preview("5. Angekommen", as: .dynamicIsland(.expanded), using: TripLiveActivityAttributes.previewArrived) {
   RNVLiveActivityLiveActivity()
} contentStates: {
    TripLiveActivityAttributes.ContentState.arrived
}
