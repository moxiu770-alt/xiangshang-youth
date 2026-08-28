# 模型独立验证集规范

当前仓库内的 `model_golden_corpus.json` 只做规则边界回归，不能代表儿童真实动作准确率。真实上线前，需要提供一份不参与阈值调节的独立人工标注集，使用 `model_labeled_corpus.schema.json` 约束格式。语料同时应覆盖 `movement`、`body`、`growth` 和 `followAlong`；跟做样本保存人工计数与冻结版本模型在同一回放片段上的预测计数。成长计划模型还会拒绝非法日期、重复日期和未发布的空分数，避免把数据质量问题误写成成长结论。

当前模型注册表覆盖六个模型族：动作评分、姿态筛查、年龄别 BMI、身高发育、视觉跟做和成长计划。每个族都有独立算法版本和校准版本；未完成独立标注验证前，状态统一为 `pending-human-validation`。评估器同时会校验跟做动作配置的四个年龄段、11 类动作和 44 个动作年龄配置，防止只验证报告模型而遗漏跟做模型。

姿态报告还会按拍摄任务校验指标归属：站姿只接受肩/骨盆/头部证据，前屈接受躯干/圆背/前伸/ATR 证据，坐姿接受中线/圆背/头前伸/枕墙距证据，步态只接受三类步态摆动证据。步态摆动使用样本范围而不是相对镜头的最大偏移，避免孩子整体偏离画面时夸大风险；Android 跟做动态区间在高噪声下会先收敛上下界，避免相机分析器因区间反转崩溃。

视觉跟做的 4×11 年龄/动作 JSON 是双端的唯一运行时校准资产：Android 从 `android/app/src/main/assets/follow_along_action_profiles.json` 读取，iOS 构建阶段复制同一文件到 App Bundle 后读取；姿态采集质量的 4 个年龄段也复用 `android/app/src/main/assets/body_pose_capture_profiles.json`，iOS 构建阶段复制并校验版本后读取。任一端无法读取时才使用内置安全回退，并保留对应版本标识。

## 标注要求

- 每条样本使用不可逆的 `id`，不要提交姓名、手机号、原始视频或可识别的人脸信息。
- `movement` 由两名标注员独立给出 7 项成绩；冲突由第三名裁决，低清晰度、多人入镜、遮挡和安全条件不满足的样本标记 `unavailable`。
- `body.snapshots` 只保存归一化关节/测量摘要，不保存原始媒体；姿态风险标签必须由专业人员按冻结协议裁决，不能由当前模型反推。
- movement/body/BMI/身高/姿态按年龄（72–96、97–132、133–180、181–216 月）、性别、机型、摄像头方向、光照和距离分层；跟做额外按运行时实际档位（72–96、97–132、133–168、169–216 月）分层，验证集不能与调参集重复。
- BMI 按 WS/T 586—2018 的半岁年龄档执行：实足月龄向下取整到 6 个月档（例如 75 个月使用 72 个月行），不得用逐月线性插值生成标准中不存在的界值。
- 每次身体测评必须同时保存“测量时月龄”。历史报告重算时优先使用该冻结月龄，不能用孩子当前月龄替换，避免跨半岁档后 BMI/身高结论漂移。
- 身高/体重标注必须落在客户端与服务端共同的物理输入范围（身高 90–190 cm、体重 15–90 kg）；超出范围应作为采集数据质量问题重新采集，不得混入健康标签验证集。
- 每条样本必须带 `split: "validation"`、匿名 `groupId` 和原始片段的 SHA-256 `clipHash`；同一片段重复出现会被评估器拒绝，防止数据泄漏。跟做样本还必须记录 `algorithmVersion: "UY-FOLLOW-CV-1.0"`，确保预测计数来自当前冻结版本。

## 运行

```bash
node scripts/evaluate_model_corpus.mjs --corpus /path/to/human-labeled.json --require-labeled
```

正式发布前再加 `--release-gate`。该门禁会拒绝非独立人工标注集、缺少数据集/标注协议、缺少对应模型年龄分层、动作、身体或跟做模型任一运行时年龄层少于 20 条样本、跟做 11 类动作任一类少于 2 条、缺少至少两种设备/摄像头/光照条件、缺少 20 条成长计划样本，或 body 样本缺少 BMI/身高/姿态人工期望标签。它会按 movement、body、BMI、身高、姿态、成长计划、跟做分别计算 accuracy、balanced accuracy、macro-F1；跟做额外检查计数 MAE ≤ 0.5，并检查每个模型族的分层指标均达到 0.95；未通过时模型状态必须保持 `pending-human-validation`，不能被总体平均值掩盖。

## 发布审批证据链

真实标注语料不得进入 Git 仓库。发布环境须以安全挂载方式同时提供私有语料、评估报告和审批记录，并运行：

```bash
export MODEL_CORPUS_PATH=/secure/model-validation/human-labeled.json
export MODEL_VALIDATION_REPORT_PATH=/secure/model-validation/report.json
export MODEL_VALIDATION_APPROVAL_PATH=/secure/model-validation/approval.json
export MODEL_REPEATABILITY_CORPUS_PATH=/secure/model-validation/repeatability.json
export MODEL_REPEATABILITY_REPORT_PATH=/secure/model-validation/repeatability-report.json
export MODEL_POSTURE_DOMAIN_REPORT_DIR=/secure/model-validation/posture-domains
python3 scripts/verify_model_validation_approval.py
```

验证器会重新以冻结模型运行独立评估，核对私有语料与报告的 SHA-256、模型注册表版本和六个模型族版本。姿态还必须为脊柱排列、肩骨盆、头颈上肢、躯干旋转、动态膝、步态、坐姿和足弓分别提供不少于 500 例的独立报告及摘要；任一问题域未达敏感度、特异度、阴性预测值、重复性和不可判定率门槛，总姿态模型不得标记为已验证。审批记录必须使用 `qa/model_validation_approval.schema.json` 的 `human-validated` 状态，并至少由算法负责人及安全/专业复核人独立签核。`qa/model_validation_approval.example.json` 只是不可通过的占位模板；严禁将其或合成边界集作为发布证据。试点和生产预检会调用该验证器，缺少任一证据即阻断发布。

输出包含准确率、平衡准确率、宏平均 F1、逐类 precision/recall/F1 和混淆矩阵，并可对同一条 body 样本分别核对 BMI、身高、姿态和综合结论。只有 `human-labeled` 独立集才允许作为发布门禁；合成边界集只能发现回归，不能证明真实准确率。

输出还会按年龄段、性别、设备、摄像头方向和光照组合给出分层指标。任一关键分层低于发布门槛，都不能用总体平均值掩盖。

建议上线门槛：总体准确率、宏平均 F1、各年龄段召回率分别达标，并对 `unavailable` 类单独检查，避免模型用“看不清”换取虚假的高准确率。

## 安全调参

动作评分模型可使用独立校准集生成候选阈值：

```bash
node scripts/fit_movement_calibration.mjs /path/to/human-labeled-calibration.json
```

拟合只使用 `split=train`，随后只在 `split=validation` 报告一次；同一 `groupId` 或 `clipHash` 跨集合会直接失败。脚本只输出 `candidate-review-required` 候选清单，不会自动修改生产阈值。BMI、身高和姿态阈值涉及既定规则/安全边界，必须经过相同的独立验证与人工审批后才能变更。
