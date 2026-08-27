import SwiftUI

extension BodyAssessmentView {
    func result(_ student: Student) -> some View {
        let activeRecord = record ?? provisionalRecord
        let level = activeRecord.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)
        return VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: icon(for: level),
                eyebrow: "\(dateText(activeRecord.measuredAt)) · 家庭观察",
                title: "\(student.name) 的身体测评结果",
                detail: resultSummary(for: level)
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "scalemass.fill", title: String(format: "BMI %.1f", activeRecord.bmi))
                    AssessmentFactChip(icon: "checkmark.circle.fill", title: "完成 \(activeRecord.completedCaptures.count) 项")
                }
            }
            bodySyncStatus(for: student)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 13) {
                    ReferenceSectionTitle(title: "身体数据", trailing: "儿童年龄别参考")
                    HStack(spacing: 10) {
                        resultMetric(title: "身高", value: String(format: "%.1f", activeRecord.heightCentimeters), unit: "cm", color: ReferenceColor.blue)
                        resultMetric(title: "体重", value: String(format: "%.1f", activeRecord.weightKilograms), unit: "kg", color: ReferenceColor.green)
                        resultMetric(title: "BMI", value: String(format: "%.1f", activeRecord.bmi), unit: activeRecord.bmiScreeningLabel(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender), color: color(for: level))
                    }
                    if let geneticHeight = activeRecord.geneticHeightReference(gender: student.gender) {
                        Divider()
                        let range = activeRecord.geneticHeightRange(gender: student.gender)
                        let rangeText = range.map { String(format: " · 区间 %.1f–%.1f cm", $0.lowerBound, $0.upperBound) } ?? ""
                        let predictedText = "遗传靶身高中位：" + String(format: "%.1f", geneticHeight) + " cm" + rangeText
                        Text(predictedText + "（" + activeRecord.geneticHeightFormula(gender: student.gender) + "）")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                    }
                    if let heightAssessment = activeRecord.heightDevelopmentAssessment(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) {
                        Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                    }
                    bmiTrend(history: state.bodyAssessmentHistory(for: student), fallback: activeRecord)
                }
            }
            if let report = activeRecord.postureReport {
                postureReportCard(report)
            }
            ForEach(activeRecord.observations(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)) { item in
                HStack(spacing: 12) { Image(systemName: icon(for: item.level)).foregroundStyle(color(for: item.level)).frame(width: 24); VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(item.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); attentionBadge(item.level) }
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            AssessmentInfoBanner(
                icon: "calendar.badge.clock",
                title: "下次建议复测 · \(dateText(activeRecord.nextFollowUpDate))",
                detail: "在相近时间和环境下复测，更便于观察真实变化。",
                tint: ReferenceColor.green
            )
            AssessmentPrimaryAction(title: "开始 28 天健康计划", icon: "figure.walk") { move(to: .plan) }
            Button { router.push(.parentCourses) } label: {
                Label("查看推荐课程", systemImage: "play.rectangle.fill")
                    .font(.system(size: AppTheme.buttonSize, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.bordered)
            .tint(ReferenceColor.blue)
        }
    }

    private func postureReportCard(_ report: PostureAssessmentReport) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("人体姿态测评报告", systemImage: "figure.stand.line.dotted.figure.stand")
                    .font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
                attentionBadge(report.overallLevel)
            }
            Text("本次观察 · \(report.snapshots.values.map(\.sampleCount).reduce(0, +)) 条记录")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(BodyAssessmentRecord.CaptureTask.allCases) { task in
                if let snapshot = report.snapshots[task] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy)
                            Spacer()
                            Text(String(format: "记录稳定度 %.0f%% · %d 条", snapshot.confidence * 100, snapshot.sampleCount))
                                .font(.caption).foregroundStyle(snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples ? ReferenceColor.green : bodyCoral)
                        }
                        Text(postureMetricSummary(snapshot))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(ReferenceColor.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            ForEach(report.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(ReferenceColor.blue)
                    Text(reason).font(.caption).foregroundStyle(ReferenceColor.navy)
                }
            }
            Text(report.disclaimer)
                .font(.caption).foregroundStyle(.secondary)
                .padding(10).background(ReferenceColor.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            if report.overallLevel == .pending {
                Button {
                    step = .capture
                } label: {
                    Label("重新记录稳定度不足的项目", systemImage: "arrow.clockwise.camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReferenceColor.blue)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func postureMetricSummary(_ snapshot: PostureMetricSnapshot) -> String {
        var values: [String] = []
        if let value = snapshot.shoulderHeightDifferenceCm { values.append(String(format: "双肩差 %.1f cm", value)) }
        if let value = snapshot.pelvicHeightDifferenceCm { values.append(String(format: "骨盆差 %.1f cm", value)) }
        if let value = snapshot.spinalMidlineDeviationCm { values.append(String(format: "中线偏移 %.1f cm", value)) }
        if let value = snapshot.cameraProxyAtrDegrees { values.append(String(format: "旋转代理 %.1f°", value)) }
        if let value = snapshot.gaitTrunkSwayCm { values.append(String(format: "步态摆动 %.1f cm", value)) }
        return values.isEmpty ? "指标尚未完整，请重新拍摄" : values.joined(separator: " · ")
    }

    @ViewBuilder private func bodySyncStatus(for student: Student) -> some View {
        if state.repository.supportsRemoteAcknowledgement,
           let status = state.localFeatures.bodyAssessmentSyncStates[student.id] {
            let presentation = bodySyncPresentation(for: status)
            Label(presentation.message, systemImage: presentation.icon)
                .font(.caption)
                .foregroundStyle(presentation.tint)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(presentation.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct BodySyncPresentation {
        let message: String
        let tint: Color
        let icon: String
    }

    private func bodySyncPresentation(for status: LocalSubmissionStatus) -> BodySyncPresentation {
        switch status {
        case .pendingSync: return BodySyncPresentation(message: "测评结果已保存，联网后自动同步。", tint: .orange, icon: "clock.arrow.circlepath")
        case .submitting: return BodySyncPresentation(message: "正在同步到孩子健康档案…", tint: ReferenceColor.blue, icon: "arrow.triangle.2.circlepath")
        case .submitted: return BodySyncPresentation(message: "已同步到孩子健康档案。", tint: ReferenceColor.green, icon: "checkmark.shield.fill")
        case .failed: return BodySyncPresentation(message: "同步失败，结果仍已保存。请稍后重试。", tint: .red, icon: "exclamationmark.triangle.fill")
        case .draft: return BodySyncPresentation(message: "测评结果尚未完成保存。", tint: .secondary, icon: "doc.text")
        }
    }

    func plan(_ student: Student) -> some View {
        let activeRecord = record ?? provisionalRecord
        let days = (0..<28).map { BusinessClock.addingDays($0, to: BusinessClock.startOfDay()) }
        let visibleDays = showsAllPlanDays ? days : Array(days.prefix(7))
        return VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "figure.strengthtraining.traditional",
                eyebrow: "根据本次测评生成",
                title: "28 天身体习惯计划",
                detail: "每天约 10 分钟，循序完成姿态觉察、肩背活动、平衡行走与规律作息。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "clock.fill", title: "每天 10 分钟")
                    AssessmentFactChip(icon: "checkmark.circle.fill", title: "已完成 \(activeRecord.completedPlanDays.count) 天")
                }
            }
            ReferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    ReferenceSectionTitle(title: "计划进度", trailing: "\(activeRecord.completedPlanDays.count) / 28 天")
                    AnimatedProgressLine(value: Double(activeRecord.completedPlanDays.count) / 28.0)
                    Text("计划进度已保存，联网后自动同步提醒。")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            Button {
                let today = BusinessClock.startOfDay()
                followAlongDate = today
                followAlongDayIndex = (BusinessClock.calendar.component(.weekday, from: today) + 5) % 7
                showFollowAlong = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开始今日跟练").font(.system(size: AppTheme.bodySize, weight: .semibold)).foregroundStyle(.white)
                        Text("示范节拍、摄像头纠错与语音提示").font(.system(size: AppTheme.captionSize)).foregroundStyle(.white.opacity(0.86))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                }
                .padding(AppTheme.cardPadding)
                .background(LinearGradient(colors: [ReferenceColor.blue, Color(hex: "19A9B7")], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .shadow(color: ReferenceColor.blue.opacity(0.18), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始今日 训练跟练")
            ReferenceSectionTitle(title: showsAllPlanDays ? "全部 28 天" : "本周安排", trailing: showsAllPlanDays ? "收起" : "查看全部", action: { showsAllPlanDays.toggle() })
                .padding(.top, 4)
            ForEach(Array(visibleDays.enumerated()), id: \.element) { visibleIndex, day in
                let index = showsAllPlanDays ? visibleIndex : visibleIndex
                let key = dayKey(day)
                let done = activeRecord.completedPlanDays.contains(key)
                Button {
                    if done {
                        state.toggleBodyPlanDay(day, for: student)
                    } else {
                        followAlongDayIndex = index % 7
                        followAlongDate = day
                        showFollowAlong = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(done ? ReferenceColor.green : AppTheme.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(index + 1) 天 · \(weekday(day))")
                                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                                .foregroundStyle(ReferenceColor.navy)
                            Text(planText(for: index % 7))
                                .font(.system(size: AppTheme.captionSize))
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text(done ? "已完成" : "去完成")
                            .font(.system(size: AppTheme.captionSize, weight: .semibold))
                            .foregroundStyle(done ? ReferenceColor.green : ReferenceColor.blue)
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.75), lineWidth: 0.75))
                }.buttonStyle(.plain)
            }
            Button { router.push(.healthProfile) } label: {
                Label("返回孩子健康档案", systemImage: "heart.text.square.fill")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.bordered)
            .tint(ReferenceColor.blue)
        }
    }

    func attentionBadge(_ level: BodyAssessmentRecord.AttentionLevel, label: String? = nil) -> some View { Text(label ?? level.label).font(.caption.weight(.bold)).foregroundStyle(color(for: level)).padding(.horizontal, 8).padding(.vertical, 5).background(color(for: level).opacity(0.12), in: Capsule()) }
    private func color(for level: BodyAssessmentRecord.AttentionLevel) -> Color { switch level { case .pending: ReferenceColor.blue; case .green: ReferenceColor.green; case .yellow: .orange; case .red: .red; case .unavailable: .secondary } }
    private func icon(for level: BodyAssessmentRecord.AttentionLevel) -> String { switch level { case .pending: "camera.viewfinder"; case .green: "checkmark.shield.fill"; case .yellow: "exclamationmark.triangle.fill"; case .red: "exclamationmark.shield.fill"; case .unavailable: "calendar.badge.exclamationmark" } }
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View { AssessmentPrimaryAction(title: title, icon: icon, action: action) }
    private func resultMetric(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: AppTheme.captionSize, weight: .medium))
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: AppTheme.captionSize))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
    private func resultSummary(for level: BodyAssessmentRecord.AttentionLevel) -> String {
        switch level {
        case .green: "本次记录整体稳定，可按计划继续日常训练并定期复测。"
        case .yellow: "发现需要持续观察的信号，建议降低训练强度并按时复测。"
        case .red: "存在优先关注项，请暂停相关动作并结合专业意见。"
        case .pending: "结果仍需补充数据，请完成缺少的动作采集。"
        case .unavailable: "当前资料不足，完善孩子信息后可获得年龄别参考。"
        }
    }
    private func bmiTrend(history: [BodyAssessmentRecord], fallback: BodyAssessmentRecord) -> some View { VStack(alignment: .leading, spacing: 7) { Text("BMI 趋势").font(.caption.weight(.semibold)).foregroundStyle(.secondary); if history.count < 2 { Text("完成下一次实测后，将显示真实趋势；不会虚构历史或目标数据。") .font(.caption).foregroundStyle(.secondary) } else { let values = Array(history.suffix(3)); HStack(alignment: .bottom, spacing: 10) { ForEach(Array(values.enumerated()), id: \.offset) { index, item in trendBar(index == values.count - 1 ? "本次" : dateText(item.measuredAt), item.bmi, values.map(\.bmi).max() ?? fallback.bmi) } } } } }
    private func trendBar(_ label: String, _ value: Double, _ maxValue: Double) -> some View { VStack(spacing: 4) { Text(String(format: "%.1f", value)).font(.caption.bold()).foregroundStyle(ReferenceColor.navy); Capsule().fill(bodyCoral.opacity(0.18)).frame(width: 48, height: 44).overlay(alignment: .bottom) { Capsule().fill(label == "本次" ? bodyCoral : ReferenceColor.blue).frame(width: 48, height: max(10, 44 * value / max(maxValue, 1))) }; Text(label).font(.caption).foregroundStyle(.secondary) } }
    func dateText(_ date: Date) -> String { Self.dateFormatter.string(from: date) }
    private func dayKey(_ date: Date) -> String { Self.dayFormatter.string(from: date) }
    private func weekday(_ date: Date) -> String { Self.weekdayFormatter.string(from: date) }
    private func planText(for index: Int) -> String {
        let day = FollowAlongPlan.day(at: index)
        guard !day.exercises.isEmpty else { return "恢复日：轻松呼吸、肩背舒展与户外散步" }
        return day.exercises.map { "\($0.title) \($0.target)\($0.unit)" }.joined(separator: " + ")
    }
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "yyyy年M月d日"; return f }()
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let weekdayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "EEEE"; return f }()
}
