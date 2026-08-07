import SwiftUI

enum ReferenceColor {
    static let blue = Color(hex: "347CF1")
    static let sky = Color(hex: "EAF4FF")
    static let canvas = Color(hex: "F7FAFF")
    static let navy = Color(hex: "172B4D")
    static let green = Color(hex: "21C46B")
    static let pink = Color(hex: "FF6D9B")
    static let purple = Color(hex: "8766EF")
    static let yellow = Color(hex: "FFBD2E")
}

struct ReferenceHeader: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    let name: String; let school: String; let initial: String; var showsBell = true; var avatarAsset: String? = nil; var roleAction: (() -> Void)? = nil; var identityAction: (() -> Void)? = nil
    var body: some View { HStack(spacing: 9) {
        if let identityAction {
            Button(action: identityAction) { identityContent }.buttonStyle(.plain).accessibilityLabel("切换孩子")
        } else {
            identityContent
        }
        Spacer()
        if let roleAction { Button(action: roleAction) { Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ReferenceColor.blue).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("切换使用角色") }
        if showsBell { Button { router.push(state.selectedRole == .teacher ? .teacherMessages : .notifications) } label: { Image(systemName: "bell").font(.system(size: 16, weight: .medium)).foregroundStyle(ReferenceColor.navy).frame(width: 32, height: 32).contentShape(Rectangle()).frame(width: 44, height: 44).contentShape(Rectangle()).overlay(alignment: .topTrailing) { if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 5, height: 5).offset(x: -3, y: 3) } } }.buttonStyle(.plain).accessibilityLabel("消息通知").accessibilityHint("打开消息中心") }
    }.padding(.horizontal, 14).padding(.vertical, 9).background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }.overlay(alignment: .bottom) { Rectangle().fill(ReferenceColor.navy.opacity(0.08)).frame(height: 0.5) } }
    private var identityContent: some View {
        HStack(spacing: 9) {
            Group {
                if let avatarAsset {
                    Image(avatarAsset).resizable().scaledToFill().frame(width: 40, height: 40).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                } else {
                    Text(initial).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 34, height: 34).background(LinearGradient(colors: [ReferenceColor.sky, ReferenceColor.blue], startPoint: .top, endPoint: .bottom), in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 1) { Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(ReferenceColor.navy); Text(school).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
    }
}

struct ReferenceSectionTitle: View {
    let title: String
    let trailing: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ReferenceColor.navy)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action: action) {
                    trailingLabel(showChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)，\(trailing)")
            } else {
                trailingLabel(showChevron: false)
            }
        }
    }
    private func trailingLabel(showChevron: Bool) -> some View {
        HStack(spacing: 3) {
            Text(trailing).font(.system(size: 10, weight: .medium)).foregroundStyle(showChevron ? ReferenceColor.blue : .secondary)
            if showChevron { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(ReferenceColor.blue) }
        }
    }
}

struct ReferenceMetric: View {
    let icon: String; let title: String; let value: String; let color: Color
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var breathes = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .scaleEffect(breathes ? 1.1 : 0.94)
                .symbolEffect(.pulse, options: .repeating, value: breathes)
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(ReferenceColor.navy)
            Text(value).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .task(id: state.localFeatures.settings.reduceMotion || systemReduceMotion) {
            guard !(state.localFeatures.settings.reduceMotion || systemReduceMotion) else { breathes = false; return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathes = true }
        }
    }
}

struct ReferenceAction: View { let icon: String; let title: String; let color: Color; var body: some View { VStack(spacing: 7) { Image(systemName: icon).font(.system(size: 21, weight: .bold)).foregroundStyle(.white).frame(width: 39, height: 39).background(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12)); Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(1) }.frame(maxWidth: .infinity).padding(.vertical, 8).accessibilityElement(children: .ignore).accessibilityLabel(title) }
}

struct ReferenceCard<Content: View>: View { @ViewBuilder let content: Content; var body: some View { content.padding(11).background(.white, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(ReferenceColor.blue.opacity(0.08), lineWidth: 1)).shadow(color: .black.opacity(0.025), radius: 4, y: 2) } }

struct AnimatedProgressLine: View {
    let value: Double
    var colors: [Color] = [ReferenceColor.blue, ReferenceColor.green]
    var height: CGFloat = 7
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var displayed = 0.0

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(colors.first?.opacity(0.12) ?? ReferenceColor.sky)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * displayed)
                }
        }
        .frame(height: height)
        .task(id: state.localFeatures.settings.reduceMotion || systemReduceMotion) {
            let target = min(max(value, 0), 1)
            guard !(state.localFeatures.settings.reduceMotion || systemReduceMotion) else { displayed = target; return }
            displayed = 0
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.18)) { displayed = target }
        }
    }
}
