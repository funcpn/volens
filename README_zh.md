# 如意 (volens)

> 中文版 | [English](README.md)

「如意」是一款针对 Claude Code 开发的插件（以后可能会适配不同 Agent），它维护一套能让项目文档紧跟决策、始终保持新鲜的结构 —— 设计文档自动跟随你的每一次决策，而你无需操心。并且你只需要在项目下，向 Claude Code 发送过一次 `/volens:volens`，“法术”即永久生效，无需在心意变化时再次施法。

## 为什么你需要「如意」

得益于大模型能力的日新月异和 Agent 产品的不断成熟，我们的灵感能在 Agent 的帮助下快速实现，不用因为五花八门的编程技术望而却步。然而在将一个不成熟的想法推进到成熟作品落地的过程中，随着我们对想法的不断丰富、对每个细节的推敲，以及一边开发一边对各种技术的了解和择优，我们脑海中的蓝图随时会产生变化，这些变化可能会推翻某些决策，也可能让我们在某些决策上反复拉扯。并且随着时间的推移，手工维护的设计文档可能会悄悄过期，误导我们的同时，也让项目变得混乱，让模型也更容易产生幻觉。

「如意」是一个为了解决上述问题的插件：

- 它通过维护一个**只追加的决策日志**（`docs/DECISION-LOG.md`），记录我们的每一次决策，让每一步决策都历史可查。

- 从**决策日志中派生设计文档**（`docs/DESIGN.md`），并且能够自动更新设计文档，保证设计文档紧跟决策的变化，保持常新，而我们无需操心。

- 不论是新创意落地，还是需要迭代已有项目，你都可以使用「如意」来帮助你。你只需在 Agent 的输入框里发送 `/volens:volens`，「如意」就会在项目下就位 `docs/DECISION-LOG.md` 和 `docs/DESIGN.md`（全新项目的设计快照由 hook 首次同步时生成），并且保证设计文档紧紧跟随你的决策。

「如意」能够保证设计文档紧跟你的想法，你只需要让 Agent 根据设计文档实现代码，整个项目就能如你心意。

建议将「如意」安装到用户级，在你需要管理的项目内，发送一次 `/volens:volens` 即可。

---

## 它是如何运行的

执行一次 `/volens:volens`，如意会先勘察项目里已有的东西（**不会覆盖**），然后在项目里就位下列文件：

- **`CLAUDE.md` 的契约模块** —— 文件不存在则新建一个只含契约模块的文件；已存在则只在标记之间插入或更新契约模块：「文档模型 + 工作约定」，其余内容一律不动。
- **`docs/DECISION-LOG.md`** —— 一个只追加的**决策日志**，种下第一条「采用本结构」的记录；以后每个设计决策都追加到这里，历史只增不改。
- **`docs/DESIGN.md`** —— 由日志派生的**设计快照**。已有项目在搭建时即生成；全新项目则先跳过，由 hook 在第一次同步时从决策日志生成。
- **`.claude/volens.lang`** —— 本项目文档用什么语言记录的「项目级决定」（如 `zh`/`en`），只问一次、提交入库。
- **`docs/.volens-cursor`** —— hook 的游标：记录「设计文档已反映到日志的第几行」。纯运行状态，会写进 `.gitignore`，不入库。

同步脚本本身随插件走，**不会写进你的项目** —— 项目里只有上面这些属于你自己的文件。

这些文件就位后，日常的「保鲜」由一条 **追加 → 察觉 → 增量同步** 的循环自动完成：

1. **决策落笔** —— 你每做一次设计决策，就往 `docs/DECISION-LOG.md` 追加一条（Context → Decision → Consequences），只追加、不改写历史。
2. **Hook 察觉** —— 在 `Stop`（一次回复结束）和 `SessionStart`（会话开始）两个时机，同步脚本自动运行，比较日志行数与 `docs/.volens-cursor` 游标。
3. **增量注入** —— 日志比游标多出几行，就把「那几行」作为额外上下文塞给 Agent，请它据此同步；若设计文档已最新，则静默快进游标。
4. **局部重生成** —— Agent 只更新设计文档中受影响的章节、「Design decisions in force」列表和「Last regenerated」头部，不重读整本日志、也不整篇重写；若日志被改写或回滚（行数变少），则重置游标、提示完整重建 `docs/DESIGN.md`。

于是 `docs/DESIGN.md` 永远是一份「当下最新」的设计快照——由日志派生、被 hook 保鲜，你只管做决策，剩下的交给「如意」。

---

## 安装与首次运行

开始之前，你的机器上得先装好 **Claude Code**。

「如意」有两种装法。**如果你访问 GitHub 需要开代理，或者不确定 `git` 命令能不能用，走第一种。**

### 装法一：下载压缩包（不依赖 git）

只要浏览器能打开 GitHub 就行。

1. 打开 https://github.com/funcpn/volens
2. 点绿色的 **Code** 按钮 → **Download ZIP**
3. 解压。解出来叫 `volens-master`，**把它改名为 `volens`**
4. 整个文件夹移到你的 skills 目录下：
   - macOS / Linux：`~/.claude/skills/`
   - Windows：`%USERPROFILE%\.claude\skills\`

   目录不存在就自己建。放好后路径是 `…/.claude/skills/volens/`，里面应该能看到 `.claude-plugin`、`skills`、`hooks` 三个文件夹。
5. 重启 Claude Code。敲 `claude plugin list` 确认能看到 `volens@skills-dir`，状态是 `✔ loaded`

> 会用 git 的话，第 1–4 步可以直接换成一条命令，效果一样（同样需要能访问 GitHub）：
>
> ```sh
> git clone https://github.com/funcpn/volens.git ~/.claude/skills/volens
> ```

### 装法二：从市场安装（需要 git 且能访问 GitHub）

**先确认这两条：**

- **`git` 在 PATH 上。** Windows 装 Git for Windows 时，到「Adjusting your PATH environment」那一步要选 **「Git from the command line and also from 3rd-party software」**。只选了「Use Git from Git Bash only」的话，Git Bash 能打开，但 `git` 不在 PATH 上，Claude Code 会找不到它。
- **能访问 GitHub。** 注意：**`git` 不会自动走浏览器或 VPN 的代理**。开着代理/VPN 的话，需要切到全局模式，或者单独给 git 配代理。

**然后，一条一条敲，每条敲完按回车：**

1. 敲这条：

   ```
   /plugin marketplace add https://github.com/funcpn/volens.git
   ```

   > 用完整地址。别用 `funcpn/volens` 这种简写 —— 简写会走 SSH，没配过 GitHub 密钥的机器会失败。

2. 看到成功提示后，再敲这条：

   ```
   /plugin install volens@volens
   ```

3. 重启 Claude Code

### 想让一个项目里所有人都自动装上

```sh
claude plugin install volens@volens -s project
```

它往项目的 `.claude/settings.json` 写一行 `enabledPlugins`。这一行提交入库之后，**协作者克隆下来就自动生效**，不用各自再去装一遍。

### 然后，在你想纳入这套结构的项目里

```
/volens:volens
```

它会先勘察已有的东西（**不会覆盖**），设定文档语言（一次性），确保 CLAUDE.md 契约模块就位，种下 `docs/DECISION-LOG.md`，并确认同步 hook 已就位。之后，每当一个设计决策改变，就往日志里**追加**一条；剩下的交给 hook。

---

## 许可证

本项目基于 MIT 许可证开源，详见 [LICENSE](LICENSE)。

