#!/usr/bin/env bash
#
# Create a stable self-signed code-signing certificate for Ghost so its
# Accessibility grant survives rebuilds.
#
# macOS keys TCC entries by the binary's code-signing "designated
# requirement". Ad-hoc signatures change every build, which invalidates
# the grant: each rebuild forces the user to re-tick Accessibility.
# Signing with a fixed cert keeps the DR stable across rebuilds, and TCC
# remembers.
#
# Run this ONCE. Idempotent: safe to re-run; it skips work if the cert
# already exists.

set -euo pipefail

CERT_NAME="Ghost Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BUNDLE_ID="com.textutility.ghost"

# Already installed? Done. (find-identity without -v finds untrusted self-
# signed certs too; that's exactly what this script installs.)
EXISTING_COUNT=$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -c "\"$CERT_NAME\"" || true)
if [[ "$EXISTING_COUNT" -ge 1 ]]; then
    if [[ "$EXISTING_COUNT" -eq 1 ]]; then
        echo "cert '$CERT_NAME' already installed (nothing to do)."
    else
        echo "WARNING: $EXISTING_COUNT copies of '$CERT_NAME' in keychain;"
        echo "codesign will be ambiguous. Delete extras with:"
        security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
            | awk -v name="\"$CERT_NAME\"" '$0 ~ name {print "  security delete-identity -Z " $2 " " ENVIRON["HOME"] "/Library/Keychains/login.keychain-db"}'
    fi
    exit 0
fi

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo "creating self-signed code-signing cert: $CERT_NAME"

# Build a config-driven cert request with the X.509 extensions codesign
# requires (codeSigning EKU; digitalSignature key usage; CA:false).
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
[req_dn]
CN = $CERT_NAME
EOF

# Prefer macOS's bundled LibreSSL; its defaults (3DES + SHA1) match what
# `security import` accepts. Fall back to whatever openssl is on PATH.
# Homebrew openssl 3 needs -legacy to produce an importable archive.
OPENSSL="/usr/bin/openssl"
[[ -x "$OPENSSL" ]] || OPENSSL="$(command -v openssl)"
LEGACY_FLAG=""
if "$OPENSSL" pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    LEGACY_FLAG="-legacy"
fi

"$OPENSSL" req -new -x509 -nodes -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -config "$TMP/cert.cnf" \
    -addext "basicConstraints = critical, CA:false" \
    -addext "keyUsage = critical, digitalSignature" \
    -addext "extendedKeyUsage = critical, codeSigning" \
    >/dev/null 2>&1

# `security import` rejects PKCS12 archives encrypted with an empty
# password (it fails MAC verification regardless of algorithm). Use a
# real password; the .p12 is deleted right after, so the value is just
# transient plumbing.
P12_PASSWORD="setup"
"$OPENSSL" pkcs12 -export -out "$TMP/cert.p12" $LEGACY_FLAG \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -passout "pass:$P12_PASSWORD" \
    >/dev/null 2>&1

# Import into login keychain. -T /usr/bin/codesign permits codesign to use
# the private key without re-prompting. The keychain itself may prompt for
# your login password the first time.
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    >/dev/null

# Reset any prior TCC grant for this bundle id so the next launch attaches
# a grant to the new (stable) signature instead of the old ad-hoc one.
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

cat <<EOF

done. next steps:
  1. ./scripts/build_app.sh                  # rebuild + reinstall, signed with the new cert
  2. open ~/Applications/Ghost.app           # launch (will prompt for Accessibility once)
  3. enable Ghost in System Settings, Privacy & Security, Accessibility
  4. quit & relaunch Ghost                   # so the now-trusted process boots clean

after this, subsequent rebuilds via build_app.sh will preserve the grant
because the cert's designated requirement stays stable.
EOF
