# 跨端前端契约门禁

`scripts/check_frontend_contract.py` 是依赖零安装的静态门禁，已接入主 CI 的
`source-integrity` job。它检查：

- iOS/Android 纯启动海报的系统栏处理与学校后台看板迁移入口；
- 移动端只保留家庭端、教师端工作台，旧校长工作台文件不得回归；
- 双端相机权限、前后摄像头、语音指导和明文流量防护；
- MockRepository 默认入口、RemoteRepository 替换边界和 Release 占位地址拦截；
- 家长数据导出/删除申请、身体测评数据使用同意撤回，以及账户注销申请的双端 API、状态和入口；
- 登录方式、孩子绑定、报告回退和角色切换的 XCTest/Compose UI 流程存在。
- 教师账号不开放移动端自助注册；登录页明确显示家长注册，学校账号统一由后台批量授权；双端底部工作台使用平台原生导航组件。

UI 测试还会把启动海报、角色选择、教师首页、家庭首页和报告详情截图写入 iOS xcresult；Android
Instrumentation 也会把启动海报写入测试沙盒并由主 CI 拉取。主 CI 会上传这些证据包。它们不替代真机截图、动态辅助功能和真实服务联调。把授权参考图放入发布
流水线后，可在此基础上接像素差异工具；视觉像素差异与系统权限行为仍由
`qa/DEVICE_MATRIX.md` 的设备矩阵验收证明。

像素差异执行入口为 `scripts/visual_regression.py`，基线目录和 manifest 约束见
`qa/visual-baseline/README.md`。基线必须来自产品确认的 13 张参考图，不能由当前构建截图反向生成。

本地运行：

```bash
python3 scripts/check_frontend_contract.py
```
