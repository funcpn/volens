# 如意 (volens)

> 中文版 | [English](README.md)

「如意」是一款面向编码 Agent 的插件，它维护一套能让项目文档紧跟决策、始终保持新鲜的结构：设计文档自动跟随你的每一次决策，而你无需操心。并且你只需要在一个项目里启用过一次它，「法术」即永久生效，无需在心意变化时再次施法。

现已适配：

- Claude Code
- Codex CLI、ChatGPT（桌面端）
- DeepSeek Harness（DSH）

> 更多 Agent 支持在计划中。

## 为什么你需要「如意」

得益于大模型能力的日新月异和 Agent 产品的不断成熟，我们的灵感能在 Agent 的帮助下快速实现，不用因为五花八门的编程技术望而却步。然而在将一个不成熟的想法推进到成熟作品落地的过程中，随着我们对想法的不断丰富、对每个细节的推敲，以及一边开发一边对各种技术的了解和择优，我们脑海中的蓝图随时会产生变化，这些变化可能会推翻某些决策，也可能让我们在某些决策上反复拉扯。并且随着时间的推移，手工维护的设计文档可能会悄悄过期，误导我们的同时，也让项目变得混乱，让模型也更容易产生幻觉。

「如意」是一个为了解决上述问题的插件：

- 它通过维护一个**只追加的决策日志**（`docs/DECISION-LOG.md`），记录我们的每一次决策，让每一步决策都历史可查；

- 从**决策日志中派生设计文档**（`docs/DESIGN.md`），并且能够自动更新设计文档，保证设计文档紧跟决策的变化，保持常新，而我们无需操心；

- 不论是新创意落地，还是需要迭代已有项目，你都可以使用「如意」来帮助你，让设计快照跟着你的决策走。

「如意」能够保证设计文档紧跟你的想法，你只需要让你的 Agent 根据设计文档实现代码，整个项目就能如你心意。

---

## 它是如何运行的

在项目里跑一次「如意」（Claude Code：`/volens:volens`；Codex：`$volens:volens`；DSH：`/volens`），它会先勘察项目里已有的东西（**不会覆盖**），然后在项目里就位下列文件：

- **指令文件的契约模块** —— Claude Code 下是 `CLAUDE.md`，Codex 和 DSH 下是 `AGENTS.md`（DSH 会同时加载 `AGENTS.md` 与 `CLAUDE.md`，只有两者内容完全相同时才去重）。文件不存在则新建一个只含契约模块的文件；已存在则只在标记之间插入或更新契约模块：「文档模型 + 工作约定」，其余内容一律不动。
- **`docs/DECISION-LOG.md`** —— 一个只追加的**决策日志**，种下第一条「采用本结构」的记录；以后每个设计决策都追加到这里，历史只增不改。
- **`docs/DESIGN.md`** —— 由日志派生的**设计快照**。已有项目在搭建时即生成；全新项目则先跳过，由同步机制在第一次同步时从决策日志生成。
- **`.volens/lang`** —— 本项目文档用什么语言记录的「项目级决定」，写成**语言标签**（`zh`、`en`、`pt-BR`），只问一次、提交入库。不是标签的值会被忽略：同步机制会回退到你的偏好，并在下次同步通知里说明。（早先版本把它放在 `.claude/volens.lang`；老项目里那份仍然管用，下次刷新时「如意」会把它搬到新位置。）
- **`docs/.volens-cursor`** —— 同步机制的游标：记录「设计文档已反映到日志的第几行」。纯运行状态，会写进 `.gitignore`，不入库。

同步机制本身随插件走，**不会写进你的项目** —— 项目里只有上面这些属于你自己的文件。

这些文件就位后，日常的「保鲜」由一条 **追加 → 察觉 → 增量同步** 的循环自动完成：

1. **决策落笔** —— 你每做一次设计决策，就往 `docs/DECISION-LOG.md` 追加一条（Context → Decision → Consequences），只追加、不改写历史。
2. **自动察觉** —— 每到会话时机，同步就自动运行（Claude Code：`Stop`（一次回复结束）和 `SessionStart`（会话开始）；Codex：`UserPromptSubmit`（你每一次发消息）；DSH：每一轮对话的开头，由进程内插件触发），比较日志行数与 `docs/.volens-cursor` 游标。
3. **增量注入** —— 日志比游标多出几行，就把「那几行」作为额外上下文塞给 Agent，请它据此同步；若设计文档已最新，则静默快进游标。
4. **局部重生成** —— Agent 只更新设计文档中受影响的章节、「Design decisions in force」列表和「Last regenerated」头部，不重读整本日志、也不整篇重写；若日志被改写或回滚（行数变少），则重置游标、提示完整重建 `docs/DESIGN.md`。

于是 `docs/DESIGN.md` 永远是一份「当下最新」的设计快照——由日志派生、被自动保鲜，你只管做决策，剩下的交给「如意」。

