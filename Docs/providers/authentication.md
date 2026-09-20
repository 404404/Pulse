# Authentication and credentials

Pulse is not an official integration of any of these products. Where it signs in, it drives a **public client the product already ships** (a CLI, an editor plugin, a login page). Settings says so before anyone starts: the consent page names that product, not Pulse, and the provider can change or withdraw the client.

Current code: [`OAuthLogin.swift`](../../Sources/Pulse/Auth/OAuthLogin.swift), [`LoopbackCallback.swift`](../../Sources/Pulse/Auth/LoopbackCallback.swift), [`GitHubDeviceLogin.swift`](../../Sources/Pulse/Auth/GitHubDeviceLogin.swift), [`CursorWebLogin.swift`](../../Sources/Pulse/Auth/CursorWebLogin.swift), [`AccountCredentials.swift`](../../Sources/Pulse/Auth/AccountCredentials.swift), [`APIKeyStore.swift`](../../Sources/Pulse/Auth/APIKeyStore.swift), [`LocalSecrets.swift`](../../Sources/Pulse/Auth/LocalSecrets.swift), [`BrowserCookies.swift`](../../Sources/Pulse/Auth/BrowserCookies.swift), [`ClaudeDesktopSession.swift`](../../Sources/Pulse/Providers/ClaudeDesktopSession.swift).

This is not a catalogue of secrets. Client ids below are public (they ship in every copy of those CLIs and plugins). Do not copy refresh tokens, cookies, or `accounts.dat` / `keys.dat` into issues.

## Three kinds of secret, three stores

| What | Where | Who renews it |
|---|---|---|
| Pasted API key or Ollama session cookie | `keys.dat` (`APIKeyStore`) | Nobody. User pastes or re-reads the browser. |
| Copilot GitHub token | `keys.dat` as well (`keepsOwnCredential`) | Sign in again. Device tokens here are not the CLI refresh path. |
| Primary Auth credentials (Codex, Grok, Cursor, Grok Bot) | `accounts.dat` (`AccountCredentialStore`) | Selected in Provider Management. Auth reads only this store and never falls back to Local. |
| Extra-account logins (Claude Code, Codex, Grok, Cursor, Grok Bot) | `accounts.dat` (`AccountCredentialStore`) | `UsageStore.fetchManaged` renews Claude Code, Codex, and Grok through `OAuthLogin.refresh`; Cursor and Grok Bot keep any returned refresh token for compatibility but have no verified browser-login refresh route. |

Both files are AES-GCM boxes in Pulse’s Application Support folder, owner-only, key derived from this Mac rather than stored. `LocalSecrets` is shared so there is one copy of the crypto; a different derived key per purpose means a box from one store cannot be opened by the other.

A file that exists but will not decode is **not** empty. Treating it as empty meant saving one provider’s key silently threw away every other provider’s — and said it had succeeded. Saving refuses instead.

Pulse does **not** keep a Keychain item of its own for these. Chromium / Claude Desktop / Safari reads may *prompt* for someone else’s Safe Storage key; that is borrowing, not Pulse storing a secret there.

**Do not say “only OpenCode Go holds a credential” or “Pulse never holds a credential”.** Primary Claude Code, Codex, Cursor, Grok, Grok Bot, and Antigravity borrow another tool’s login. Pulse *does* hold pasted keys, Ollama sessions, Copilot’s token, and every extra-account login.

## Why sign in at all, rather than copy the CLI

Measured: a Codex access token lives on the order of 240 hours; a Claude Code one about five; a Grok CLI token about six hours. Copying the credential would leave the account you are *not* currently using dead within an afternoon. The only way to renew a copied token is the refresh token the CLI is also relying on — which, if the provider rotates it, signs the user out of their own CLI.

Claude Code, Codex, and Grok managed logins have their own refresh token and do not read or write what the CLI stored. Cursor and Grok Bot managed logins are also isolated in `accounts.dat`, but Pulse does not guess a refresh request for either browser-login flow. That separation is the reason for signing in.

`fetchManaged` renews OAuth-managed credentials when the access token is within a minute of expiry. Cursor and Grok Bot instead report `.signedOut` when their browser-login token is no longer usable. A renewal that fails reports `.signedOut`, not a network error: the remedy is the same and the user can act on it.

## Extra accounts: who can have them

[`Provider.supportsMultipleAccounts`](../../Sources/Pulse/Usage/MonitoredAccount.swift) is **`.claudeCode`, `.codex`, `.grok`, `.cursor`, `.grokBot`**. Cursor is now supported through its separate browser-login target.

