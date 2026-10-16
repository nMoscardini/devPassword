# 0009 Site logos fetched from each site, on request only

Date: 15 October 2026. Status: accepted by Nino, build not started. Record type: lite (Personal). First outbound network use by devPassword.

- **Decision.** devPassword shows each login's site logo, like Apple Passwords and LastPass. Logos are fetched directly from each site, only when Nino clicks "Fetch Logos". No logo service.
- **Why.** Nino wants logos; one key icon for 1,000 logins is hard to scan. A logo service (Google, DuckDuckGo) would learn his whole site list in one place. Fetching from each site tells each site only that its icon was fetched; his network provider sees the domain names looked up, nothing more.
- **Rules.**
  - Only on request: Settings > Logos, with a plain warning (moved off the Vault menu 16 October), never in the background, never at unlock. Single records: click the icon.
  - HTTPS only. Two fixed paths per host: `/apple-touch-icon.png`, then `/favicon.ico`. No HTML is fetched or parsed.
  - Ephemeral session: no cookies, no cache, no credentials. 5 second timeout, 200 KB limit, redirects only within the same host.
  - IP addresses, local names (no dot, .local, .lan, .home) and hosts with no icon get a coloured letter tile instead. Never fetched.
  - Each image is decoded once and redrawn to a 64 by 64 PNG before saving. The site's original bytes are never stored.
  - Cache: one file in Application Support, sealed under the vault key (the host list is personal). Readable only while unlocked. Amended 16 October (Nino): the sealed cache goes into backups (digest in the manifest, checked on open, restored beside the vault) so the iPhone shows logos without fetching; it will sync with the vault (0008). The iPhone app never fetches.
  - Nothing else in devPassword uses the network. No record content, username or password ever leaves the Mac by this path.
- **Reversal point.** Any sign that fetching leaks more than the host name, or a logo source that needs no network.
