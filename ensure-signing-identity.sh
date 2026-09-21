#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=script/product_config.sh
source "$ROOT/script/product_config.sh"
load_product_config "$ROOT/config/product.conf"

identity_count="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fc "\"$SIGNING_IDENTITY\"" || true)"
if [[ "$identity_count" == "1" ]]; then
  echo "found: $SIGNING_IDENTITY"
  exit 0
fi

if [[ "$identity_count" != "0" ]]; then
  echo "Expected exactly one valid signing identity named $SIGNING_IDENTITY; found $identity_count." >&2
  exit 1
fi

echo "Missing signing identity: $SIGNING_IDENTITY" >&2
echo "Create one in Keychain Access as Self Signed Root / Code Signing." >&2
exit 1
