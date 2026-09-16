# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.1.2

**中文**

**新功能**

- **更多 Token 消耗来源。** 新增 Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot 等本地记录读取，以及 Cursor、Trae 等导出格式。部分来源需要先导出或捕获记录；缺少 token 计数的来源不会被当作零用量。不完整计数、无法解码的记录和仅有会话日期的数据会明确标注。[来源与验证范围](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md)。
- **按模型查看详情。** 点击模型即可查看输入、输出、缓存读写、每日与每小时消耗、Agent 分布及 API 费用估算；支持排序和分页。历史图表悬停即显示日期或小时及 token 数量。费用按公开 API 价格折算，不是订阅账单。
- **更容易打开设置。** 右键浮动栏可打开设置；新增可自行设置的全局快捷键，用于打开设置和显示或隐藏浮动栏，默认不绑定按键。
- **繁體中文、日本語、한국어。** 界面和 README 新增三种语言，大数缩写使用各语言对应的万、亿单位。

**改进与修复**

- 第一方没有公布价格的模型可使用对应套餐商的公开价格；日汇总、模型详情和会话计价保持一致，Kilo CLI 使用自己的价格来源。
- Antigravity IDE 读取自身的会话存储；Devin 数据库记录不再被误标为仅来自 CLI，已匹配的数据库与 Desktop 捕获不会重复统计。
- 仅有日期的跨天汇总记录也按所选区间统计，会话列表不再将昨天的消耗带入“今天”。
- Command Code 的 rewind 保留已经发生的消耗，重复记录只统计一次，模型归属沿各自分支解析。
- Token 消耗默认统计最近一周，并记住上次选择的区间；旧统计缓存会自动重读，离线升级仍可回退使用已有价格表。
- 修复切换语言后设置侧栏变窄的问题，并补充 Agent 图标与新版界面截图。

**English**

**New**

- **More token-spend sources.** Added local-record readers for Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot and more, plus export formats from Cursor, Trae and others. Some sources require a prior export or capture; sources without token counters are not presented as zero usage. Incomplete counts, unreadable compressed records and session-date-only timing are identified. [Sources and validation coverage](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md).
- **Model details.** Open a model to inspect input, output, cache reads and writes, daily and hourly usage, contributions by agent and API cost estimates, with sortable, paged tables. Hover over history charts for the date or hour and token count. Costs use published API rates and are not a subscription bill.
- **Easier access to Settings.** Right-click the floating rail to open Settings. Optional global shortcuts open Settings or show and hide the rail; both are unassigned by default.
- **Traditional Chinese, Japanese and Korean.** Added three interface and README translations, with large-number abbreviations using each language's own myriad units.

**Changed and fixed**

- Models without a first-party price can use their plan vendor's published rate. Day, model and session amounts agree, and Kilo CLI uses its own vendor.
- Antigravity IDE reads its own conversation store. Devin's shared database is no longer labelled CLI-only, and matched database sessions and Desktop captures are counted once.
- Cross-day aggregate records respect the selected span even when only their dates are known; Today no longer includes yesterday's consumption in the session list.
- Command Code rewinds retain consumption that already occurred. Replayed records count once, and model attribution follows each reply's own branch.
- Token spend defaults to the last week and remembers the selected span. Older ledgers are reread automatically; an offline upgrade can still fall back to its existing price table.
- Fixed the Settings sidebar narrowing after a language change, and added agent icons and updated screenshots.

## 1.1.1

**中文**

**新功能**

- **Devin 成为第十八个服务商。** 从 Chromium 浏览器会话读取每日、每周额度，无需钥匙串授权；无登录凭据时读取应用保存的带日期套餐。不同账户和组织的读数保持隔离。
- **Token 消耗统计。** 汇总 Claude Code、Codex、OpenCode、Kilo CLI、Grok Build、Kimi CLI 和 Devin CLI 的本机会话，按区间、Agent、模型、项目、会话和 token 类型查看。费用按公开 API 价格折算，不是订阅账单。
- **开发者集成。** 在设置中导出 Raycast 扩展及 tmux、sketchybar、终端脚本；`Pulse --json` 增加读数来源和账户设置链接。集成仅读取缓存。[配置指南](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md)。
- **连接诊断。** 查看最近检查、读数来源、缓存和回退结果，按原因修复连接；额外账户可原位重新登录。可复制不含账户详情或凭据的诊断信息。
- **变红阈值可调。** 可选 60%–90%，默认 75%；圆环、详情条和收起的胶囊保持一致，已耗尽状态仍优先。

