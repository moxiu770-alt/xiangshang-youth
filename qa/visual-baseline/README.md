# 视觉回归基线目录

这里必须放经产品确认的 13 张参考图以及同尺寸、同系统栏策略的实际截图，不能把当前构建截图复制成 baseline。建议命名：

`launch-poster`、`login`、`role-picker`、`parent-home`、`teacher-home`、`parent-report`、`teacher-task`、`parent-messages`、`health-profile`、`training-capture`、`training-result`、`backend-overview`、`backend-risk`。

准备好图片后创建 `qa/visual-baseline/manifest.json`，格式：

```json
{
  "maxMeanAbsoluteDifference": 0.015,
  "maxChangedPixelRatio": 0.02,
  "screenshots": [
    {"name": "launch-poster", "baseline": "qa/visual-baseline/launch-poster.png", "actual": "tmp/visual-run/launch-poster.png"}
  ]
}
```

执行：

```bash
python3 scripts/visual_regression.py qa/visual-baseline/manifest.json --root .
```

缺少 baseline、尺寸不同或超过阈值都会失败。当前 xcresult 已保留关键页面截图附件，但没有把它们冒充为用户提供的 13 张批准基线。
