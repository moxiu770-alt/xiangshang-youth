# 发布预检

仓库内的代码门禁只能证明源码、构建和自动化测试；正式发布还必须验证真实服务、签名、崩溃监控、灰度配置和设备。统一入口是：

```bash
# 本地开发：允许 Mock、允许没有设备，但不会把结果标成发布通过
python3 scripts/release_preflight.py --target local --allow-missing-devices

# 试点/生产：从 secret manager 注入环境变量，缺任何阻断项都会退出 1
python3 scripts/release_preflight.py --target pilot --json /tmp/youth-pilot-preflight.json
python3 scripts/release_preflight.py --target production --json /tmp/youth-production-preflight.json

# 设备矩阵探测；缺设备只记录为缺口，不伪造通过
python3 scripts/device_matrix_preflight.py --output /tmp/youth-device-matrix.json
```

`release_preflight.py` 会校验：Remote 数据源和 HTTPS 地址、Sentry DSN、生产密钥长度、对象存储、异地备份、CORS、模型人工验证状态、Git 远程以及设备工具。它不会打印密钥值。

设备报告只记录工具和已连接设备。模拟器/AVD 不能替代真机；必须把 `qa/DEVICE_MATRIX.md` 的每个 P0 尺寸、字体、权限、离线、杀进程和相机场景附上截图、崩溃与性能证据后，才能将发布项标记为通过。
