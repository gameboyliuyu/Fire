# 业火输入法二次开发 · 交接文档（HANDOFF）

> 仓库：`github.com/gameboyliuyu/Fire` · 分支：`feature/enhance`
> 本文档面向接手继续开发的 AI/开发者，读完即可上手。最后更新：2026-11-18

## 一、项目是什么

Fork 自 [qwertyyb/Fire](https://github.com/qwertyyb/Fire)（Swift + InputMethodKit 的 macOS 五笔拼音混合输入法），在 `feature/enhance` 分支上做了两项自有功能：

### 1. 内联计算器（已完成，已实装验证）
- 文件：`Fire/Utils/SmartCalc.swift`（纯 Swift 递归下降解析器）、`Fire/Engine/CalcState.swift`（`=` 进入的子状态）
- 功能：拼音/五笔候选栏直接算术，支持 `1+2*3=`、大写金额（`=1200` 出壹仟贰佰）、中文数字、中文日期
- 已知教训：**不要用 NSExpression**（整除语义错误、抛 ObjC 异常、浮点误差）

### 2. 词频学习·同意点选入库（代码完成，待实装验证）
- 设计哲学（对齐上游 issue #193 结论）：**系统绝不从打字流水猜词**（中文无词边界，猜词必产垃圾词）；只有用户主动确认的词才进词库
- 文件：`Fire/Engine/RootState.swift` 中的 `frequencyLearning()` / `acceptFavoriteHandler()`
- 行为：候选栏选中的**纯中文词**计数 → 满阈值（默认 3，`frequencyThreshold`）→ Toast 提示「按 ⌃⌥= 存入个人词库」→ 用户按 **control+option+=** 才 `addUserText`；不按=忽略，忽略/已入库不再提示
- 开关：`enableFrequencyLearning`（DefaultsKeys.swift，默认 false）
- **2026-11-18 最新修复（待云构建验证）**：新增 `hasText()` 判断——基础词库（wb/py/user 任意类型）已有的词不再提示入库（修复常用单字"滑"也弹提示的 bug）。改动文件：`EngineDictManager.swift`（协议+默认实现）、`DictReader.swift`、`DictManager.swift`、`RootState.swift`、`MockEngineDictManager.swift`、`FrequencyLearningTests.swift`（新增 `baseDictWord_doesNotPrompt` 用例，共 7 个用例）
- 已实装验证的部分：Toast 提示正常弹出（「词【滑】已选 3 次…」截图为证）；⌃⌥= 入库落库待验证

## 二、构建与安装（无本地 Xcode，走 GitHub Actions 云构建）

本机只有 Command Line Tools（无完整 Xcode），`swiftc` 只能 `-parse` 不能 typecheck，**编译验证只能靠云构建**：

1. **触发构建**：POST `repos/gameboyliuyu/Fire/actions/workflows/test.yml/dispatches`，body `{"ref":"feature/enhance"}`（用 `test.yml`，`build.yml` 的证书步骤有 bug 不可用）
2. **看结果**：GET `/actions/runs/{id}`，`conclusion=success` 才算过；失败拉 `/actions/runs/{id}/logs`（zip）
3. **产物**：artifact 名 `dist`（约 91MB zip，内含 `FireInstaller.pkg` 15MB），GET `/actions/artifacts/{id}/zip` 下载（国内限速约 45KB/s，**必须后台下载**）
4. **安装**：`open FireInstaller.pkg` → 输密码装到 `/Library/Input Methods/Fire.app`
5. **重启输入法进程**：`killall Fire` 后系统自动拉起；不要用 `open` 手动拉（菜单挂不上）

## 三、血泪坑清单（每条都真实踩过）

1. **pbxproj 手动注册**：Xcode 传统工程，新增 .swift 文件要在 `project.pbxproj` 四处注入（PBXBuildFile / PBXFileReference / PBXGroup children / Sources Build Phase），漏一处报 `cannot find 'X'`。改完 `plutil -lint` 校验
2. **git push 不可用**：本机 git 推送认证失败（token 会被 shell 环境改写），**所有提交走 GitHub REST API**：`PUT /repos/.../contents/{path}`（带 sha、branch、base64 content）
3. **swiftc -parse 过 ≠ 编译过**：inout 漏 `&`、类型误用这类错误本地查不出来，别把 parse 通过当验证完成
4. **测试文件别把 mock 类型用混**：`TestFixtures.makeRootState` 返回元组第 4 位是 config 不是 context，mock 上下文要自己 new `MockInputContext()`
5. **词库结构**：`~/Library/Application Support/com.qwertyyb.inputmethod.Fire/dict.sqlite`，表 `wb_py_dict(id, wbcode, text, type, ...)`，type ∈ wb/py/user/blocked
6. **菜单栏图标被 Bartender 5 藏了**：图标"消失"先查 Bartender 的 Hide 列表（`defaults read com.surteesstudios.Bartender`），别去查系统注册
7. **验证终点 = 用户可见界面**：配置写对/接口 200 都是中间态
8. **沙箱限制**：`log show` 不可用（Cannot run while sandboxed）、`ps` 常被拒、长命令（下载 91MB）必须 `run_in_background`

## 四、当前待办（按优先级）

1. **P0 · 云构建验证 hasText 修复**：触发 test.yml → 编译+7 个测试全过 → 下载 pkg 安装
2. **P0 · 实装验证入库链路**：连选一个基础词库没有的多字词 3 次 → Toast → ⌃⌥= → 查 `dict.sqlite` user 表新增
3. **P1 · 常用单字验证不再弹提示**（本轮修复目标）
4. **P1 · 拼音输入增强**（已分析未实施，优先级排序）：
   - P0 首字母简拼（`spell` 字段可建索引）
   - P1 拼音反查五笔码（利用现有 spell 数据）
   - P1 模糊音（n/l、前后鼻音，四川用户刚需）
   - P2 整句分词（不建议做，同自动造词哲学冲突）
5. **P2 · 长期**：词频计数持久化（当前内存态，重启丢失——待定是否需要）

## 五、测试与验收清单

- 单元测试：`FireTests/Engine/FrequencyLearningTests.swift` 7 用例（disabled / 阈值提示不自动入库 / ⌃⌥=入库 / 无pending不响应 / 忽略不再提示 / 屏蔽词 / **基础词已有词不提示**）
- 实装验收：① Toast 弹出文案正确 ② ⌃⌥= 后 dict.sqlite 出现新 user 行 ③ 忽略后不再提示 ④ 基础词库已有词不提示 ⑤ 长句打字零垃圾词新增（对照 `dict.sqlite` mtime）
