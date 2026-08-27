# 可发布基线

候选版本必须同时满足：

1. Git 工作区干净，候选提交已推送到受保护远程分支；
2. `python3 scripts/check_large_file_boundaries.py` 通过；
3. `python3 scripts/check_frontend_contract.py` 与 `python3 scripts/check_model_contract.py` 通过；
4. 后端 check、OpenAPI lint、单元测试和独立测试数据库集成测试通过；
5. iOS XCTest/UI Test 与 Android unit/lint/Compose UI Test 保存证据；
6. `release_preflight.py --target pilot` 通过；
7. 使用专用家长、教师账号执行真实远程只读验收；
8. 写入验收只操作专用测试任务、学生、活动和预约时段；
9. 候选提交打注释标签，记录数据库 migration、镜像 digest、iOS build、Android versionCode；
10. 保留上一个稳定镜像、数据库备份验证记录和移动端回滚版本。

禁止进入候选基线：本地 `.env`、账号密码、证书私钥、Provisioning Profile、对象存储密钥、真实儿童健康明细、原始摄像头帧。

大文件预算不是最终目标，而是防止重新合并。后端 `server.js` 下一阶段继续拆分 AuthSession、AdminSchool 和 FileStorage 路由；当前新增业务必须直接进入领域路由文件。

当前领域边界：

- iOS：会话/角色恢复、领域数据投影、课程、健康、通知、排期、教师任务和支持能力分别位于 `AppState+*.swift`；身体基础数据、姿态算法和结果视图已分文件。
- Android：会话恢复与登录、教师任务、社区健康和支持能力分别位于 `AppState*.kt`；身体基础数据和姿态算法已分文件。
- 后端：Activity、Appointment、ClassCircle、Course、Notification、FamilyHealth、TeacherTask 和场地端路由已有独立模块；学生导入解析已从主服务抽离。主服务剩余 AuthSession、场地编排和管理端路由是后续拆分对象。

真实远程验收必须遵循 [REMOTE_WORKFLOW_ACCEPTANCE.md](REMOTE_WORKFLOW_ACCEPTANCE.md)，并将脱敏后的输出作为候选提交证据。没有专用测试账号、独立测试数据库和可访问的 HTTPS 环境时，候选只能标记为“本地可构建基线”，不能标记为“学校试点远程闭环已验收”。
