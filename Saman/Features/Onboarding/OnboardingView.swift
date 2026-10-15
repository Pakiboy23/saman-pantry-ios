import SwiftUI
import PostHog

/// First-launch only. Completion is stored in AppStorage and never shown again.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0

    private let pages: [Page] = [
        Page(
            headline: "Don't lose the recipes that only one person knows.",
            body: "Record whoever in your family cooks as they explain a dish, in any language. Samaan Pantry pulls out the recipe.",
            cta: "Next"
        ),
        Page(
            headline: "One cookbook. Every generation.",
            body: "Every recipe you extract goes into a family cookbook your whole family can cook from.",
            cta: "Next"
        ),
        Page(
            headline: "Start with 5 free extractions.",
            body: "New accounts get 5 recipe extractions for life. No credit card needed. Go Samaan Pro when you're ready for unlimited.",
            cta: "Get started"
        ),
    ]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                Text("Samaan Pantry")
                    .font(.pantryWordmark)
                    .foregroundStyle(Color.brandSaag)
                    .padding(.bottom, 28)
                    .accessibilityAddTraits(.isHeader)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        pageContent(item)
                            .tag(index)
                            .padding(.horizontal, Samaan.Space.lg)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: page)

                pageDots
                    .padding(.top, 20)
                    .padding(.bottom, 28)

                Button(pages[page].cta) {
                    advance()
                }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .padding(.horizontal, Samaan.Space.lg)
                .padding(.bottom, 40)
                .accessibilityIdentifier("onboarding.cta")
            }
        }
        .accessibilityIdentifier("onboarding.root")
        .postHogScreenView("Onboarding")
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color.brandSaagSoft.opacity(0.55),
                Color.surfaceDoodh,
                Color.surfaceMalai.opacity(0.9),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Image(systemName: "leaf.fill")
                .font(.system(size: 220))
                .foregroundStyle(Color.brandSaag.opacity(0.06))
                .rotationEffect(.degrees(-18))
                .offset(x: 90, y: -40)
                .allowsHitTesting(false)
        }
    }

    private func pageContent(_ page: Page) -> some View {
        VStack(spacing: 16) {
            Text(page.headline)
                .font(.cormorant(size: 34))
                .foregroundStyle(Color.inkKohl)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.headline")
            Text(page.body)
                .font(.system(size: 16))
                .foregroundStyle(Color.inkKohlSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.brandSaag : Color.borderAkhrotSoft.opacity(0.7))
                    .frame(width: index == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
    }

    private func advance() {
        if page >= pages.count - 1 {
            onFinished()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                page += 1
            }
        }
    }

    private struct Page {
        let headline: String
        let body: String
        let cta: String
    }
}

enum OnboardingStorage {
    static let completedKey = "samaan.hasCompletedOnboarding"
}