---

## 同步机制到底做了什么 —— 以及它不做什么

同步机制随插件分发。在 Claude Code 下它由 `hooks/hooks.json` 注册，在 `Stop`（一次回复结束）和 `SessionStart`（会话开始、被清空或被压缩）两个时机运行；在 Codex 下由 `hooks/hooks-codex.json` 注册，只在 `UserPromptSubmit`（你每一次发消息时）运行——这两家共用同一个 shell 脚本。DSH 不走 hook：同一套逻辑以 JavaScript 跑在它自己的进程里（`dsh/index.js`），在每一轮对话的开头触发。

**它读什么** —— `docs/DECISION-LOG.md` 的**行数**、`docs/.volens-cursor` 里存的那个数字、`docs/DESIGN.md` 的**修改时间**，以及你的语言偏好（`~/.config/volens/lang` —— 设置了 `XDG_CONFIG_HOME` 就在它下面 —— 或项目里的 `.volens/lang`）。

就这些。**它不读你日志的内容、不读设计文档的内容、不读你的源代码** —— 它只数一个文件的行数、比一个时间戳。

**它写什么** —— 只有一个文件：`docs/.volens-cursor`。它**不自己写** `docs/DESIGN.md`，而是发一条提示请 Agent 去写；游标要等那次写入落地之后才前进。

**它不做什么：**

- **不联网。** 没有 HTTP、没有 socket、没有遥测、没有统计。任何东西都不会离开你的机器。
- **不写 `docs/` 以外的任何地方。** 不碰你的源码，不碰你的指令文件；`.volens/lang` 那份语言它只读、不写。
- **不执行你项目里的任何东西。** 这套逻辑是固定的、随插件走：Claude Code 和 Codex 下是一个 shell 脚本，DSH 下是跑在 Agent 进程里的插件代码。
- **不阻断任何操作。** Claude Code 和 Codex 下它永远 `exit 0`，DSH 下它不返回任何决定——无论哪种，它都只能往对话里追加信息，拦不住一次回复、也拒绝不了工具调用。
- **不注入子会话（DSH）。** 子 Agent 继承父级的工作目录、却无法据此行动，所以 DSH 下子会话会被跳过。

没有东西可同步时它**什么都不打印**。**沉默意味着没有注入，不代表出错了。**

---

## 安装

前置条件：

- `git` 在 PATH 上
- `git` 能访问 GitHub
- 一个能跑脚本的 bash

> macOS / Linux 自带；Windows 上推荐安装 Git for Windows —— 装了 WSL 的话，`Windows\System32` 里那个 `bash.exe` 不算：它是 WSL 的启动器，跑不了这个 hook。
>
> **DSH 是例外**：它不需要 bash（同步逻辑跑在进程里），但技能那一半要从本仓库取得，所以你仍然需要 `git`（或下面的压缩包）来拿到仓库。

### 在 Claude Code 里安装

1. 添加市场：

   ```
   /plugin marketplace add https://github.com/funcpn/volens.git
   ```

2. 从市场安装：

   ```
   /plugin install volens@volens
   ```

3. 确认安装状态：执行 `claude plugin list`，看到 `volens@volens`、状态是 `✔ enabled`，就说明装好了。

### 在 Codex 里安装

「如意」同样作为插件装在 Codex 里，走 Codex 自己的市场机制：

1. 添加市场：

   ```
   codex plugin marketplace add https://github.com/funcpn/volens
   ```

2. 从市场安装：

   ```
   codex plugin add volens@volens
   ```

3. 确认安装状态：执行 `codex plugin list`，能看到 `volens`，状态是 `installed, enabled`，就说明装好了。

市场和插件同名（都叫 `volens`），所以安装那行写成 `volens@volens`——前面是市场，后面是插件。

### 在 ChatGPT 桌面端（Codex）里安装

桌面端用的是同一个插件、同一套机制：在插件界面里添加市场 `https://github.com/funcpn/volens`（**Git ref** 留空），再安装 `volens` 即可。装好之后的用法与 Codex 完全一样——斜杠菜单里会出现 `volens:volens`。

只有两处不一样，都值得在依赖它之前知道：

- **安装不等于授权 hook，而且没有任何提示。** 未授权的 hook 会被静默跳过——没有弹窗、没有角标、没有注入——插件看起来一切正常，`docs/DESIGN.md` 却悄悄停止更新。要授权，打开「如意」的插件详情（manage）页，在 *"1 hook needs review before it can run"* 下面点 **Trust all**。那一页展示的是它要运行的命令字符串（哪个文件会被执行），不是脚本内容；信任绑在这条字符串上，所以之后插件更新只要不改命令就不会再问一次。
- **同步通知是悬停提示，不是对话里的一行。** 把鼠标停在会话里的钩子图标上才看得到（终端 CLI 会直接内联打印同一行：`↳ Hook · 📝 DECISION-LOG …`）。

