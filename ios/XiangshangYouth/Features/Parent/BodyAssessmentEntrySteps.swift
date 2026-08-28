import SwiftUI

extension BodyAssessmentView {
    func overview(_ student: Student) -> some View {
        VStack(spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "figure.walk.motion",
                eyebrow: "为 \(student.name) 准备",
                title: "约 5 分钟完成身体测评",
                detail: "记录身高、体重，并通过八段家庭相机采集检查全身姿态与动作质量。无需标定板，专业仪器数值仍由学校复测。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "clock.fill", title: "约 5 分钟")
                    AssessmentFactChip(icon: "camera.fill", title: "端内识别")
                    AssessmentFactChip(icon: "lock.shield.fill", title: "不存原片")
                }
            }

            if let record {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ReferenceSectionTitle(title: "最近一次记录", trailing: dateText(record.measuredAt))
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(format: "%.1f", record.bmi))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(ReferenceColor.blue)
                                Text("BMI")
                                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 7) {
                                attentionBadge(record.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender))
                                Text("已完成 \(record.completedCaptures.count) / \(BodyAssessmentRecord.CaptureTask.allCases.count) 项采集")
                                    .font(.system(size: AppTheme.captionSize))
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        Text("测评于 \(dateText(record.measuredAt)) · 已完成 \(record.completedCaptures.count) 项拍摄任务")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                        Button { viewingSavedRecord = true; move(to: .result) } label: {
                            Label("查看结果与计划", systemImage: "chevron.right")
                                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapSize)
                        }
                        .buttonStyle(.bordered)
                        .tint(ReferenceColor.blue)
                    }
                }
            }

            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "测评流程", trailing: "共 9 步")
                    AssessmentPhaseRow(number: 1, title: "准备资料", detail: "阅读说明、完成监护授权并确认孩子信息", icon: "checklist")
                    Divider()
                    AssessmentPhaseRow(number: 2, title: "填写与采集", detail: "填写身高体重，检查环境并完成八段双次相机采集", icon: "camera.viewfinder")
                    Divider()
                    AssessmentPhaseRow(number: 3, title: "查看建议", detail: "确认质量，查看结果并开始训练计划", icon: "chart.bar.doc.horizontal")
                }
            }
            AssessmentInfoBanner(
                icon: "cross.case.fill",
                title: "家庭运动健康观察",
                detail: "结果用于运动建议，不替代医疗诊断。如孩子有疼痛、麻木或活动受限，请先咨询专业人员。",
                tint: ReferenceColor.green
            )
            let standardApplicable = SpineScreeningStandard.isApplicable(ageMonths: student.bodyAssessmentAgeMonths)
            AssessmentInfoBanner(
                icon: standardApplicable ? "person.crop.circle.badge.checkmark" : "calendar.badge.exclamationmark",
                title: "手册适用年龄：6–12 岁",
                detail: standardApplicable ? "孩子年龄在本次家庭姿态观察适用范围内。" : "当前档案年龄不在适用范围或出生日期缺失，请先联系学校核对档案。",
                tint: standardApplicable ? ReferenceColor.green : .orange
            )
            AssessmentPrimaryAction(
                title: standardApplicable ? (record == nil ? "开始身体测评" : "开始新的测评") : "请先核对孩子出生日期",
                icon: "arrow.right",
                enabled: standardApplicable
            ) {
                viewingSavedRecord = false
                move(to: .consent)
            }
        }
    }

    var consentStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "lock.shield.fill",
                eyebrow: "隐私与安全",
                title: "由监护人陪同完成",
                detail: "相机画面只在手机内实时处理，不保存照片、视频或原始帧。"
            ) {
                AssessmentFactChip(icon: "checkmark.shield.fill", title: "仅保存结构化测量结果")
            }

            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "需要你的确认", trailing: adultReady && consentAcknowledged ? "已完成" : "2 项")
                    readinessToggle(
                        title: "监护关系确认",
                        detail: "我是孩子的监护人，并将在测评过程中全程陪同。",
                        icon: "person.badge.shield.checkmark",
                        isOn: $adultReady
                    )
                    Divider()
                    readinessToggle(
                        title: "摄像头与算法说明",
                        detail: "我已了解数据用途、保留范围和撤回授权方式。",
                        icon: "camera.metering.center.weighted",
                        isOn: $consentAcknowledged
                    )
                }
            }

            AssessmentInfoBanner(
                icon: "heart.text.square.fill",
                title: "用途说明",
                detail: "身体测评仅用于家庭运动健康筛查和训练建议，不构成疾病诊断。",
                tint: ReferenceColor.green
            )
            AssessmentPrimaryAction(
                title: adultReady && consentAcknowledged ? "继续确认孩子资料" : "请完成两项确认",
                icon: "arrow.right",
                enabled: adultReady && consentAcknowledged
            ) { move(to: .profile) }
        }
    }

    func profileStep(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentInfoBanner(
                icon: "person.text.rectangle.fill",
                title: "确认测评对象",
                detail: "BMI 年龄参考会使用孩子档案中的出生日期、性别和本次测量日期。"
            )
            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 13) {
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(LinearGradient(colors: [ReferenceColor.blue, Color(hex: "39B7B0")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(student.name)
                                .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                                .foregroundStyle(ReferenceColor.navy)
                            Text("\(student.grade) · \(student.className)")
                                .font(.system(size: AppTheme.secondarySize))
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(ReferenceColor.green)
                            .accessibilityLabel("孩子档案已载入")
                    }
                    Divider()
                    profileDataRow(icon: "person.fill", title: "性别", value: student.gender)
                    profileDataRow(icon: "birthday.cake.fill", title: "年龄参考", value: student.bodyAssessmentAgeLabel)
                    profileDataRow(icon: "building.2.fill", title: "学校档案", value: "\(student.grade) \(student.className)")
                    Text("如资料有误，请先在家庭账户中联系学校更正。年龄别 BMI 只使用孩子资料中的出生日期和本次测量日期计算。")
                        .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                        .padding(.top, 2)
                }
            }
            AssessmentPrimaryAction(title: "确认无误，填写身高体重", icon: "arrow.right") { move(to: .bmi) }
        }
    }

    var environmentStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            environmentPreview
            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "家庭拍摄环境核验", trailing: spaceReady ? "已确认" : "6 项")
                    checklist(SpineScreeningStandard.mainCameraPlacement, icon: "iphone.gen3")
                    Divider()
                    checklist("地面设置足印标记；站姿双脚与肩同宽，Adams 前屈双脚并拢", icon: "shoeprints.fill")
                    Divider()
                    checklist("准备 3 米直线无遮挡步态通道和硬质无靠背凳", icon: "ruler.fill")
                    Divider()
                    checklist("已排除近期外伤/手术、持续腰背痛、发热头晕和无法维持标准动作等暂缓情形", icon: "exclamationmark.shield.fill")
                    Divider()
                    checklist("光线均匀无背光，画面中只出现一名孩子且全身完整入镜", icon: "sun.max.fill")
                    Divider()
                    checklist("手机使用后置 1× 主摄并保持稳定；没有支架时可固定靠放。孩子按人形框站位，连续两次采集用于重复性校验。", icon: "viewfinder.rectangular")
                }
            }
            readinessToggle(
                title: "环境已经准备好",
                detail: "我已确认拍摄距离、光线、安全空间、健康暂缓条件和隐私遮挡。",
                icon: "checkmark.shield.fill",
                isOn: $spaceReady
            )
            AssessmentInfoBanner(
                icon: "camera.aperture",
                title: "相机还会自动检查",
                detail: "打开相机后将继续识别手机水平、光线、距离、遮挡、多人入镜和身体离开画面；正式记录锁定后置 1× 主摄。"
            )
            AssessmentPrimaryAction(
                title: spaceReady ? "进入动作采集" : "请先确认拍摄环境",
                icon: "camera.fill",
                enabled: spaceReady
            ) { move(to: .capture) }
        }
    }

    func bmiEntry(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "scalemass.fill",
                eyebrow: "本次实际测量",
                title: "填写身高和体重",
                detail: "请使用身高仪和体重秤的实际读数，相机不会估算身高或体重。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "function", title: "自动计算 BMI")
                    AssessmentFactChip(icon: "calendar", title: student.bodyAssessmentAgeLabel)
                }
            }
            ruler(title: "身高", value: $height, range: 90...190, unit: "cm", step: 0.5)
            ruler(title: "体重", value: $weight, range: 15...90, unit: "kg", step: 0.1)

            ReferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前 BMI")
                                .font(.system(size: AppTheme.captionSize, weight: .semibold))
                                .foregroundStyle(AppTheme.muted)
                            Text(height > 0 && weight > 0 ? String(format: "%.1f", provisionalRecord.bmi) : "--")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(ReferenceColor.blue)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            attentionBadge(provisionalBMILevel, label: provisionalRecord.bmiScreeningLabel(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender))
                            Text("儿童年龄别 BMI 参考")
                                .font(.system(size: AppTheme.captionSize))
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    Divider()
                    Text("BMI = 体重(kg) ÷ 身高²(m²)。结果会结合出生日期、性别和测量日期给出年龄别参考。")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                    if let heightAssessment = provisionalRecord.heightDevelopmentAssessment(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) {
                        Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm · 儿童身高参考标准")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(ReferenceColor.navy)
                    }
                }
            }

            DisclosureGroup(isExpanded: $parentsExpanded) {
                VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
                    Text("仅用于计算遗传靶身高参考区间，不代表成年身高预测。")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                    ruler(title: "父亲身高", value: $fatherHeight, range: 120...230, unit: "cm", step: 0.5)
                    ruler(title: "母亲身高", value: $motherHeight, range: 120...230, unit: "cm", step: 0.5)
                    if let geneticHeight = provisionalRecord.geneticHeightReference(gender: student.gender) {
                        let range = provisionalRecord.geneticHeightRange(gender: student.gender)
                        let rangeText = range.map { String(format: "%.1f–%.1f cm", $0.lowerBound, $0.upperBound) } ?? "待完整填写"
                        AssessmentInfoBanner(
                            icon: "ruler.fill",
                            title: String(format: "遗传靶身高中位 %.1f cm", geneticHeight),
                            detail: "参考区间 \(rangeText) · 仅作家庭健康管理参考",
                            tint: ReferenceColor.green
                        )
                    }
                }
                .padding(.top, AppTheme.cardSpacing)
            } label: {
                Label("补充父母身高（选填）", systemImage: "person.2.fill")
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
            }
            .padding(AppTheme.cardPadding)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))

            AssessmentPrimaryAction(
                title: hasValidCoreMeasurements ? "继续检查拍摄环境" : "请填写有效身高和体重",
                icon: "arrow.right",
                enabled: hasValidCoreMeasurements
            ) { move(to: .environment) }
        }
    }
}
