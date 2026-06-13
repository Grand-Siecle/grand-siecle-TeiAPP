#!/usr/bin/env bash
# Upload de ressources vers eXist-db via REST PUT, UN PAR UN avec pause.
# Lit la config serveur depuis .existdb.json (serveur/user/password/root).
#
# A utiliser quand la sync VS Code n'est pas disponible (extension HS) ou pour un
# upload controle et verifiable (chaque PUT renvoie un code HTTP synchrone -> la
# cadence se regule d'elle-meme ; la pause ajoute une respiration au serveur).
#
# Le chemin distant est calcule relativement a la racine du repo : un fichier
# data/registers/persons.xml va dans <root>/data/registers/persons.xml.
#
# Usage :
#   scripts/upload_tei.sh data/*.tei.xml
#   scripts/upload_tei.sh data/registers/*.xml data/*.tei.xml
#   PAUSE=5 scripts/upload_tei.sh data/LIV0013_reconciled.tei.xml
#
# Variables : PAUSE (secondes entre fichiers, defaut 3), SERVERKEY (cle de .existdb.json).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/.existdb.json"
PAUSE="${PAUSE:-3}"

# Lecture de la config serveur depuis .existdb.json.
# 1 champ par ligne (un mot de passe VIDE casserait un read positionnel).
{ read -r SERVER; read -r USER; read -r PASS; read -r APPROOT; } < <(SERVERKEY="${SERVERKEY:-}" python3 - "$CFG" <<'PY'
import json, os, sys
c = json.load(open(sys.argv[1]))
key = os.environ.get("SERVERKEY") or c.get("sync", {}).get("server") or next(iter(c["servers"]))
s = c["servers"][key]
print(s["server"]); print(s.get("user", "")); print(s.get("password", "")); print(s["root"])
PY
)
BASE="$SERVER/rest$APPROOT"
echo "Cible : $BASE  (user: $USER, pause: ${PAUSE}s)"

n=0; ok=0; fail=0
for f in "$@"; do
  [ -f "$f" ] || { echo "absent, ignore : $f"; continue; }
  n=$((n+1))
  rel="$(realpath --relative-to="$ROOT" "$f")"
  url="$BASE/$rel"
  sz=$(du -h "$f" | cut -f1)
  t0=$SECONDS
  code=$(curl -s -o /tmp/_upload_err -w '%{http_code}' -X PUT -u "$USER:$PASS" \
         -H 'Content-Type: application/xml' --data-binary @"$f" "$url")
  dt=$((SECONDS-t0))
  if [ "$code" = "201" ] || [ "$code" = "200" ]; then
    echo "OK   $code (${sz}, ${dt}s) $rel"; ok=$((ok+1))
  else
    echo "FAIL $code (${sz}) $rel -> $(head -c 200 /tmp/_upload_err)"; fail=$((fail+1))
  fi
  sleep "$PAUSE"
done
echo "--- $ok OK / $fail echecs sur $n fichiers ---"
