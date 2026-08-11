#!/usr/bin/env bash
# Create a STABLE self-signed code-signing certificate for Prosciutto — run ONCE per Mac
# that cuts releases (and on your dev machine). No Apple Developer account, no cost.
#
# Why: macOS ties TCC permissions (Accessibility, "access data from other apps", Desktop
# folder, …) to the app's CODE SIGNATURE. An ad-hoc signature (`codesign --sign -`) gets a
# fresh cdhash on every build, so macOS sees each release as a new app and drops every grant
# — the user must re-grant after every update. A certificate reused across releases gives a
# STABLE designated requirement (identifier + this cert's hash), so the grants persist across
# updates. It is NOT notarized, so Gatekeeper still shows "unidentified developer" (same as
# ad-hoc, one right-click→Open / handled by the Homebrew cask) — but permissions stick.
#
# The private key never leaves your keychain. To release from another machine or CI, export
# the identity once (`security export`) and import it there; keep the same cert forever.
set -euo pipefail

IDENTITY="${PROSCIUTTO_SIGN_IDENTITY:-Prosciutto Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# NOTE: no `-v` — a self-signed cert is untrusted, so it never appears in the "valid
# identities" list, but codesign uses it fine and its designated requirement is still a
# STABLE `identifier + certificate root` (verified: that's what makes TCC persist). Match
# by name in the full list instead.
if security find-identity -p codesigning | grep -qF "$IDENTITY"; then
  echo "==> Identity '$IDENTITY' already exists — nothing to do."
  security find-identity -p codesigning | grep -F "$IDENTITY"
  exit 0
fi

echo "==> Creating self-signed code-signing certificate '$IDENTITY'"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
KEY="$TMP/key.pem"; CERT="$TMP/cert.pem"; P12="$TMP/cert.p12"; CONF="$TMP/openssl.cnf"
P12_PASS="prosciutto-cert-import"

# A code-signing cert: not a CA, digitalSignature + codeSigning EKU (both critical) so
# `codesign` and `security find-identity -p codesigning` recognize it. 10-year validity.
cat > "$CONF" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3
[dn]
CN = $IDENTITY
O = Prosciutto
C = US
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl genrsa -out "$KEY" 2048 2>/dev/null
openssl req -new -x509 -key "$KEY" -out "$CERT" -days 3650 -config "$CONF" 2>/dev/null
# `-legacy`: OpenSSL 3 defaults to AES-256/SHA-256 PKCS#12, which Apple's `security import`
# can't read. The legacy (PBE-SHA1-3DES) encoding is what the keychain accepts.
openssl pkcs12 -export -legacy -out "$P12" -inkey "$KEY" -in "$CERT" -passout "pass:$P12_PASS" 2>/dev/null

# Import into the login keychain. `-T /usr/bin/codesign` pre-authorizes codesign to use the
# private key, so signing doesn't prompt. The set-key-partition-list call best-effort quiets
# the keychain ACL further; it needs the login-keychain password and is harmless if it can't
# run non-interactively (codesign still works via the `-T` grant above) — hence `|| true`. If
# macOS ever pops "codesign wants to sign using key…" on the first build, click Always Allow.
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "==> Done. Identity now available (shows as untrusted — that's expected and fine):"
security find-identity -p codesigning | grep "$IDENTITY"
cat <<EOF

Next:
  • Releases: scripts/package-dmg.sh now signs with '$IDENTITY' automatically.
  • Keep this cert forever — signing every release with it is what makes permissions persist.
  • Existing users re-grant ONCE on the first signed release; updates after that keep the grant.
EOF
