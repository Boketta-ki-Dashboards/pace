#!/bin/sh
# Bricht den Build ab, wenn als SUPABASE_PUBLISHABLE_KEY ein geheimer Schlüssel eingetragen ist, damit er nie in
# eine App (Info.plist, Archiv, TestFlight) gelangt. Erlaubt sind nur öffentliche Keys (sb_publishable_… bzw. der
# alte anon-JWT) oder ein leerer Wert. Der Wert selbst wird nie ausgegeben.
#
# Läuft als Build-Phase des Targets „Pace“ und in der CI (.github/workflows/ios.yml).
set -eu

key="${SUPABASE_PUBLISHABLE_KEY:-}"

fail() {
  echo "error: $1 In Config/Pace.xcconfig gehört ausschließlich der Publishable Key (sb_publishable_…). Siehe docs/BACKEND.md." >&2
  exit 1
}

case "$key" in
  sb_secret_*)
    fail "SUPABASE_PUBLISHABLE_KEY enthält einen Secret Key (sb_secret_…)."
    ;;
esac

# Alte JWT-Keys: Rolle aus dem Payload lesen (base64url, ohne Padding).
payload=$(printf '%s' "$key" | cut -s -d. -f2)
if [ -n "$payload" ]; then
  while [ $(( ${#payload} % 4 )) -ne 0 ]; do
    payload="${payload}="
  done
  if printf '%s' "$payload" | tr '_-' '/+' | base64 --decode 2>/dev/null | grep -Eq '"role"[[:space:]]*:[[:space:]]*"service_role"'; then
    fail "SUPABASE_PUBLISHABLE_KEY ist ein service_role-Key."
  fi
fi

exit 0
