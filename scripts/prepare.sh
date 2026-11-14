#!/usr/bin/env bash
# prepare.sh — one-time setup, safe to re-run: the model files, then the engine image.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/config.sh

# ── Model files (resumable; verified once against Hugging Face's sha256) ─────
fetch() {  # fetch FILE URL SIZE SHA256 DEFAULT_NAME; only the default files are downloaded
    local f="$MODEL_DIR/$1" url=$2 size=$3 sha=$4
    if [[ "$1" != "$5" ]]; then
        [[ -f "$f" ]] || { echo "Error: $f not found" >&2; exit 1; }
        return 0
    fi
    if [[ ! -f "$f" || $(stat -c %s "$f") -ne $size ]]; then
        local have=0; [[ -f "$f" ]] && have=$(stat -c %s "$f")
        local free; free=$(df -Pk "$MODEL_DIR" | awk 'NR == 2 {print $4 * 1024}')
        ((free > size - have + 2**30)) || { echo "Error: not enough disk in $MODEL_DIR for $1" >&2; exit 1; }
        echo "downloading $1 ($(awk -v s="$size" 'BEGIN{printf "%.1f", s / 2^30}') GiB, resumes if interrupted)"
        curl -fL --progress-bar --retry 10 --retry-delay 5 -C - -o "$f" "$url"
    fi
    if [[ ! -f "$f.verified" ]]; then
        echo "verifying $1"
        [[ "$(sha256sum "$f" | cut -d' ' -f1)" == "$sha" ]] \
            || { echo "Error: $1 does not match its published sha256; delete it and re-run" >&2; exit 1; }
        touch "$f.verified"
    fi
}
mkdir -p "$MODEL_DIR"
UNSLOTH=https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main
ZLAB=https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF/resolve/main
fetch "$MODEL_FILE" $UNSLOTH/Qwen3.8-27B-UD-Q4_K_XL.gguf \
    17659407264 2a5f3565f39cf885103da591182c1266da64745737b42b452fd3e675369f1211 Qwen3.8-27B-UD-Q4_K_XL.gguf
case "$DRAFT" in
    mtp) fetch "$DRAFT_FILE" $UNSLOTH/MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
        1369590656 50d9ce5a6da381bbcfb31061cf73df94a90e6faf8efeddee379a9cb8f1501c6e mtp-Qwen3.8-27B-Q4_0.gguf ;;
    dflash) fetch "$DRAFT_FILE" $ZLAB/Qwen3.8-27B-DFlash2-Q4_K_M.gguf \
        1143006816 1a25c56858e1ebe93f2718ac1d49d1151f9323325c1bbfd6209370f4db131ebd Qwen3.8-27B-DFlash2-Q4_K_M.gguf ;;
esac
if [[ "$VISION" == 1 ]]; then
    fetch "$MMPROJ_FILE" $UNSLOTH/mmproj-F16.gguf \
        927607488 cbb841a9ee0636b2ec172f5bb8df2ea8dfeb01e90fe7c6126581d662a0b4e43e mmproj-F16.gguf
fi

# ── Engine image: strix-llama.cpp's own, pinned in scripts/config.sh ─────────
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" \
    || { echo "Error: could not pull $IMAGE" >&2; exit 1; }
