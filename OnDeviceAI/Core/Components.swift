import SwiftUI

/// Placeholder mascot: a coloured circle with the persona's letter and a mood emoji.
/// Swap this view for your own character artwork (one image per Mood).
struct MascotFace: View {
    let mascot: Mascot
    let mood: Mood
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(mascot.color.gradient)
                .overlay(Text(mascot.rawValue.uppercased()).font(.system(size: size * 0.45, weight: .heavy, design: .rounded)).foregroundStyle(.white))
            Text(mood.emoji).font(.system(size: size * 0.38))
                .offset(x: size * 0.08, y: size * 0.08)
                .contentTransition(.opacity)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.3), value: mood)
        .accessibilityLabel("\(mascot.name), \(mood.rawValue)")
    }
}

/// The mascot saying something (welcome text, errors).
struct Says: View {
    @Environment(\.pal) private var p
    let mascot: Mascot
    let text: String
    var mood: Mood = .happy
    var size: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MascotFace(mascot: mascot, mood: mood, size: size)
            Text(markdown(text)).font(.body).foregroundStyle(p.ink)
                .padding(12)
                .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

/// Small capsule button used under assistant answers.
struct SmallButton: View {
    @Environment(\.pal) private var p
    let symbol: String
    let title: String
    let action: () -> Void

    init(_ symbol: String, _ title: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.title = title; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
        }
        .buttonStyle(.glass) // Liquid Glass (iOS 26+)
        .tint(p.tint)
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let w = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? s.width : s.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].items.isEmpty
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += isFirst ? s.width : s.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, s.height)
        }
        return rows
    }
}