### 在 DSH 里安装

DSH 不像另外两家那样读插件清单。它把 **cordis bundle**——带配置层的 npm 包——加载进自己的进程，而技能是从**文件系统目录**里发现的，不是由插件清单声明的。所以在 DSH 上「如意」要装**两步**，一步一半。

1. 把插件装进某个 profile：

   ```
   dsh plugin --profile web add volens-dsh
   ```

   这条命令就是在那份 profile 目录（`~/.dsh/profiles/web`）里执行 `pnpm add`；`web` 是 DSH 自带的 web 端模板，换成你自己的 profile 名即可。包本身声明了 bundle，所以装完它的配置层就对这份 profile 生效。

2. 让技能可被发现——DSH 从文件系统目录发现技能，插件清单声明不了它，所以技能得单独就位。先把本仓库拿到手（`git clone`，或后面「备选安装方法」里的压缩包），再把它链接进 DSH 会扫描的目录：

   ```
   ln -s /path/to/volens/skills/volens ~/.agents/skills/volens
   ```

   其中 `/path/to/volens` 就是你拿到的那份仓库。DSH 会扫描 `~/.agents/skills`、`~/.dsh/skills`，以及项目内的 `.agents/skills` 和 `.dsh/skills`。符号链接即可（DSH 会跟随），所以技能只留一份。在输入框里敲 `/`，菜单里应当能看到 `volens`。

3. 重启 DSH：profile 的 patch 与插件模块都是启动时读取的。

依赖它之前，有两件事值得先知道：

- **插件更新靠重装。** `dsh plugin add` 是把包**复制**进 profile，不是链接过去；所以改了包之后，要再跑一次 `add` 才会生效。技能是符号链接，不需要任何操作。
- **同步通知是一条折叠的上下文行，不是独立的一行提示。** 找一个小上下文图标，旁边写着 `volens` 和通知文字——它和工具调用行排在一起，很容易划过。同步本身不依赖你是否看见它。

### 备选安装方法：下载压缩包

如果 `git` 不能访问 GitHub，Claude Code、Codex，以及 DSH 的技能那一半，都可以改用下载。下载和解压是通用的，装进哪个 Agent 里则各走各的路。

先把文件夹拿到手：

1. 打开本仓库的 **Releases** 页面，在最新一个版本里下载 **Source code (zip)**；如果那个版本另外附了打包好的 zip，就下那一个
2. 解压。解出来的文件夹名带后缀（比如 `volens-0.3.0`、`volens-main`），**把它改名为 `volens`**

**Claude Code** —— 整个文件夹移到你的 skills 目录下：

- macOS / Linux：`~/.claude/skills/`
- Windows：`%USERPROFILE%\.claude\skills\`

目录不存在就自己建。放好后路径是 `…/.claude/skills/volens/`，里面应该能看到 `.claude-plugin`、`skills`、`hooks` 这几个文件夹。重启 Claude Code，敲 `claude plugin list` 确认能看到 `volens@skills-dir`，状态是 `✔ loaded`。

**Codex** —— 文件夹放在哪里都行（比如 `~/plugins/volens`），把它当成本地市场加进来：

```
codex plugin marketplace add ~/plugins/volens
codex plugin add volens@volens
```

敲 `codex plugin list` 确认状态是 `installed, enabled`。第一次开会话时同样会看到 `Hooks need review`，选 **Trust all and continue**。

**DSH** —— 压缩包给的是**技能那一半**：解压后把链接指向压缩包里的 `skills/volens`（插件那一半仍然从 npm 装，见上面的 DSH 安装步骤）。

---

## 如何使用

插件要**重启一次 Agent** 才会加载进来。重启之后，在你想纳入这套结构的项目里执行：

Claude Code 下：

```
/volens:volens
```

Codex 下：

```
$volens:volens
```

DSH 下：

```
/volens
```

>**Codex 里第一次运行要信任一次 hook。** 第一次在 Codex 里开会话时会看到 `Hooks need review`，选 **Trust all and continue**。不选的话插件装上了，但设计文档不会自动更新。

>**DSH 没有命名空间，也没有 hook 需要信任。** 技能在菜单里就是裸的 `/volens`；插件随 profile 加载，装好之后重启进程即生效。

它会先勘察已有的东西（**不会覆盖**），设定文档语言（一次性），确保指令文件的契约模块就位，种下 `docs/DECISION-LOG.md`，并确认同步机制已就位（Claude Code 和 Codex 下是 hook，DSH 下是进程内插件）。之后，每当一个设计决策改变，就往日志里**追加**一条；剩下的交给它。

---

## 许可证

本项目基于 MIT 许可证开源，详见 [LICENSE](LICENSE)。
