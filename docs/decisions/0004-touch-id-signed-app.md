# 0004 Touch ID through a signed Xcode app, Keychain-held vault key

Date: 3 October 2026. Status: accepted. Record type: lite (Personal). Partly supersedes 0002.

- **Decision.** Add a signed macOS app project in `App/` (Nino's developer team, Keychain Sharing capability, App Sandbox off) that wraps the package's `DevPasswordUI`. With Touch ID switched on, the vault key is stored in the data protection Keychain: this device only, never synchronised, available only while the Mac is unlocked, released only by a biometric match against the fingers enrolled now (`biometryCurrentSet`). The passphrase and recovery code always still work. `swift run` stays as an unsigned build without Touch ID.
- **Why.** Nino asked for Touch ID. Spec F10 and section 5 call for exactly this design. Holding the key in app memory while locked was rejected: it breaks "release working keys on lock".
- **Principle affected.** None of the gates. Sandbox stays off (0002) so both builds share one vault file.
- **Reversal point.** Moving to the App Group container in Stage 2, which needs the sandbox and a scripted, backed-up migration (N3).

Consequences: a person who can unlock the Mac and has an enrolled finger can open the vault. That is the same trust boundary as the spec's threat model. Not unit-tested: Keychain access control cannot run in `swift test`. Verified by hand only (see ENGINEERING_STATE.md).
