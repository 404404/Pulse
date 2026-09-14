# Devin

| `Provider` | Ring name | Source | Icon |
|---|---|---|---|
| `.devin` | Devin | `~/Library/Application Support/Devin/User/globalStorage/state.vscdb` | `devin` |

Service: [`../../Sources/Pulse/Providers/DevinUsageService.swift`](../../Sources/Pulse/Providers/DevinUsageService.swift).

Devin is Cognition's agent. Its Mac app is the **former Windsurf editor** — `/Applications/Devin.app` still identifies itself as `com.exafunction.windsurf`, and every key it writes is still named `windsurf.*`. That inheritance is the whole route: it is a VS Code fork, so its global state is an ordinary SQLite file, and the plan it last read from the account is one row in it.

## Verified against a live account

Yes, on 2026-09-14, against a Pro subscription on this machine. Devin.app 3.10.23 (Electron 42, `windsurf@3.10.23`). The row was read, the figures were watched moving, and both of the shapes below came off this Mac rather than out of somebody else's parser.

## The route

No credential, no network, no keychain prompt, no Full Disk Access. The file is the user's own, under their own Application Support, and is opened **read-only and in place** — the app may be running and its rollback journal belongs to that process.

```sql
SELECT value FROM ItemTable
 WHERE key LIKE 'windsurf.reactSettings.cachedPlanInfoData%'
```

The key carries the account id: `windsurf.reactSettings.cachedPlanInfoData:user-<32 hex>`. CodexBar's notes name an older key, `windsurf.settings.cachedPlanInfo`; this build has never seen it and it is read as a fallback only.

**The support directory is looked for under two names**, newest first. An Electron app's support directory follows its product name, so a Mac that ran Windsurf before the rename carries `Application Support/Windsurf` and a fresh install carries `Application Support/Devin`.

### Two shapes, because the plans differ

A paid plan reports percentages and sets the message counters to `-1`:

```json
{ "planName": "Pro", "billingStrategy": "quota",
  "dailyRemainingPercent": 98, "weeklyRemainingPercent": 99,
  "dailyResetAtUnix": 1789372800, "weeklyResetAtUnix": 1789891200,
  "hideDailyQuota": false, "hideWeeklyQuota": false,
  "remainingMessages": -1, "totalMessages": -1,
  "overageBalanceMicros": 10000000,
  "startTimestamp": 1789296110000, "endTimestamp": 1791888110000 }
```

A free one reports a message pool instead — captured out of `state.vscdb.backup`, written the moment before this account was upgraded:

```json
{ "planName": "Free", "isDevinFree": true,
  "remainingMessages": 2500, "totalMessages": 2500,
  "duration": 0, "startTimestamp": 0, "endTimestamp": 0 }
```

`-1` is how a paid plan says *not applicable*. Read as a count it draws an allowance of minus one out of minus one, so anything below zero at either end is absent rather than empty.

## What is drawn

| Field | Window | Notes |
|---|---|---|
| `dailyRemainingPercent` | `.daily`, 86,400s | Dropped entirely when `hideDailyQuota` |
| `weeklyRemainingPercent` | `.weekly`, 604,800s | Dropped entirely when `hideWeeklyQuota` |
| `remainingMessages` / `totalMessages` | `.messages` | No window, no reset, `reportsLength` false |
| `overageBalanceMicros` | — | `creditBalance` display string; micros, so 10,000,000 is ten dollars |
| `planName` | — | The card's plan line |

**Nothing here is inferred.** Devin reports both percentages itself and states both resets, so `used = 100 − remaining` and the window clock draws from a length the provider actually gave. Both resets land on a fixed 08:00 UTC boundary.

`.daily` and `.messages` are new `UsageWindow.Kind` cases and exist for the same reason `.monthly` and `.balance` do: the shortest window anyone else reports is five hours and the next is a week, and an allowance counted in messages has no period at all. Filing either under a period nobody stated would put a length on the card that no provider gave.

## The limitation: it is a launch-time snapshot

**The row is written when the app starts, not while it runs.** Measured on 2026-09-14: the account was spent down through the morning and the file sat at 100% throughout, while the web page had already moved; the app was quit and reopened at 09:20:01 and the row changed at 09:20:16, fifteen seconds later. CodexBar's own note on the Windsurf cache says the same thing and it is correct.

So the reading is stamped with **the launch**, not with now. The time comes from `logs/`, where each run creates one directory whose *name* is its start time (`20260914T092003`, in this Mac's zone). The name rather than the directory's modification date, which moves: writing inside an existing file leaves it alone, but a log file created an hour into the session bumps it, and every minute it gains is a minute the card under-reports the age of a reading that has not changed since launch.

That is what puts "as of …" on the card instead of letting a morning-old figure pass for a fresh one, and `UsageCache`'s 24-hour ceiling drops it entirely once a day has gone by without a relaunch.

A live route exists and is not built yet: `GET https://app.devin.ai/api/<org>/billing/quota/usage` with a Bearer token, and Windsurf's `GetPlanStatus` protobuf on `windsurf.com`. Both need session values that live in a **Chromium browser's localStorage** — a LevelDB, which Pulse has no reader for — rather than in the app: the four `devin_*` keys CodexBar reads were looked for in `Application Support/Devin/Local Storage/leveldb` on this Mac and are **not there**. The app authenticates through the Codeium extension's own stored session against `server.codeium.com`, a different credential for a different API.

## Two accounts in one store

More than one `cachedPlanInfoData:user-…` row can exist where two accounts have signed in on this Mac, and **nothing in the file says which is current**. The one whose `endTimestamp` is furthest out is taken — an active subscription outranks a lapsed one — and the plan name is on the card either way. `hasMultipleDevinAccounts` is in the payload but names nothing that resolves this.

## Failure copy

- `.devinAppMissing` — no support directory under either name. "Devin isn't installed."
- `.devinPlanUnread` — the store is there and holds no plan row. "Open Devin and sign in, so it can record your plan."
Both are `.neutral` to `UsageAlerts`: true until somebody does something, and not an outage to announce. The remedy for both is `openApp("Devin")`.

## First-run evidence

The app's own store, not the bundle: the plan is read from global state, so a Mac that has the app but has never run it has nothing to report, and one that ran it before the app was moved or renamed still does. Same rule in `borrowsAnExistingLogin`, so a machine that has never run Devin is never given a permanently empty ring.

## Fixtures

`Tests/PulseTests/Fixtures/devin-pro.json`, `devin-free.json`, `devin-hidden-daily.json`, and `devin-state.vscdb` — a two-row store used to pin the choice above. Written to the confirmed shapes with the account identity removed.
