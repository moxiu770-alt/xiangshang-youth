import SwiftUI

struct SpineStandingMeasurementCard: View {
    @Binding var shoulderDifference: String
    @Binding var pelvisDifference: String
    @Binding var headTilt: String
    let isComplete: Bool

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 10) {
                SpineMeasurementHeader(
                    title: "项目 1 现场实测",
                    detail: "指尖轻触双侧肩峰、髂后上棘标记，用 0.1 cm 软尺测量与地面的垂直高度差。"
                )
                VStack(spacing: 10) {
                    SpineNumberField(title: "双肩高度差", text: $shoulderDifference, unit: "cm")
                    SpineNumberField(title: "骨盆高度差", text: $pelvisDifference, unit: "cm")
                    SpineNumberField(title: "头部侧倾", text: $headTilt, unit: "°")
                }
                SpineMeasurementStatus(
                    isComplete: isComplete,
                    completeText: "实测数值已完整记录",
                    incompleteText: "请录入三项现场实测值"
                )
            }
        }
    }
}

struct SpineAdamsObservationCard: View {
    @Binding var result: String
    @Binding var prominenceSide: String
    let isComplete: Bool

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 10) {
                SpineMeasurementHeader(
                    title: "项目 2 主检员定性记录",
                    detail: "从正后方平视胸腰背部：双侧等高为阴性，单侧隆起＜1 cm 为可疑阳性，≥1 cm 为阳性。"
                )
                Picker("Adams 结果", selection: $result) {
                    Text("未记录").tag("unrecorded")
                    Text("阴性 −").tag("negative")
                    Text("可疑 ±").tag("equivocal")
                    Text("阳性 +").tag("positive")
                }
                .pickerStyle(.segmented)
                if result == "equivocal" || result == "positive" {
                    Picker("隆起侧", selection: $prominenceSide) {
                        Text("请选择").tag("无")
                        Text("左侧").tag("左")
                        Text("右侧").tag("右")
                    }
                    .pickerStyle(.segmented)
                }
                SpineMeasurementStatus(
                    isComplete: isComplete,
                    completeText: "Adams 定性记录已完成",
                    incompleteText: "请完成定性分级和隆起侧记录",
                    incompleteIcon: "eye"
                )
            }
        }
    }
}

struct SpineGaitObservationCard: View {
    @Binding var result: String
    @Binding var note: String

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 10) {
                SpineMeasurementHeader(
                    title: "项目 4 步态人工观察",
                    detail: "从后方、侧方同步观察肩部摆动、骨盆上下摆动和躯干中线是否持续偏移。"
                )
                Picker("步态结果", selection: $result) {
                    Text("未记录").tag("unrecorded")
                    Text("无异常").tag("normal")
                    Text("存在异常").tag("abnormal")
                }
                .pickerStyle(.segmented)
                TextField("异常描述（选填，如单侧骨盆持续抬高）", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
    }
}

struct SpineSeatedMeasurementCard: View {
    @Binding var midlineDifference: String
    @Binding var shoulderDifference: String
    @Binding var kyphosisResult: String
    let isComplete: Bool

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 10) {
                SpineMeasurementHeader(title: "项目 5 坐姿现场实测", detail: nil)
                HStack(spacing: 10) {
                    SpineNumberField(title: "棘突中线偏移", text: $midlineDifference, unit: "cm")
                    SpineNumberField(title: "双肩高度差", text: $shoulderDifference, unit: "cm")
                }
                Picker("胸椎后凸观察", selection: $kyphosisResult) {
                    Text("未记录").tag("unrecorded")
                    Text("未见明显").tag("normal")
                    Text("圆肩驼背").tag("abnormal")
                }
                .pickerStyle(.segmented)
                SpineMeasurementStatus(
                    isComplete: isComplete,
                    completeText: "坐姿实测与定性观察已完成",
                    incompleteText: "请完成坐姿实测与定性观察"
                )
            }
        }
    }
}

private struct SpineMeasurementHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                .foregroundStyle(ReferenceColor.navy)
            if let detail {
                Text(detail)
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SpineNumberField: View {
    let title: String
    @Binding var text: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: AppTheme.captionSize, weight: .semibold))
                .foregroundStyle(ReferenceColor.navy)
            HStack(spacing: 4) {
                TextField("0.0", text: $text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
                Text(unit)
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SpineMeasurementStatus: View {
    let isComplete: Bool
    let completeText: String
    let incompleteText: String
    var incompleteIcon = "ruler"

    var body: some View {
        Label(
            isComplete ? completeText : incompleteText,
            systemImage: isComplete ? "checkmark.circle.fill" : incompleteIcon
        )
        .font(.system(size: AppTheme.captionSize, weight: .semibold))
        .foregroundStyle(isComplete ? ReferenceColor.green : AppTheme.warning)
    }
}
