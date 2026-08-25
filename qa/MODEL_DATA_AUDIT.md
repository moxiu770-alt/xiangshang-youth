# 模型数据资产审计（2026-08-22）

## 结论

当前工程可以证明“规则、边界、跨端契约和合成回归通过”，不能证明儿童真实场景准确率 100%。本次审计没有把演示数据或视频当成人工真值：

- `qa/model_golden_corpus.json` 明确标记为 `synthetic-boundary-regression`。
- `/Users/luyanpeng/Desktop/陆彦鹏/体育跟跳项目/体育跟跳-App/ios/TiantianGenTiao/Resources/DemoPoses.json` 是归一化姿态点演示样本，没有人工计次、风险标签或设备分层。
- 体育跟跳项目中的 `MotionAccuracyTests.swift` 是合成信号回归测试，不是儿童视频标注集。
- 体育跟跳项目的旧版 `src/utils/motionScoring.ts` 仍属于参考实现，节奏分数先按 0–100 计算后又乘 100，存在饱和到满分的风险；当前 App 没有直接复用它，避免把该实现当作已校准模型。
- 发现的 `cbcc473d29fbd5b519e0c06e214b05cf.mp4` 没有随附 `clipHash`、年龄、机位、光照、动作计次和人工裁决元数据，因此不进入发布评估。

## 已落地的模型安全措施

- 已核对《7.20脊柱侧弯测评框架pdf.pdf》：姿态模型现在保留头部侧倾证据，并支持胸段/腰段 ATR 字段；只有校准仪器或深度适配器的 ATR 才会触发 5° 关注、7° 转诊筛查门槛，二维 RGB 代理不会冒充 ATR。

- 运行时带正式版本号的姿态采集和跟做校准资产必须通过完整年龄段、动作类别、参数范围和重复键校验；失败时只使用内置安全回退。
- iOS 与 Android 共用 Android 资产，并在构建/启动时校验版本；动作跟做固定为 4 个年龄段 × 11 类动作 × 4 组年龄配置。
- 独立评估器拒绝合成集作为发布门禁，并按动作、BMI、身高、姿态、综合身体和成长计划分别计算 accuracy、balanced accuracy、macro-F1 及设备/机位/光照分层指标。
- 独立评估器现在同时接收跟做回放的人工计数与模型预测计数，按年龄/设备/机位/光照分层，并以计数 MAE ≤ 0.5 作为额外门禁；未提供跟做集不能通过发布门禁。
- 发布门禁要求 movement/body/BMI/身高/姿态每个通用月龄层至少 20 条、跟做每个运行时年龄层至少 20 条 `split=validation` 样本，且同一 `groupId`/`clipHash` 不得跨集合泄漏。
- 身体测评记录已冻结测量时月龄并在 iOS、Android、本地存储和服务端重算链路中贯通，历史报告不会因当前日期变化而跨 BMI/身高年龄档。

## 要达到真实发布门槛还缺什么

需要采集并脱敏一套独立人工标注集，至少包含：

1. 4 个月龄层 × 2 种以上设备 × 前/后摄 × 2 种以上光照；动作、BMI、身高、姿态、跟做计数和成长计划均有对应人工期望值。
2. 动作项目由两名标注员独立计次/评分，冲突由第三人裁决；姿态由专业人员按冻结协议裁决；每条记录保留不可逆 `clipHash`。
3. 训练/调参集和独立验证集按儿童/家庭 `groupId` 隔离，不能只按视频文件名切分。
4. 将数据按 `qa/model_labeled_corpus.schema.json` 整理后运行：

```bash
node scripts/evaluate_model_corpus.mjs \
  --corpus /path/to/human-labeled-independent-validation.json \
  --require-labeled --release-gate
```

只有该门禁通过，模型注册表的状态才可以从 `pending-human-validation` 变更为可发布状态。任何“合成回归 100%”都不得替代这一步。