**改进与修复**

- Claude Code 的 warning 不再被误判为额度耗尽；登录码、取消按钮和错误信息归属正确的服务商页面，切换页面不再串写凭据。
- 修复详情卡片展开、收起时沿胶囊漂移的问题。
- 跨天会话只计入所选区间；修正日志与数据库缓存更新、模型别名计价和自定义会话标题读取。
- Devin 旧快照按实际时间标注，过期窗口和超龄快照不再显示；额度变化纳入自适应刷新，异常浏览器存储长度不再导致崩溃。

**English**

**New**

- **Devin is the eighteenth provider.** Read daily and weekly quota from your Chromium browser session without a keychain prompt. With no credential, Pulse reads the app's dated saved plan. Account and organization boundaries are preserved.
- **Token spend.** Bring together local sessions from Claude Code, Codex, OpenCode, Kilo CLI, Grok Build, Kimi CLI and Devin CLI, grouped by span, agent, model, project, session and token kind. Costs use published API rates and are not a subscription bill.
- **Developer integrations.** Export a Raycast extension and tmux, sketchybar and shell scripts from Settings. `Pulse --json` now includes reading sources and account links; integrations only read the cache. [Setup guide](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md).
- **Connection diagnostics.** Inspect checks, sources, cache use and fallback outcomes, with relevant repair actions and in-place reauthentication for added accounts. Copied diagnostics omit account details and credentials.
- **Configurable warning colour.** Choose where rings turn red, from 60% to 90% (default 75%). Rings, detail bars and the collapsed rail agree; exhausted limits still take precedence.

**Changed and fixed**

- Claude Code warnings no longer mean exhausted. Device codes, Cancel and errors stay with their provider; switching panes no longer lets login completion overwrite another provider's credential field.
- Fixed detail cards drifting along the rail as they open and close.
- Cross-midnight sessions count only their in-range work. Corrected log and database cache updates, model aliases and custom session titles.
- Devin snapshots retain their actual age; expired windows and over-age snapshots disappear. Quota changes participate in adaptive refresh, and malformed browser-storage lengths no longer crash Pulse.

## 1.1.0

- **A large balance no longer overflows the ring.** The rail shows ¥5k, ¥123k, $1.2M rather than the full figure, which did not fit and was being cut off — the exact balance is on the card and in Settings. It is always rounded **down**, so the ring never claims you have more than you do.

- **The rail no longer sits slightly too low until you touch something.** On most displays the panel is taller than the space macOS will grant it, and Pulse works out where to draw the rail from the position the window actually got. It was asking that question a moment too early — before the window was on screen, when the answer was still the position it had **requested** — so the rail was drawn about 76pt below where it belonged, and then jumped into place the first time any setting changed.

- **API balances are checked more often.** Pulse paces itself by watching this Mac — an agent writing to its transcripts, a figure that moved, you glancing at the rail — which is why it can be quick when you are working and quiet when you are not. But money spent through an API leaves no trace here, so DeepSeek and Command Code were always being left the full half hour: it waited because nothing had changed, and nothing appeared to change because it waited. Those two are now checked at least every five minutes. Everything else is unaffected, a Mac in low power or with the panel hidden still goes quiet, and a fixed interval you chose yourself still means what it says.

- **The provider list starts in alphabetical order.** It was in the order providers had been added over the months, which meant nothing to anyone reading it. If you have arranged the rail yourself, your arrangement is untouched.

- **Tell me when the credit runs low.** Providers that sell prepaid credit — DeepSeek and Command Code — get a **Warn below** figure in their own settings, and Pulse says so once when the balance falls under it. Money rather than a percentage, because these two report no allowance to take a percentage of; per provider rather than one figure, because ¥20 and $20 are not the same line. Off until you set one, like every other notification here. It is said once and not again until you top up — or until you move the line, which is a new question and gets a new answer.

- **Notifications about a prepaid balance say less, and say it correctly.** Credit that is bought does not reset and cannot be declared spent by arithmetic, so changing what the ring measures against no longer announces a reset, and a balance reaching 100% of a figure **you** set no longer claims the provider says you are out. Only the provider saying so does that.

