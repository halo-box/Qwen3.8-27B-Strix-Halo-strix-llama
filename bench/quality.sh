#!/usr/bin/env bash
# bench/quality.sh — what the KV cache type costs in quality, as Mia's TensorFold 27B recipe measures its FP8 cache:
# KL divergence and top-1 agreement against an f16 cache, on 4 sequences of 4,096 tokens of wikitext-2
# (test) and 4 of CPython source (the asyncio package of the host's Python). Needs the GPU; run it with no server up.
#
#   bench/quality.sh [WIKITEXT_TEST_FILE]     writes results/quality/kv.md
#
# Without a file it downloads wikitext-2-raw-v1 from ggml-org/ci, the copy llama.cpp's own perplexity scripts use.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/config.sh
. scripts/host.sh
pgrep -x llama-server >/dev/null && { echo "Error: a llama-server is running; ./stop.sh first" >&2; exit 1; }
DATA=bench/data/quality; OUT=results/quality; mkdir -p "$DATA" "$OUT"
if [[ -n "${1:-}" ]]; then
    [[ -f "$1" ]] || { echo "Error: $1 not found (wikitext-2-raw-v1, wiki.test.raw)" >&2; exit 1; }
    cp "$1" "$DATA/wikitext.txt"
else
    zip=bench/data/wikitext-2-raw-v1.zip
    [[ -f "$zip" ]] || curl -fL --retry 5 -o "$zip" https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip
    [[ "$(sha256sum "$zip" | cut -d' ' -f1)" == ef7edb566e3e2b2d31b29c1fdb0c89a4cc683597484c3dc2517919c615435a11 ]] \
        || { echo "Error: $zip does not match its sha256; delete it and re-run" >&2; exit 1; }
    python3 -I -c 'import sys, zipfile; sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read("wikitext-2-raw/wiki.test.raw"))' \
        "$zip" > "$DATA/wikitext.txt"
fi
asyncio=$(python3 -I -c 'import asyncio, os; print(os.path.dirname(asyncio.__file__))')
find "$asyncio" -name '*.py' | sort | xargs cat > "$DATA/cpython.txt"

DEVICES=(--device "$STRIX_RENDER"); [[ "$BACKEND" == rocm ]] && DEVICES+=(--device /dev/kfd)
GROUPS_ADD=(); for g in $(stat -c %g "$STRIX_RENDER" $([[ "$BACKEND" == rocm ]] && echo /dev/kfd) | sort -u); do GROUPS_ADD+=(--group-add "$g"); done
ppl() {  # ppl CORPUS KV_TYPE LOG ARGS...
    local corpus=$1 kv=$2 log=$3; shift 3
    docker run --rm "${DEVICES[@]}" "${GROUPS_ADD[@]}" --ipc=host --security-opt seccomp=unconfined \
        -v "$MODEL_DIR:/models:ro" -v "$PWD/$DATA:/data" --entrypoint /app/llama "$IMAGE" perplexity \
        -m "/models/$MODEL_FILE" -f "/data/$corpus.txt" -c 4096 -b 2048 -ub "$UBATCH" --chunks 4 \
        -ngl 999 -fa on --load-mode "$LOAD_MODE" -ctk "$kv" -ctv "$kv" "$@" > "$log" 2>&1 \
        || { tail -20 "$log" >&2; exit 1; }
}
row() { awk -v n="$1" '
    function first(s) { sub(/^[^:]*: */, "", s); split(s, a, " "); return a[1] }
    {sub(/^[0-9.]+ [A-Z] /, "")}
    /^Mean +KLD:/ {kld = first($0)}
    /^Same top p:/ {top = first($0)}
    END {printf "| %s | %s | %s |\n", n, kld, top " %"}' "$2"; }

{
    echo "| Corpus | KL of q8_0 to f16 | Top-1 agreement |"
    echo "| --- | ---: | ---: |"
    for c in wikitext cpython; do
        ppl $c f16 "$DATA/$c-f16.log" --kl-divergence-base "/data/$c-f16.kld"
        ppl $c q8_0 "$DATA/$c-q8_0.log" --kl-divergence-base "/data/$c-f16.kld" --kl-divergence
        row "$c" "$DATA/$c-q8_0.log"
        rm -f "$DATA/$c-f16.kld"
    done
} | tee "$OUT/kv.md"
