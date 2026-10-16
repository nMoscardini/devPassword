# Clean-up plan (Monday 19 October 2026)

Goal: well under 1,000 entries, without losing a login that still matters. Agreed with Nino 15 October.

## Where deleting happens

- Apple logins: delete in Passwords (Recently Deleted keeps them 30 days). Deleting them in devPassword is pointless: the next import brings them back. devPassword finds them and lists them.
- devPassword-only records (mSecure, LastPass notes): delete in devPassword. They go to Deleted first.
- Logins Apple no longer has stay in devPassword as the last known copy. Add a "Removed from Apple" view and a "Move to Deleted" button so Nino chooses when they go.

## One Clean-up screen, rules in order

Each rule shows a list with a tick box per item. Nothing is deleted automatically. Snapshot before any bulk change (N3).

1. Exact duplicates: mSecure copies of Apple logins (same site, username, password). About 232. Bulk remove from devPassword.
2. Old identities: usernames on addresses Nino no longer uses, from a list he edits. Start: `@gartner.com`. Money-related logins set aside for a manual check: Pensions group, or pension, 401k, ADP, payroll, mykplan, towerswatson, hancock in the site or title. `@wokinghamvineyard.org` is still active (Nino, 15 October): never an old identity.
3. Same site, several usernames (example: four mykplan.adp.com logins). Keep the one that works.
4. Not really logins: IP addresses, Wi-Fi, gate and alarm codes. Keep, file in a group.
5. Debbie's logins: suggest an Apple shared group with Debbie.

For Apple logins, the screen produces a list to work through in Passwords (Mac or iPhone). The next Apple import marks them removed; the "Removed from Apple" view then clears them from devPassword.