- Claude Code / Codex / Grok: `OAuthLogin` public CLI clients.
- Cursor: `CursorWebLogin` with `redirectTarget=cli`, stored in `AccountCredentialStore`.
- Grok Bot: **not OAuth** — [`CursorWebLogin`](../../Sources/Pulse/Auth/CursorWebLogin.swift) with `redirectTarget=sand`.

`AccountKey` for the first account is the provider’s raw value (`claudeCode`, not `claudeCode#…`). Added accounts get a slot generated once and never reused, so removing one and adding another cannot inherit settings.

## Local application login versus Pulse-managed login

The first account for each provider starts as the local application account. Provider Management lets Codex, Grok, Cursor, and Grok Bot switch that primary slot explicitly between Local and Auth. Local reads the provider-owned login and Pulse does not sign it out, refresh it, or write back to it. Auth reads only the Pulse-managed credential in `accounts.dat`; it never falls back to Local. For Codex, Grok, and Cursor the Local files are `~/.codex/auth.json`, `~/.grok/auth.json`, and Cursor’s `state.vscdb`.

A Pulse-managed credential can back the primary Auth slot or an added account created by the Connect action in Settings. Its access and refresh credentials are stored only in encrypted `accounts.dat` through `AccountCredentialStore`; it never copies or replaces the local application credential. Disconnecting clears only the selected Pulse-managed entry.

The same provider can therefore have one Local primary account, an Auth primary account, and multiple Pulse-managed extra accounts. They remain separate credential sources and `AccountKey` values and are fetched only through the selected route.

## OAuth: Claude Code, Codex, Grok

Pulse cannot register an OAuth application with these providers. `OAuthLogin.Configuration.of` is read from the installed CLI / the provider’s discovery document rather than remembered. A flow with one parameter wrong fails in a way that looks like the user’s fault.

### Claude Code — redirect, any loopback port

- Authorize `https://claude.com/cai/oauth/authorize`, token `https://platform.claude.com/v1/oauth/token`.
- Public client id from the CLI.
- Scopes: **`user:profile` only**. The CLI also asks for inference and session scopes, which would let Pulse **spend** the plan it is only supposed to report on.
- Token endpoint takes **JSON**. Exchange **carries `state`**.
- Extra authorize item `code=true`.
- `fixedPort` is nil: any loopback port, path `/callback`.
- No device flow. Loopback code in `LoopbackCallback` exists for this provider.

### Codex — browser authorization code with PKCE
The normal **Connect ChatGPT account** action uses the browser authorization-code flow from the Codex CLI, not a pasted device code. Pulse starts the loopback listener before opening the browser, generates a verifier and S256 challenge, checks the returned state, and exchanges the code into credentials stored only in `accounts.dat`.

- Authorize and token endpoints are OpenAI’s public Codex client endpoints.
- The registered redirect is `http://localhost:1455/auth/callback`; if 1455 is occupied, Pulse tries the CLI-compatible fallback 1457 and uses the port that actually bound.
- The published scopes are retained: `openid profile email offline_access api.connectors.read api.connectors.invoke`. The authorize request also includes `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, and `originator=codex_cli_rs`.
- The token exchange is form encoded and follows the Codex client contract; it does not add Anthropic’s state field.

The existing OpenAI device flow is preserved as a deliberate fallback. If browser authorization fails, Settings offers **Use device-code login instead**. It remains a code-and-poll flow with no local callback. Auth mode never falls back to the local `~/.codex/auth.json` login, and Local mode never reads the Pulse-managed account.

The Codex CLI is open source. Read its current login client rather than inferring OAuth parameters from a binary; the loopback shape and fallback port are taken from [`codex-rs/login/src/server.rs`](https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs).

### Grok — RFC 8628 device code

Parameters from `auth.x.ai/.well-known/openid-configuration`, not from CLI strings. Client id is the CLI’s and appears in `~/.grok/auth.json` as `oidc_client_id` after `grok login`.

Scopes: `openid email offline_access grok-cli:access`.

- `grok-cli:access` is what the CLI proxy is gated on.
- `email` stops two Grok accounts both being offered as “Grok”.
- Dropped from the CLI’s set: `profile`, `api:access`, conversation and workspace scopes (the last two would let Pulse read and write chats).
- **`billing:read` looks like the right scope and is refused.** Measured: the device endpoint answers `invalid_scope — Scope 'billing:read' is not allowed for this client`. Do not document it as missing-and-needed.
- That the remaining four are *enough* was settled by performing the sign-in (an added account reads both endpoints), not by reasoning about it. This is not a claim that a later change of server policy will keep working.

**Grok’s device flow is the specification’s; Codex’s is not.** They share a name and nothing else (`OAuthLogin.DeviceFlow`). Writing either as a special case of the other gives a parser that reads neither reliably.

On the standard flow a refusal and a “still waiting” arrive with the **same HTTP 400**; only the body’s `error` tells them apart. Measured against xAI with an unapproved code: `400 {"error":"authorization_pending"}`. `slow_down` lengthens the interval by the five seconds the specification names. The poll makes its own request rather than calling `post`, so “not yet” never travels as a `Failure` the UI would show every few seconds.

**xAI does send `verification_uri_complete`, and it is used.** Pre-filling is the device-code phishing attack only when the link comes from somebody else. Here Pulse asked for the code and opens the page itself. GitHub deliberately sends none (see Copilot). Use the field where the service offers it; never construct it where it does not. Still copy the code for a page that turns out not to fill itself in.

The redirect flow was not chosen for Grok. Cloudflare answers 403 to anything but a browser on `auth.x.ai/oauth2/authorize`, so whether the client accepts an arbitrary loopback port cannot be probed without performing a sign-in. Loopback fields are still filled from the CLI’s `http://127.0.0.1:<port>/callback` in case that changes.

