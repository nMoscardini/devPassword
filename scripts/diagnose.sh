#!/bin/bash
# Read-only vault diagnostics. Prints file names, sizes, permissions, record COUNTS and the
# activity log (action names only). Never prints record contents, keys or secrets.
VDIR="$HOME/Library/Application Support/devPassword"
echo "== Vault folder: $VDIR"
ls -la "$VDIR" "$VDIR/Snapshots" 2>&1
for db in "$VDIR"/vault*.sqlite; do
  [ -f "$db" ] || continue
  echo "== $(basename "$db")"
  echo -n "   records: "; sqlite3 -readonly "$db" "SELECT count(*) FROM entries;" 2>&1
  echo -n "   vault id: "; sqlite3 -readonly "$db" "SELECT json_extract(CAST(value AS TEXT),'$.vaultID') FROM meta WHERE key='header';" 2>&1
done
echo "== Activity log, newest first (live vault)"
sqlite3 -readonly "$VDIR/vault.sqlite" "SELECT datetime(at,'unixepoch','localtime'), action FROM audit ORDER BY id DESC LIMIT 25;" 2>&1
echo "== Backup folder setting"
for dom in com.nino.devPassword devPassword DevPasswordMac; do
  v=$(defaults read "$dom" backupFolder 2>/dev/null) && echo "   $dom: $v" && BDIR="$v"
done
if [ -z "$BDIR" ]; then
  BDIR=$(defaults find backupFolder 2>/dev/null | sed -n 's/.*backupFolder = "\(.*\)";/\1/p' | head -1)
  [ -n "$BDIR" ] && echo "   found: $BDIR"
fi
if [ -n "$BDIR" ] && [ -d "$BDIR" ]; then
  echo "== Backups in $BDIR"
  for f in "$BDIR"/devPassword-backup-*.dpbackup; do
    [ -f "$f" ] || continue
    python3 - "$f" <<'PY'
import json, sys, os
p = sys.argv[1]
try:
    a = json.load(open(p))
    print(f"   {os.path.basename(p)}  {os.path.getsize(p)} bytes  records={len(a.get('entries', []))}  vault={a['header']['vaultID']}")
except Exception as e:
    print(f"   {os.path.basename(p)}  unreadable: {e}")
PY
  done
fi
