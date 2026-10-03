# 0002 Stage 1 Mac app runs from the Swift package, passphrase unlock only

Date: 3 October 2026. Status: accepted, partly superseded by 0004 (Touch ID). Record type: lite (Personal).

- **Decision.** For Stage 1 the Mac app is an executable target in the Swift package, run from Xcode or `swift run`. It is unsigned for distribution, unsandboxed, and unlocks with the master passphrase or recovery code only. Touch ID unlock, the App Group container, Keychain storage of the vault key, CloudKit and the AutoFill extension arrive with a signed Xcode app target in Stage 0 and Stage 2.
- **Why.** Stage 0 has not proved signing, Keychain access control or Touch ID on Nino's keyboard. Writing that code before the proof would add code nobody can verify. The package gives a working local vault now with nothing to configure.
- **Principle affected.** None of the gates. Departs from spec v1.1 F10 (biometric access) and section 4 (App Group container) for Stage 1 only.
- **Reversal point.** Stage 0 complete. Then add the Xcode app target and move the vault into the App Group container with a scripted, backed-up migration (N3).

Consequences: the vault lives at `~/Library/Application Support/devPassword/vault.sqlite`. Without a sandbox, any process running as Nino can read the file. It holds ciphertext only, so this exposes record counts and sizes, not contents.
