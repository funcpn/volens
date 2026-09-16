# 如意 (volens)

> 中文版 | [English](README.md)

「如意」是一款面向编码 Agent 的插件 —— 今天支持 Claude Code 和 Codex —— 它维护一套能让项目文档紧跟决策、始终保持新鲜的结构：设计文档自动跟随你的每一次决策，而你无需操心。并且你只需要在一个项目里启用过一次它，「法术」即永久生效，无需在心意变化时再次施法。

## 为什么你需要「如意」

得益于大模型能力的日新月异和 Agent 产品的不断成熟，我们的灵感能在 Agent 的帮助下快速实现，不用因为五花八门的编程技术望而却步。然而在将一个不成熟的想法推进到成熟作品落地的过程中，随着我们对想法的不断丰富、对每个细节的推敲，以及一边开发一边对各种技术的了解和择优，我们脑海中的蓝图随时会产生变化，这些变化可能会推翻某些决策，也可能让我们在某些决策上反复拉扯。并且随着时间的推移，手工维护的设计文档可能会悄悄过期，误导我们的同时，也让项目变得混乱，让模型也更容易产生幻觉。

「如意」是一个为了解决上述问题的插件：

- 它通过维护一个**只追加的决策日志**（`docs/DECISION-LOG.md`），记录我们的每一次决策，让每一步决策都历史可查。

- 从**决策日志中派生设计文档**（`docs/DESIGN.md`），并且能够自动更新设计文档，保证设计文档紧跟决策的变化，保持常新，而我们无需操心。

- 不论是新创意落地，还是需要迭代已有项目，你都可以使用「如意」来帮助你。你只需在 Claude Code 的输入框里发送 `/volens:volens`，「如意」就会在项目下就位 `docs/DECISION-LOG.md`，并让设计快照跟着你的决策走。

「如意」能够保证设计文档紧跟你的想法，你只需要让 Claude Code 根据设计文档实现代码，整个项目就能如你心意。

---

## 它是如何运行的

执行一次 `/volens:volens`，如意会先勘察项目里已有的东西（**不会覆盖**），然后在项目里就位下列文件：

- **指令文件的契约模块** —— Claude Code 下是 `CLAUDE.md`，Codex 下是 `AGENTS.md`。文件不存在则新建一个只含契约模块的文件；已存在则只在标记之间插入或更新契约模块：「文档模型 + 工作约定」，其余内容一律不动。
- **`docs/DECISION-LOG.md`** —— 一个只追加的**决策日志**，种下第一条「采用本结构」的记录；以后每个设计决策都追加到这里，历史只增不改。
- **`docs/DESIGN.md`** —— 由日志派生的**设计快照**。已有项目在搭建时即生成；全新项目则先跳过，由 hook 在第一次同步时从决策日志生成。
- **`.volens/lang`** —— 本项目文档用什么语言记录的「项目级决定」（如 `zh`/`en`），只问一次、提交入库。（早先版本把它放在 `.claude/volens.lang`；老项目里的那份会在下一次刷新时自动搬过来。）
- **`docs/.volens-cursor`** —— hook 的游标：记录「设计文档已反映到日志的第几行」。纯运行状态，会写进 `.gitignore`，不入库。

同步脚本本身随插件走，**不会写进你的项目** —— 项目里只有上面这些属于你自己的文件。

这些文件就位后，日常的「保鲜」由一条 **追加 → 察觉 → 增量同步** 的循环自动完成：

1. **决策落笔** —— 你每做一次设计决策，就往 `docs/DECISION-LOG.md` 追加一条（Context → Decision → Consequences），只追加、不改写历史。
2. **Hook 察觉** —— 在 `Stop`（一次回复结束）和 `SessionStart`（会话开始）两个时机，同步脚本自动运行，比较日志行数与 `docs/.volens-cursor` 游标。
3. **增量注入** —— 日志比游标多出几行，就把「那几行」作为额外上下文塞给 Claude Code，请它据此同步；若设计文档已最新，则静默快进游标。
4. **局部重生成** —— Claude Code 只更新设计文档中受影响的章节、「Design decisions in force」列表和「Last regenerated」头部，不重读整本日志、也不整篇重写；若日志被改写或回滚（行数变少），则重置游标、提示完整重建 `docs/DESIGN.md`。

于是 `docs/DESIGN.md` 永远是一份「当下最新」的设计快照——由日志派生、被 hook 保鲜，你只管做决策，剩下的交给「如意」。

---

## hook 到底做了什么 —— 以及它不做什么

同步脚本随插件分发。在 Claude Code 下它由 `hooks/hooks.json` 注册，在 `Stop`（一次回复结束）和 `SessionStart`（会话开始、被清空或被压缩）两个时机运行；在 Codex 下由 `hooks/hooks-codex.json` 注册，在 `SessionStart` 和 `UserPromptSubmit`（你下一次发消息时）运行。它是同一个 shell 脚本。

