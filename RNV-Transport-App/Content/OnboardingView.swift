//
//  OnboardingView.swift
//  RNV-Transport-App
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0
    @Environment(\.colorScheme) private var colorScheme

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "tram.circle.fill",
            title: "Willkommen bei\nÖPNV Mannheim",
            body: "Dein Begleiter für Bus, Tram und S-Bahn in Mannheim und Umgebung. Verbindungen in Echtzeit – direkt auf deinem iPhone.",
            gradient: [Color(hex: "#0c0a09"), Color(hex: "#1c1917")]
        ),
        OnboardingPage(
            icon: "location.fill",
            title: "Haltestellen\nin deiner Nähe",
            body: "Die App nutzt deinen Standort, um nahegelegene Haltestellen zu finden. Deine Position wird nur für die Suche verwendet und nie gespeichert.",
            gradient: [Color(hex: "#1c1917"), Color(hex: "#292524")]
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            title: "Live Activity &\nDynamic Island",
            body: "Verfolge deine Fahrt direkt im Dynamic Island oder auf dem Sperrbildschirm – mit Echtzeit-Abfahrtszeiten und Verspätungsanzeige.",
            gradient: [Color(hex: "#292524"), Color(hex: "#0c0a09")]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: pages[currentPage].gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                Spacer()

                pageContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentPage)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)

                Spacer()

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Page Content

    private var pageContent: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 140, height: 140)
                Image(systemName: pages[currentPage].icon)
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 16) {
                Text(pages[currentPage].title)
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(pages[currentPage].body)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index == currentPage ? 1 : 0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                }
            }

            if currentPage < pages.count - 1 {
                HStack {
                    Button("Überspringen") {
                        finishOnboarding()
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Button(action: nextPage) {
                        HStack(spacing: 8) {
                            Text("Weiter")
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(Capsule())
                    }
                }
            } else {
                Button(action: finishOnboarding) {
                    Text("Loslegen")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func nextPage() {
        withAnimation {
            currentPage = min(currentPage + 1, pages.count - 1)
        }
    }

    private func finishOnboarding() {
        withAnimation(.easeOut(duration: 0.3)) {
            hasSeenOnboarding = true
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let body: String
    let gradient: [Color]
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
}