- **DeepSeek is the seventeenth provider**, and the first one Pulse carries that reports no allowance at all — `GET /user/balance` says how much prepaid credit is left and nothing else. There is no quota, no window and no spend history to read, so the ring needs a denominator from somewhere and you choose which in DeepSeek's settings. **Since top-up** is the default and needs nothing from you: Pulse remembers the highest balance it has watched, and a balance that goes up can only be a top-up, so the ring starts again from full when you add credit. **Balance only** draws no ring at all and puts the money itself on the rail. **My budget** measures against a figure you type. The first two days on "since top-up" will read low — Pulse can only measure from the moment it started watching, and the card says which date that is.

- **智谱's row is now called "Zhipu".** The rail and the settings list are otherwise all Latin script, and one row in Chinese characters read as a different kind of thing rather than as another shop. The company, the storefront and the key it takes are unchanged — this is the name on the row, nothing else. Its sibling stays **z.ai**, which is that company's own spelling.

## 1.0.9

- **Command Code is the sixteenth provider.** It bills a credit balance in dollars rather than a token allowance, so the rings are money: the rolling 5-hour and weekly limits, your organisation's spend limits, and how much of this month's plan is gone. That last one is marked **estimated** on the card, and it is the one thing here Pulse has to infer — Command Code reports what is **left** of a plan's monthly credit but never what the plan grants, which is published on its pricing page instead. A plan Pulse cannot size shows no monthly row at all rather than a reassuring zero. Sign in by pasting a key, or let Pulse borrow the one `cmd auth login` already saved.

- **The panel can follow you between displays.** Switch on "Follow the active display" and the rail moves to whichever screen your pointer is on, keeping the same corner and the same distance down it. There is still only one rail — it is carried across, not copied onto every monitor — and it stays where you last dragged it if you leave the setting off, which is how it ships. "Active" means the display the pointer is on and nothing else: it does not chase other apps' windows around, and it asks for no extra permission to work out where you are.

## 1.0.8

- **The interface follows your Mac's language.** Pulse now declares that it speaks Chinese, which it always did — the translations shipped, macOS just was not told they existed, so a Mac set to 简体中文 got an English app. If that was you, this update switches over on its own; if you preferred it in English, Settings › Language still overrides. The Chinese copy has been rewritten throughout while we were in there.

- **Antigravity can show its two allowances as two rings.** The plan carries one budget for Gemini and a separate one for Claude and GPT, and until now a single ring could only follow whichever was busier — the other went unmentioned unless you hovered. Switch on "A ring for each model group" in Antigravity's settings and each gets its own ring, both under the Antigravity icon, both refreshing the one login. Off by default: an extra ring takes room on the rail, and most people want the one number.

- **智谱 and z.ai get a usage history**, read from the same statistics the console draws its own charts from. Unlike the history Pulse builds for Claude Code and Codex — which it works out by reading session files on this Mac — this one comes from the account, so it covers every machine you use it on. It counts tokens only: the figures behind it cannot be turned into money, and the card says so rather than printing a confident zero.

- **A second limit on the ring.** A thinner ring inside the first shows the next-fullest limit *of the same kind* — the 5-hour beside the weekly it belongs with — so both are readable without hovering. Where a provider splits its allowance by model, the two arcs come from the same allowance wherever it has a second limit to show: pairing one model's weekly with another's 5-hour would put two unrelated budgets on one mark. Off by default and switched on in Settings; the ring is the thing you read without stopping, and two arcs is twice as much to take in. Where a provider reports only one limit nothing is added.

- **The panel no longer slides out from under you as you pick it up.** On a display where the panel is taller than the space under the menu bar — which is most laptops — macOS quietly refuses the position Pulse asks for, and Pulse was then drawing the rail relative to a position the window never had. It jumped about one ring's worth on the first frame of a drag. It tracks the pointer exactly now.

- **The two GLM Coding Plan rows are now named for the shops** — **z.ai** and **智谱**. They were "Z.ai" and "GLM Coding Plan", which was a trap: both shops sell the plan under that same name, so anyone on the international plan picked the row named after their product and had their key sent to the mainland service, which of course refused it.
- **A refused key now says the key was refused.** These services answer with an ordinary HTTP 200 and put the verdict inside, and Pulse only recognised the English wording and two of the numbers — so the most common mistake of all, a key from the other one of the two shops, came out as "the service returned an error" and sent people looking for an outage that was not happening.

## 1.0.7