**它读什么** —— `docs/DECISION-LOG.md` 的**行数**、`docs/.volens-cursor` 里存的那个数字、`docs/DESIGN.md` 的**修改时间**，以及你的语言偏好（`~/.config/volens/lang` —— 设置了 `XDG_CONFIG_HOME` 就在它下面 —— 或项目里的 `.volens/lang`）。

就这些。**它不读你日志的内容、不读设计文档的内容、不读你的源代码** —— 它只数一个文件的行数、比一个时间戳。

**它写什么** —— 只有一个文件：`docs/.volens-cursor`。它**不自己写** `docs/DESIGN.md`，而是发一条提示请 Claude 去写；游标要等那次写入落地之后才前进。

**它不做什么：**

- **不联网。** 没有 HTTP、没有 socket、没有遥测、没有统计。任何东西都不会离开你的机器。
- **不写 `docs/` 以外的任何地方。** 不碰你的源码，不碰你的指令文件；`.volens/lang` 那份语言它只读、不写。
- **不执行你项目里的任何东西。** 脚本是固定的，随插件走。
- **不阻断任何操作。** 它永远 `exit 0`，只能往对话里追加信息，拦不住一次回复、也拒绝不了工具调用。

没有东西可同步时它**什么都不打印**。**沉默意味着没有注入，不代表出错了。**

---

## 安装与首次运行

在 Claude Code 里装上「如意」。前置条件就两条：

- `git` 在 PATH 上
- `git` 能访问 GitHub

1. 添加市场：

   ```
   /plugin marketplace add https://github.com/funcpn/volens.git
   ```

   > 用完整地址。别用 `funcpn/volens` 这种简写 —— 简写会走 SSH，没配过 GitHub 密钥的机器会失败。

2. 从市场安装：

   ```
   /plugin install volens@volens
   ```

3. 确认安装状态：执行 `claude plugin list`，看到 `volens@volens`、状态是 `✔ enabled`，就说明装好了。

### 如何使用

插件要**重启一次 Claude Code** 才会加载进来。重启之后，在你想纳入这套结构的项目里执行：

```
/volens:volens
```

它会先勘察已有的东西（**不会覆盖**），设定文档语言（一次性），确保指令文件的契约模块就位，种下 `docs/DECISION-LOG.md`，并确认同步 hook 已就位。之后，每当一个设计决策改变，就往日志里**追加**一条；剩下的交给 hook。

### 在 Codex 里使用

「如意」同样作为插件装在 Codex 里，走 Codex 自己的市场机制：

1. 添加市场：

   ```
   codex plugin marketplace add https://github.com/funcpn/volens
   ```

2. 安装：

   ```
   codex plugin add volens@volens
   ```

3. 确认：`codex plugin list` 里能看到 `volens`，状态是 `installed, enabled`。

**第一次运行要信任一次 hook。** 第一次在 Codex 里开会话时会看到 `Hooks need review`，选 **Trust all and continue**。不选的话插件装上了，但设计文档不会自动更新。以后升级「如意」**不需要**重新信任 —— 只有它改动了 hook 命令本身才会再问一次。

装好之后，在你想纳入这套结构的项目里，让 Codex 用一次「如意」的 skill（比如直接说：「用 volens 给这个项目建立文档结构」）。它会做和 Claude Code 下一样的事，只是契约模块落在 `AGENTS.md` 里。

同步时机和 Claude Code 略有不同：Codex 下发生在 `SessionStart`（会话开始）和 `UserPromptSubmit`（你下一次发消息时）。也就是说会话中途记下的决策，会在你下一次输入时落到设计文档里。

### 备选安装方法：下载压缩包

如果 `git`不能访问 GitHub，可以改用下载：

1. 在本仓库主页，点上方绿色的 **Code** 按钮 → **Download ZIP**
2. 解压。解出来的文件夹名带分支后缀（比如 `volens-main`），**把它改名为 `volens`**
3. 整个文件夹移到你的 skills 目录下：
   - macOS / Linux：`~/.claude/skills/`
   - Windows：`%USERPROFILE%\.claude\skills\`

   目录不存在就自己建。放好后路径是 `…/.claude/skills/volens/`，里面应该能看到 `.claude-plugin`、`skills`、`hooks` 三个文件夹。
4. 重启 Claude Code。敲 `claude plugin list` 确认能看到 `volens@skills-dir`，状态是 `✔ loaded`

> ⚠️ **这条路没有自动更新。**「如意」以后发新版本时不会有任何提示，你得自己回来重新下载、覆盖一遍。**能用市场就用市场。**

---

## 许可证

本项目基于 MIT 许可证开源，详见 [LICENSE](LICENSE)。
