import SwiftUI

// Building blocks shared by the Kids Mode screens: little text, lots of animation.
// Every animation respects Reduce Motion.

struct KidsCard<Content: View>: View {
    @Environment(\.pal) private var p
    let title: String
    let emoji: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(emoji).font(.title2)
                Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(p.ink)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(p.dark ? 0.35 : 0.07), radius: 14, y: 5)
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.footnote, design: .rounded, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.6), in: Capsule())
    }
}

/// Gradient hero with bouncing emoji.
struct KidsHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let emojis: [String]
    let title: String
    let pills: [String]
    let colors: [Color]
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { i, e in
                    Text(e).font(.system(size: 40))
                        .offset(y: bounce ? -12 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.1), value: bounce)
                }
            }
            Text(title).font(.system(size: 28, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
            HStack(spacing: 8) { ForEach(pills, id: \.self) { Pill(text: $0) } }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 10)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(Color(hex: 0xFF1E2A3A))
        .onAppear { bounce = true }
    }
}

/// A card that flips to show its meaning.
struct FlipCard: View {
    let emoji: String
    let name: String
    let meaning: String
    let color: Color
    @State private var open = false

    var body: some View {
        Button { withAnimation(.spring(duration: 0.5)) { open.toggle() } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.gradient)
                if open {
                    Text(meaning).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(6)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                } else {
                    VStack(spacing: 4) {
                        Text(emoji).font(.system(size: 28))
                        Text(name).font(.system(.caption2, design: .rounded, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                    }
                }
            }
            .frame(height: 92)
            .rotation3DEffect(.degrees(open ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name): \(meaning)")
    }
}

func kidsButton(_ title: String, _ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: icon).font(.system(.headline, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 6)
    }
    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(tint)
}
