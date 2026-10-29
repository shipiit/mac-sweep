#!/usr/bin/env bash
# One-time setup: creates a local, self-signed "MacSweep Local Signing" code-signing certificate in your login
# keychain. Builds signed with it keep the same identity, so macOS remembers Full Disk Access and Keychain
# "Always Allow" across updates. It never leaves this Mac; delete it any time in Keychain Access.
set -euo pipefail
NAME="MacSweep Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists."
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 3650 -config "$work/cert.cnf" 2>/dev/null
pass=$(openssl rand -hex 16)
openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout "pass:$pass" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout "pass:$pass"
# Only codesign may use the private key.
security import "$work/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" -T /usr/bin/codesign
echo "Created \"$NAME\". Run 'make install', then grant Full Disk Access to MacSweep once more."