### LoopbackCallback (Claude Code)

Binding is a **separate step** from waiting: the port is only known once the listener is ready, and the redirect address goes into the authorize request before the browser opens. Folding the two together produced a redirect to `localhost:0`.

Codex’s client uses `http://localhost:1455/auth/callback` and a CLI-compatible fallback port. Claude Code accepts any loopback port.

`state` is checked in the callback, handed over at `start(expecting:)` rather than at `awaitCode`: the browser can beat that call.

**Cancelling has to unwind the wait, not merely mark it cancelled.** A bare `CheckedContinuation` ignores cancellation; a 300-second timeout in an unstructured `Task` does not inherit it. Pressing Cancel left the attempt running, and five minutes later the abandoned cleanup wrote “the browser didn’t come back” over a second sign-in. `withTaskCancellationHandler` settles it. `OAuthLogin.post` lets `CancellationError` through instead of reporting the service failing to answer.

**A busy port does not fail an `NWListener`, it parks it in `.waiting`.** Only `.failed` / `.cancelled` were handled, so a fixed-port sign-in would hang with a dead button. The fixed-port path is covered by the Codex client, while Claude binds `.any`.

Query values are read encoded and decoded here: a query string spells a space `+` and `URLComponents` will not undo that, while decoding before substitution turns a literal plus (`%2B`) into a space.

## GitHub Copilot — device code, `read:user` only

[`GitHubDeviceLogin`](../../Sources/Pulse/Auth/GitHubDeviceLogin.swift). This is a **security decision**, not a missing paste field.

The Copilot usage endpoint accepts any GitHub OAuth token — the one `gh` already holds works (verified historically). That token carries `repo` and `workflow`: the run of someone’s source code, handed over to draw a percentage. The device flow asks for `read:user` and nothing else.

Pulse cannot register an OAuth app with GitHub, so it drives the VS Code Copilot plugin’s public client. Consent page names the editor.

**The verification link must not carry the code.** RFC 8628 has `verification_uri_complete`; GitHub deliberately does not send one. Its page: *“Never use a code sent by someone else.”* Pre-filling **is** the device-code phishing attack. A `user_code` query parameter was tried and is ignored; it is not kept. The code goes on the clipboard instead. If a service ever offers `verification_uri_complete`, that is the service’s decision to make (Grok does; GitHub does not).

GitHub’s codes last fifteen minutes; polling patience is 900 seconds so Pulse does not report failure while the code on screen is still good.

The token is stored in `keys.dat` (`keepsOwnCredential`), not `accounts.dat`.

## Cursor managed login

Cursor has two credential sources:

- Local Cursor reads `cursorAuth/accessToken` from the editor’s `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` and builds the `WorkosCursorSessionToken` cookie.
- A Pulse-managed Cursor account opens `https://cursor.com/loginDeepControl` with `redirectTarget=cli`, polls `https://api2.cursor.sh/auth/poll`, and builds the same cookie from the returned JWT. It does not require Cursor or `state.vscdb` to exist.

The poll treats 404 as pending, a 403 with an explicit error as provider refusal, and transient failures as retryable. It accepts both camelCase and snake_case token fields, requires a JWT `exp`, and uses `userId`, `authId`, or `sub` only when present.

