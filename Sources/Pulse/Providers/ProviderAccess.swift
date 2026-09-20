import Foundation

extension Provider {
    /// Shown before enabling a provider, both in the chooser and in Settings.
    /// Pure copy: drawing this must never inspect the credentials it describes.
    var monitoringAccessDescription: String {
        switch self {
        case .claudeCode:
            .localized("Reads Claude Code's saved login from Keychain or its credentials file. May ask for Keychain access, including Claude Desktop's cookie storage.")
        case .codex:
            .localized("Can use Codex's saved login or a ChatGPT account connected directly in Pulse. Pulse does not request Keychain access.")
        case .antigravity:
            .localized("Reads the running editor's local language server and connection token. No Keychain prompt.")
        case .cursor, .grokBot:
            .localized("Can use Cursor's local editor login or a Cursor account connected directly in Pulse. No Keychain prompt.")
        case .grok:
            .localized("Can use Grok CLI's saved login or a Grok account connected directly in Pulse. No Keychain prompt.")
        case .openCodeGo:
            .localized("Uses a key entered in Settings, or reads OpenCode's auth.json. No Keychain prompt.")
        case .glmCoding:
            .localized("Uses a key entered in Settings, or reads the saved GLM key files. No Keychain prompt.")
        case .commandCode:
            .localized("Uses a key entered in Settings, or reads ~/.commandcode/auth.json. No Keychain prompt.")
        case .devin:
            .localized("Reads Devin's web login from local Chromium browsers without a prompt; may also read the desktop app's saved plan.")
        case .volcengine:
            .localized("Runs arkcli with its saved login, or uses access keys entered in Settings. Pulse does not request Keychain access.")
        case .ollamaCloud, .xiaomiMiMo:
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        case .copilot:
            .localized("Uses the GitHub login you connect in Settings. No Keychain prompt.")
        case .kimiCode, .zai, .minimax, .minimaxCN, .deepSeek:
            .localized("Uses only the API key you enter in Settings. No Keychain prompt.")
        }
    }
}
