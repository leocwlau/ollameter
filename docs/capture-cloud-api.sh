#!/usr/bin/env bash
set -euo pipefail

: "${OLLAMA_API_KEY:?OLLAMA_API_KEY must be set}"
OLLAMA_API_BASE="${OLLAMA_API_BASE:-https://ollama.com}"
OLLAMA_RANGE="${OLLAMA_RANGE:-24h}"

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
output_dir="${OLLAMA_CAPTURE_DIR:-$script_dir/captured}"
mkdir -p "$output_dir"

balance_url="$OLLAMA_API_BASE/api/balance"
usage_url="$OLLAMA_API_BASE/api/usage?range=$OLLAMA_RANGE&group_by=model"

fetch() {
    local url=$1
    local output=$2
    local status

    status="$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
        --header "Authorization: Bearer $OLLAMA_API_KEY" "$url")"

    if [[ $status != 2* ]]; then
        echo "Request failed with HTTP $status: $url" >&2
        exit 1
    fi
}

fetch "$balance_url" "$output_dir/balance.json"
fetch "$usage_url" "$output_dir/usage.json"

echo "Balance response: $output_dir/balance.json"
echo "Usage response ($OLLAMA_RANGE): $output_dir/usage.json"