- **Pulse can tell you, instead of waiting to be looked at.** Three switches in Settings, all off until you turn them on. **Warn at** posts a notification when a limit passes 75, 80, 90 or 95% — whichever you pick — and again when the provider says it is spent. **When a limit comes back** says so once the window you were warned about has turned over, which is the moment you can start again. **When a reading stops arriving** is the one that is about Pulse rather than about usage: a failed check falls back to the last good figures, which is the right thing to show and also the reason the fault is invisible — the panel goes on displaying perfectly plausible numbers with only a "last read" time to give it away. It waits for three failures in a row and then says it once, with the same sentence the card would have shown you.
- **It says each thing once.** A limit already past the line when you switch this on is mentioned straight away — silence followed by a wall is not restraint — and then never again until it resets or gets worse. "Spent" is the provider's own word, never a rounding of ours. A reset is announced only on unambiguous evidence, so a rolling weekly allowance sliding down a few points is not mistaken for a window turning over. And a provider you have never set up, or an app that simply is not running, is not a failure to be reminded of on a timer.
- **Antigravity reads from the IDE too**, not only the desktop app. If Antigravity IDE is the one you have open, its ring said “Open Antigravity to see its usage” while the figures were sitting there for the asking. Both report the same thing — the Gemini and the Claude-and-GPT group, weekly and five-hour each.
- **Antigravity could pick the wrong helper and give up.** It runs more than one of these, only one of them answers, and Pulse asked the first it found and stopped.
- **Reorder the rail by dragging.** The arrows are still there — they are the precise way to move one place, and the only way that works from the keyboard — but with fifteen providers, moving the bottom one to the top was fourteen clicks. There is a Reset order button under the list for when a drag goes somewhere you didn't mean.
- **Volcengine**, bringing it to fifteen. The Ark Coding Plan and Agent Plan, personal and team, each with its five-hour, weekly and monthly windows. Two ways in: `arkcli`, using the login it already saved so there is nothing to paste, or a Volcengine access key pair for anyone who has keys but doesn't run the CLI here. With both set up it prefers the keys — the CLI carries a sign-in that can belong to a different account, and quietly showing the wrong account's limits is worse than either answer.
- **`Pulse --json`**, so the figures can go somewhere other than the panel — a tmux status line, sketchybar, Raycast, a shell prompt. It prints what the app last read rather than fetching, so polling it every second costs nothing and asks no provider anything; every account says when its figures were taken and how old they are. Nothing in the output is translated, so a script parsing it does not break when you change the interface language.
- **Settings has a search field**, since the sidebar now lists fifteen providers plus whatever accounts you have added. It matches the provider's name as well as your own label, so a second Claude subscription you called "work" is still found by typing Claude.
- **The Settings window opens bigger.** It was sized when the sidebar held four rows and had got to the point of appearing already scrolled in both columns.
- Notifications come with the standard notification sound. Silence them, or change anything else about how they arrive, in System Settings › Notifications › Pulse — the same place as every other app.

## 1.0.6

- **Grok**, read from the login Grok Build's CLI already stores — nothing to paste. One thing worth knowing before the ring confuses you: since June 2026 a paid Grok plan spends **one weekly pool across every Grok product** — the web chat, Imagine, voice, the API and the CLI alike — so this is what the account has spent this week, not what the CLI has. That is why it is called Grok rather than Grok Build.
- **Grok Bot**, which is a different limit despite the name. It comes with a Cursor plan rather than a SuperGrok one, so it is read with the login the Cursor editor already stores and carries the xAI mark to tell the two apart on the rail. It appears by itself only if the standalone app is installed; otherwise switch it on in Settings.
- **A second account of either.** Grok signs in with a device code, Grok Bot through Cursor's own sign-in page. Both ask for the narrowest access that can read a limit — never for permission to read or write your conversations.
- A card could print a window length the provider never reported. Some limits carry a length that only exists to sort the rows — a rolling week, a billing cycle — and when there was no reset time to show, that length was printed as though it were one.
- A provider with a single route named the wrong one in Settings. Every such provider but Cursor was described as "Antigravity's language server", about an app it had nothing to do with.

## 1.0.5

