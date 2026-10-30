# 全局 Coding Agent 规则增补：Karpathy 风格的简洁开发约束（2026-10-30）

**状态：待本机 Agent 应用。** 这是对用户已经部署的**个人全局 Agent 规则**的局部增补指南，不是本仓库的项目级 `AGENTS.md`，也不是第三方 Skill 的复制或自动安装。

## 已核实的现状

- 用户曾在 2026-09-15 将一份共享全局规则从本机未跟踪文件 `E:\MachineContext\.local\global-rules-canonical.md` 部署到多个 Agent；详见 `docs/devlog/2026-09-15-global-rules-and-cli-upgrades.md` 和 09-16 的 OMP 纠错记录。
- 规则已包含六个中文章节：`沟通`、`任务执行`、`仓库状态`、`测试与验证`、`Git 与开发环境`、`完成与汇报`。**GitHub 仓库没有这份全局规则的完整正文**，不能假设此文档可以直接替换任一真实 `AGENTS.md`。
- `E:\MachineContext\AGENTS.md` 是 **MachineContext 本项目级规则**，不是用户全局规则。不能把本增补直接写进它，并宣称已影响 Codex 等其他项目。
- 本机存有原来的各宿主规则文件；具体版本和内容必须由本地 Agent 只读检查。外部原版 Ponytail 和 STS 的 Plugin/Hook 单独安装；不把它们的全部规则重复写进全局指令。

## 应合并的短小行为增补

> 这是 **基于 Karpathy-inspired 社区规则的 AgentKit 自有短版**，非 Andrej Karpathy 本人官方 Skill、非原文转载。只纳入现有规则中尚未覆盖的意思；无须复制成新章节。如果原规则已含等价条款，以原有措辞为准。

**建议融入现有「任务执行」章节：**

- 在满足用户已确认的完整需求、产品/架构决定和现有项目约束的前提下，优先采用当前代码库/框架已有的最直接、可维护实现；不因“精简”删减明确要求的功能。
- 不为假想的未来用途新增抽象、配置、兼容分支、备用系统、冗余备份或额外步骤；新增防御须对应实际使用方、受支持的失败场景或真实安全/数据风险。
- 修改应限于目标及其必要影响链，不顺手重构无关代码；简单任务直接实施，复杂任务才安排必要阶段，不重复已经完成的规划。

**建议融入现有「测试与验证」章节：**

- 选择与改动影响及风险相称的最少**有效**验证，复用对当前最终状态仍有效的测试结果；不为“再保险”反复执行无关套件、制造测试框架或审查循环。
- 用户或项目明确要求的安全、权限、事务、迁移、数据完整性、设备实机/发布门禁照常执行，不能用 YAGNI 或省 Token 为理由跳过。

**「完成与汇报」仅在原文缺失时补充一句：**任务达成、必要证据足够、没有范围内现实阻塞即收口；如实区分已验证与未验证。

## 本地 Agent 一次性执行任务

1. 先只读核对 `E:\MachineContext\docs\devlog\2026-09-15-global-rules-and-cli-upgrades.md`、09-16 OMP 纠错记录，及真实全局 `%USERPROFILE%\.codex\AGENTS.md`、`%USERPROFILE%\.claude\CLAUDE.md`、`%USERPROFILE%\.gemini\config\GEMINI.md` 等。若存在 `E:\MachineContext\.local\global-rules-canonical.md`，把它当候选原始模板，先与真实部署版本核对是否发生人工改动；**不能因为模板存在就覆盖较新的本机配置**。
2. 仅将上述**缺少**的意思融入共享原文的现有段落；保留六个章节、旧偏好、Git/commit/push 规则、项目范围、开发机器特殊约束。不添加整套 Karpathy Skill、重复叙述 Ponytail/STS，也不附加新一轮固定工作流。
3. 以核对后的真实版本为基础，形成一份可供复用的更新稿。分别按宿主实际语法部署到原有**全局**路径；如果个别宿主配置已有独立用户追加规则，先合并其语义而不是整文件替换。避免项目 `AGENTS.md` 或 Claude 项目规则被覆盖。
4. 已知目标：
   - Codex CLI/Desktop：`%USERPROFILE%\.codex\AGENTS.md`；
   - Claude Code：`%USERPROFILE%\.claude\CLAUDE.md`（Grok 曾复用它，须检查当前版本的加载关系）；
   - Agy：`%USERPROFILE%\.gemini\config\GEMINI.md`；
   - ZCode：`%USERPROFILE%\.zcode\AGENTS.md`；
   - Qoder CN：`%USERPROFILE%\.qoder-cn\rules\global-personal-rules.md`（保留已有 `always_on` 元数据）；
   - OMP：曾通过 `%USERPROFILE%\.omp\agent\config.yml` 中 `enabledProviders: [codex]` 加载 Codex 全局规则，**不要额外复制同份全文**；
   - DSH、TRAE、其他近期增加的 Agent：依据 MachineContext **当前本地**记录/官方宿主机制核实后再维护，不能假设 2026-09 的路径仍不变。
5. 对确实安装了 Ponytail 原生 Plugin 的 Codex/Claude，不再额外注入整份 Ponytail `AGENTS.md`；STS 原生 Hook 的启用与信任由宿主独立管理。这里只更新精简的公共工程偏好，不负责安装插件。
6. 验证本地各目标实际文本及加载机制；验证用户级全局加载时，使用**不含项目 `AGENTS.md`/ `CLAUDE.md` 的临时工作目录**，不能从 `E:\MachineContext` 项目内运行并误把项目规则当全局规则。测试后清理仅自己生成的临时产物。
7. 最后报告**实际修改的文件**、保留/合并的用户原有规则、哪些宿主已验证真实加载、未验证项及原因。除非任务内容要求，不进行软件升级、重装、模型切换、全局配置重构或重复备份。若需要将规则修订记录纳入 MachineContext，只保存安全摘要/路径与事实，不提交用户私有规则全文、凭据或配置原文到此仓库。

完成判断：实机共享全局规则保留原有能力，补齐少量原则，与 Ponytail/STS 原生插件无明显重复冲突；不以“再生成几份 AGENTS.md”作为完成标准。
