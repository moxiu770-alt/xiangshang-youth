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
    @ScaledMetric(relativeTo: .headline) private var nameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .subheadline) private var schoolSize: CGFloat = 15
    var body: some View { HStack(spacing: 9) {
        if let identityAction {
            Button(action: identityAction) { identityContent }.buttonStyle(.plain).accessibilityLabel("切换孩子")
        } else {
            identityContent
        }
        Spacer()
        if let roleAction { Button(action: roleAction) { Image(systemName: "arrow.left.arrow.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.blue).frame(width: 48, height: 48).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("切换使用角色") }
        if showsBell { Button { router.push(.messageCenter(for: state.selectedRole)) } label: { Image(systemName: "bell").font(.system(size: 19, weight: .medium)).foregroundStyle(ReferenceColor.navy).frame(width: 38, height: 38).contentShape(Rectangle()).frame(width: 48, height: 48).contentShape(Rectangle()).overlay(alignment: .topTrailing) { if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 7, height: 7).offset(x: -3, y: 3) } } }.buttonStyle(.plain).accessibilityLabel("消息通知").accessibilityHint("打开消息中心") }
    }.padding(.horizontal, AppTheme.pagePadding).padding(.vertical, 12).background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }.overlay(alignment: .bottom) { Rectangle().fill(ReferenceColor.navy.opacity(0.08)).frame(height: 0.5) } }
    private var identityContent: some View {
        HStack(spacing: 9) {
            Group {
                if let avatarAsset {
                    Image(avatarAsset).resizable().scaledToFill().frame(width: 48, height: 48).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                } else {
                    Text(initial).font(.system(size: nameSize, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(LinearGradient(colors: [ReferenceColor.sky, ReferenceColor.blue], startPoint: .top, endPoint: .bottom), in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 1) { Text(name).font(.system(size: nameSize, weight: .bold)).foregroundStyle(ReferenceColor.navy); Text(school).font(.system(size: schoolSize)).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

struct ReferenceSectionTitle: View {
    let title: String
    let trailing: String
    var action: (() -> Void)? = nil
    /// Use when the enclosing card owns the tap target.  It keeps the visual
    /// affordance honest without introducing an inaccessible nested button.
    var showsLink: Bool = false
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 19
    @ScaledMetric(relativeTo: .subheadline) private var trailingSize: CGFloat = 15
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
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
                trailingLabel(showChevron: showsLink)
            }
        }
    }
    private func trailingLabel(showChevron: Bool) -> some View {
        HStack(spacing: 3) {
            Text(trailing).font(.system(size: trailingSize, weight: .medium)).foregroundStyle(showChevron ? ReferenceColor.blue : .secondary).lineLimit(2)
            if showChevron { Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.blue) }
        }
    }
}

struct ReferenceMetric: View {
    let icon: String; let title: String; let value: String; let color: Color
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var valueSize: CGFloat = 15
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
            Text(title).font(.system(size: titleSize, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
            Text(value).font(.system(size: valueSize)).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
}

struct ReferenceAction: View {
    let icon: String; let title: String; let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 21, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(color, in: RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(ReferenceColor.navy)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct ReferenceCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(AppTheme.cardPadding)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.75), lineWidth: 0.75))
            .shadow(color: ReferenceColor.navy.opacity(0.045), radius: 10, y: 4)
    }
}

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
