#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SIGNING_DIR="$ROOT_DIR/.signing"
KEYCHAIN_PATH="$SIGNING_DIR/Vidget.keychain-db"
PASSWORD_PATH="$SIGNING_DIR/keychain-password"
CERTIFICATE_PATH="$SIGNING_DIR/Vidget-certificate.pem"
IDENTITY_NAME="Vidget Local Development"

function ensure_keychain_is_searchable() {
    if security list-keychains -d user | grep -Fq "$KEYCHAIN_PATH"; then
        return
    fi

    local -a current_keychains
    current_keychains=("${(@f)$(
        security list-keychains -d user | \
            sed -e 's/^[[:space:]]*"//' -e 's/"$//'
    )}")
    security list-keychains -d user -s "${current_keychains[@]}" "$KEYCHAIN_PATH"
}

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ -f "$KEYCHAIN_PATH" ]] && \
   [[ -f "$PASSWORD_PATH" ]] && \
   security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | \
       grep -Fq "$IDENTITY_NAME"; then
    IFS= read -r keychain_password < "$PASSWORD_PATH"
    security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
    ensure_keychain_is_searchable
    exit 0
fi

if [[ ! -f "$PASSWORD_PATH" ]]; then
    openssl rand -hex 32 -out "$PASSWORD_PATH"
    chmod 600 "$PASSWORD_PATH"
fi

IFS= read -r keychain_password < "$PASSWORD_PATH"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/vidget-signing.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

openssl req \
    -new \
    -newkey rsa:2048 \
    -x509 \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME/O=Vidget Local Build/" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$temporary_dir/private-key.pem" \
    -out "$temporary_dir/certificate.pem" \
    >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -inkey "$temporary_dir/private-key.pem" \
    -in "$temporary_dir/certificate.pem" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$keychain_password" \
    -out "$temporary_dir/identity.p12"

if [[ -f "$KEYCHAIN_PATH" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
fi

security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security import "$temporary_dir/identity.p12" \
    -k "$KEYCHAIN_PATH" \
    -t agg \
    -f pkcs12 \
    -P "$keychain_password" \
    -T /usr/bin/codesign
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$KEYCHAIN_PATH" \
    >/dev/null
cp "$temporary_dir/certificate.pem" "$CERTIFICATE_PATH"
chmod 600 "$CERTIFICATE_PATH"
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN_PATH" \
    "$CERTIFICATE_PATH"
ensure_keychain_is_searchable

echo "Создана локальная identity: $IDENTITY_NAME"