The reference client exposes `exchange_user_api_key`, but the repository investigation did not establish that endpoint as a browser-login refresh contract. Pulse therefore saves a returned refresh token for future compatibility but does not call it. When the JWT expires, the managed account reports reauthentication required and the user reconnects it.

## Grok Bot extras — Cursor web login, not OAuth

Cursor publishes no authorize/token pair for a third party. Calling this OAuth sets the wrong expectations.

1. Browser: `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=sand`.
2. Poll: `https://api2.cursor.sh/auth/poll?uuid=…&verifier=…`. **404 means “not yet”, not “wrong address”.** Only a 403 carrying `error` ends the attempt.

Proof key is PKCE’s algorithm. The verifier is 32 random bytes **base64url-encoded**; the challenge is the base64url of the SHA-256 of **that encoded string**, not of the raw bytes. Read out of `Grok Bot.app` (`Contents/Resources/app.asar`), not inferred.

Tokens last about **sixty days** (measured from `exp` on one Mac). No refresh endpoint exists in Cursor’s client. When one ages out, `fetchManaged` reports `.signedOut` and the remedy is to sign in again.

`OAuthLogin.Configuration.of(.grokBot)` is nil. `fetchManaged` still calls `OAuthLogin.refresh` when the token is no longer fresh; that fails closed into `.signedOut`, which is the honest path.

Pulse does **not** read `~/Library/Application Support/Grok Bot/sand-secrets.json`. That file was identified during investigation; the extra-account token Pulse obtained itself is what is stored.

## Browser cookies — Ollama Cloud only

[`BrowserCookies.swift`](../../Sources/Pulse/Auth/BrowserCookies.swift) exists because Ollama publishes no quota API. Setup, host filter, and parser rules: [`../ollama-cloud.md`](../ollama-cloud.md).

**User-browser cookie reading is not how Claude, Cursor, or anyone else authenticates.** Claude Desktop borrows the *desktop app’s* Chromium cookie store (`sessionKey` / `sessionKeyV3` on `claude.ai`) via [`ClaudeDesktopSession`](../../Sources/Pulse/Providers/ClaudeDesktopSession.swift) — a different path, gated on a Keychain grant for `Claude Safe Storage`. Cursor **builds** a `WorkosCursorSessionToken` from the editor’s SQLite token; it does not open Safari or Chrome.

Failure class this feature keeps rediscovering: **a wrong lookup reads as an empty one**, then the next browser is tried, and Settings reports a session from a browser the user never signed in at.

- Safari host match must not be a suffix (`notollama.com`).
- Duplicate cookie names are normal (host-only + domain); throwing discarded the whole browser.
- Edge’s keychain service is `Microsoft Edge Safe Storage`, not a name derived from the display string “Edge”.
- Default browser first, even if it prompts. A cheap browser with a months-stale session is worse than a prompt.
- Naming a browser in Settings means *only* that one is opened.

Parsers were driven against data built on purpose (synthetic `binarycookies`, Chromium values encrypted with the documented scheme). File discovery on a real machine is not claimed as verified here.

## Claude Desktop Keychain grant

There is no way to ask the Keychain for an item silently (`SecKeychainSetUserInteractionAllowed` is deprecated with no replacement). [`AppDelegate`](../../Sources/Pulse/App/AppDelegate.swift) asks for `Claude Safe Storage` once at launch, fenced three ways: a desktop cookie store exists, Claude Code is enabled with source Automatic or Desktop App, and **once** — a refusal is a decision.

`.automatic` then reads the remembered grant (`usageIfAlreadyPermitted`) rather than raising the dialog. Pinning `.desktopApp` calls `usage` directly, so a first-time pin can prompt there.

A grant that stops working is asked about again rather than treated as asked-and-refused: the Keychain ties the allowance to the code signature, and Pulse is ad-hoc signed, so every update is a different app as far as the ACL is concerned.

The desktop session rides its own ephemeral `URLSession` so a `Set-Cookie` on those replies is never carried onto Pulse’s other requests. The session belongs to the desktop app and is borrowed for one call.

## What “not public API” means here

Most usage endpoints Pulse calls are **undocumented account or editor routes**. They can change without notice. A few paths are documented by the vendor (Claude Code’s status-line hook; Kimi’s usage URL as the service comments it; GitHub’s device-code *login*, not the Copilot quota JSON). None of that makes Pulse an official integration, and none of it is a promise the JSON will stay stable.

Do not write “official API” unless the vendor documents that exact usage contract. Do not write “the only credential is the provider’s” when Pulse also stores keys, sessions, Copilot tokens, and extra-account logins.
