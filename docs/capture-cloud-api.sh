#!/usr/bin/env bash
set -euo pipefail

: "${OLLAMA_API_KEY:?OLLAMA_API_KEY must be set}"
OLLAMA_API_BASE="${OLLAMA_API_BASE:-https://ollama.com}"
usage_ranges=("24h" "7d" "30d")

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
output_dir="${OLLAMA_CAPTURE_DIR:-$script_dir/captured}"
mkdir -p "$output_dir"

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

fetch "$OLLAMA_API_BASE/api/balance" "$output_dir/balance.json"

for range in "${usage_ranges[@]}"; do
    usage_url="$OLLAMA_API_BASE/api/usage?range=$range&group_by=model"
    fetch "$usage_url" "$output_dir/usage-${range}.json"
done

echo "Balance response: $output_dir/balance.json"
for range in "${usage_ranges[@]}"; do
    echo "Usage response (${range}): $output_dir/usage-${range}.json"
done