- **Claude Code read through the Claude desktop app.** If you work in the desktop app rather than a terminal, Pulse had no way to see your limits: the desktop app hands the CLI a token through its own environment and renews it itself, so the login Pulse was reading went stale and never came back, and it never renders a status line either. Pulse can now read the session the desktop app is signed in with — a new "Desktop app" choice under Read usage from, and the route `Automatic` falls back to once you have allowed it. It asks for the keychain once, at launch, so there is nothing to go and find in Settings.
- **The new route says why it can't answer**, rather than leaving the last reading in place with nothing but its "Last read" time to give it away — which is what makes a refresh look as though it did nothing. It says whether the desktop app is signed out, or whether it was the keychain that was refused.
- **A reading could go backwards.** A newer figure already on file could be replaced on screen by an older one that had just arrived, and a refresh that had been given up on could still overwrite the one that replaced it — including, for an added account, the renewed login itself.
- **GitHub Copilot no longer shows a red ring for paid overage.** Going past the included allowance with overage permitted is not being blocked, and it was being drawn as though it were.
- **Codex no longer marks the wrong model group as spent.** A group reporting "limit reached" could put the mark on another group's window entirely.
- Removing your only added account no longer leaves the rail empty.

## 1.0.4

- **GitHub Copilot**, bringing it to twelve. Signs in with a device code, so there is no token to paste — Pulse asks GitHub for permission to read your profile and nothing else, and never for access to your repositories. Shows the completions, chat and premium-request allowances your plan actually has.
- **Whether a limit will last.** A switch in Settings puts one line under each limit on the card: whether it is on course to outlast its window, and roughly when it runs out if it isn't. Off by default, and it stays quiet when the figures can't carry it — the time only appears when it falls before the reset, and it is rounded, because usage comes in bursts and a figure to the minute would be made up.
- **Show what's left instead of what's spent.** Another switch, which turns the figure and the ring over together so a limit reads "88% left" rather than "12% used". The colour still means how close you are, so a nearly empty ring is still red.
- **Claude Code's card names the plan** — "Max 5x", "Pro", "Team" — as every other provider's already did. The multiplier is part of it, since a Max 5x and a Max 20x are different products.
- **The panel could quietly stop refreshing** after running a long time, and only come back when you next started Claude Code in a terminal. It notices when its own readings have gone stale and asks again, recovers from a fetch that never returned, and refreshes when the Mac wakes as well as when the display does.

## 1.0.3

- **The panel can go on a second display.** Drag it across; it remembers which screen you left it on, and comes home if that screen is unplugged.
- **Four more providers**: the GLM Coding Plan and MiniMax, each with a separate entry for the international and the mainland service, since they are separate accounts with separate keys.
- **A second arc can show how far through the window the clock is**, so "80% used" can be read against how much of the window is left. Off by default, in Settings.
- **The figure can sit above the ring** instead of below it. Also in Settings.
- A provider that needs an API key is no longer switched on by itself — it waits in Settings rather than taking a place on the rail to ask for a key.
- One that has no key says so, instead of saying "Reading…" for ever.
- Claude Code no longer shows a limit that has already reset. If its saved login has expired and no session has run for a while, the stale window is dropped rather than shown with an old reset time.
- The update window now shows the release notes itself, rather than loading the GitHub page inside it.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription and watch both at once, each with its own ring.
- **Cursor**, reported as the two pools its own account page shows.
- **Ollama Cloud**, from PcOffeeP's pull request — with the session read out of your browser rather than copied by hand.
- **The rail can dock along the top of the screen**, above the menu bar.
- **A colour of your own for any ring**, and the gap between rings is now adjustable.
- **Percentages can be switched off** on either rail.
- The rail opens with the last reading instead of sitting blank.
- The activity mark no longer keeps turning for a minute after a turn has ended.
- The API-key field in Settings lets go when you click away from it.
- A limit you have used never reads as 0% any more.
- Quitting Codex no longer takes Pulse down with it.
- A new app icon, drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go** and **Kimi Code**, bringing it to five agents.
- **Put the rings in your own order**, in Settings.
- **A refresh button on every provider's pane**, with the age of the reading beside it.
- A new install starts with the agents you actually have, rather than five rings that say "not configured".
- The panel can be dragged by any part of the capsule, not only by its rings.
- Clicking a ring refreshes the one you clicked, whatever order the rail is in.
- The detail card no longer truncates itself at Small or sit half empty at Large.

## 1.0.0

- The first release. A floating rail of rings against the edge of the screen, one per coding agent, showing how much of each limit is left.
