#!/bin/bash
# Creates a trusted local self-signed Code Signing certificate in the login keychain
# so Gary Tools keeps a stable code signature across rebuilds and macOS preserves
# Accessibility / Screen Recording permissions.
set -euo pipefail

CERT_NAME="${GARY_TOOLS_SIGN_IDENTITY:-Gary Tools Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = Darwin ] || die "Code signing setup only runs on macOS."

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  say "Signing identity \"$CERT_NAME\" is already installed and trusted."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# If an untrusted cert with the same name already exists in the login keychain, reuse it
# instead of creating duplicates.
if security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > "$TMP/existing.pem" 2>/dev/null && [ -s "$TMP/existing.pem" ]; then
  say "Found existing \"$CERT_NAME\" certificate — marking it trusted for code signing"
  say "(macOS may prompt for Touch ID or your login password once)"
  security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/existing.pem"
else
  say "Creating self-signed code signing certificate \"$CERT_NAME\" (valid 10 years)"
  cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no

[dn]
CN = $CERT_NAME

[codesign_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

  # Use macOS LibreSSL (/usr/bin/openssl) so the PKCS#12 container is always accepted by security import.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf" 2>/dev/null

  PASS=$(/usr/bin/openssl rand -hex 16)
  /usr/bin/openssl pkcs12 -export \
    -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -passout "pass:$PASS"

  say "Importing \"$CERT_NAME\" into login keychain"
  security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

  say "Trusting \"$CERT_NAME\" for code signing (macOS will ask for Touch ID or your password once)"
  security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
fi

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  say "Ready: \"$CERT_NAME\" will be used automatically by ./build.sh"
else
  die "Certificate was created but is not yet listed as a valid code signing identity. Open Keychain Access, find \"$CERT_NAME\", and set Code Signing trust to Always Trust."
fi
