import SwiftUI

/// Shared presentation primitives for the nine-step family assessment.
/// Keeping these outside the feature view prevents each step from inventing
/// its own spacing, typography and progress treatment.
struct AssessmentProgressHeader: View {
    let titles: [String]
    let currentIndex: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    progressTitle
                    Spacer(minLength: 8)
                    progressCount
                }
                VStack(alignment: .leading, spacing: 8) {
                    progressTitle
                    progressCount
                }
            }

            HStack(spacing: 5) {
                ForEach(titles.indices, id: \.self) { index in
                    Capsule()
                        .fill(segmentColor(at: index))
                        .frame(height: index == currentIndex ? 7 : 5)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("assessment-progress-header")
            .accessibilityLabel("身体测评进度")
            .accessibilityValue("第 \(currentIndex + 1) 步，共 \(titles.count) 步，当前为 \(titles[currentIndex])")

            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.icloud.fill")
                    Text("填写内容会自动保存")
                }
                .font(.system(size: AppTheme.captionSize, weight: .medium))
                .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))
    }

    private var progressTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("家庭身体测评")
                .font(.system(size: AppTheme.captionSize, weight: .semibold))
                .foregroundStyle(ReferenceColor.blue)
            Text(titles[currentIndex])
                .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                .foregroundStyle(ReferenceColor.navy)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var progressCount: some View {
        Text("第 \(currentIndex + 1) 步 · 共 \(titles.count) 步")
            .font(.system(size: AppTheme.captionSize, weight: .semibold))
            .foregroundStyle(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func segmentColor(at index: Int) -> Color {
        if index < currentIndex { return ReferenceColor.green }
        if index == currentIndex { return ReferenceColor.blue }
        return AppTheme.divider
    }
}

struct AssessmentHeroCard<Content: View>: View {
    let icon: String
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(
        icon: String,
        eyebrow: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow)
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.80))
                    Text(title)
                        .font(.system(size: AppTheme.pageTitleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [ReferenceColor.blue, Color(hex: "19A9B7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 150, height: 150)
                .offset(x: 48, y: -70)
                .allowsHitTesting(false)
        }
        .shadow(color: ReferenceColor.blue.opacity(0.18), radius: 18, y: 10)
    }
}

struct AssessmentFactChip: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: AppTheme.captionSize, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.16), in: Capsule())
    }
}

struct AssessmentInfoBanner: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = ReferenceColor.blue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
                Text(detail)
                    .font(.system(size: AppTheme.secondarySize))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(tint.opacity(0.065), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(tint.opacity(0.12), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

struct AssessmentPrimaryAction: View {
    let title: String
    let icon: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.system(size: AppTheme.buttonSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                LinearGradient(
                    colors: enabled ? [ReferenceColor.blue, Color(hex: "2689EF")] : [AppTheme.muted.opacity(0.55), AppTheme.muted.opacity(0.45)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .shadow(color: enabled ? ReferenceColor.blue.opacity(0.18) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityValue(enabled ? "可操作" : "尚未满足条件")
    }
}

struct AssessmentPhaseRow: View {
    let number: Int
    let title: String
    let detail: String
    let icon: String
    var completed = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(completed ? ReferenceColor.green.opacity(0.12) : ReferenceColor.blue.opacity(0.09))
                Image(systemName: completed ? "checkmark" : icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(completed ? ReferenceColor.green : ReferenceColor.blue)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)")
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
                Text(detail)
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
