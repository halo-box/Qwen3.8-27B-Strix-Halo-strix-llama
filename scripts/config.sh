# Settings for start.sh. Every value can be overridden from the environment
# (PARALLEL=4 ./start.sh) or from a .env file next to start.sh (KEY=value lines);
# the environment wins over .env, and .env wins over these defaults.
# shellcheck shell=bash

# .env: KEY=value lines, data only, never sourced; the environment wins.
_env="$(dirname "${BASH_SOURCE[0]}")/../.env"
if [[ -f "$_env" ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || { echo "Error: bad .env line: $line" >&2; exit 1; }
        [[ -z "${!BASH_REMATCH[1]+x}" ]] && export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    done < "$_env"
fi

# ── Engine ───────────────────────────────────────────────────────────────────
: "${BACKEND:=vulkan}"                # vulkan | rocm
case "$BACKEND" in
    rocm)   : "${IMAGE:=ghcr.io/halo-box/strix-llama.cpp:server-rocm-b12474@sha256:c7113fbf44dbd21875140a47fce0812b2725d6ce32756100ded74303f5b6c48d}" ;;
    vulkan) : "${IMAGE:=ghcr.io/halo-box/strix-llama.cpp:server-vulkan-b12474@sha256:fd6c97884343254ff15ae61124f464b8428bbe0bf95d4390c9105981dca497ea}" ;;
    *) echo "Error: BACKEND must be rocm or vulkan, got '$BACKEND'" >&2; exit 1 ;;
esac
: "${SERVER_BIN:=}"                     # llama-server in an image whose entrypoint is not it; empty: the image's entrypoint
: "${CONTAINER_NAME:=qwen38-27b-strix}"

# ── Model ────────────────────────────────────────────────────────────────────
: "${MODEL_DIR:=$HOME/models/qwen38-27b}"
: "${MODEL_FILE:=Qwen3.8-27B-UD-Q4_K_XL.gguf}"
: "${VISION:=1}"                        # image input (the model's own vision tower, 0.9 GB)
: "${MMPROJ_FILE:=mmproj-F16.gguf}"
: "${SERVED_NAME:=Qwen3.8-27B}"

# ── Serving ──────────────────────────────────────────────────────────────────
: "${HOST:=127.0.0.1}"                 # 0.0.0.0 publishes on the LAN; set API_KEY then
: "${PORT:=8080}"
: "${API_KEY:=}"
: "${PARALLEL:=$([[ $BACKEND == vulkan ]] && echo 8 || echo 6)}"  # requests served at once, each with its own CONTEXT_PER_SLOT window; auto = as many as fit
: "${CONTEXT_PER_SLOT:=262144}"        # tokens each request may use (prompt + reply); the model's native window
: "${KV_UNIFIED:=0}"                   # 1: one shared pool of PARALLEL x CONTEXT_PER_SLOT instead of a window per slot
: "${KV_DTYPE:=q8_0}"                  # KV cache type
: "${UBATCH:=2048}"                    # prompt batch
: "${BATCH:=$UBATCH}"
: "${CTX_CHECKPOINTS:=4}"              # recurrent-state checkpoints per slot (host RAM; default 32)
: "${CACHE_RAM:=0}"                    # host prompt cache in MiB (0 = off; default 8192)
: "${LOAD_MODE:=none}"                 # none | dio | mmap. Not mmap: on Vulkan it intermittently wedges amdgpu, on ROCm KFD refuses it

# ── Speculative decoding ─────────────────────────────────────────────────────
: "${DRAFT:=dflash}"                      # mtp (unsloth's MTP head) | dflash (z-lab's DFlash2) | none
case "$DRAFT" in
    mtp)    : "${DRAFT_FILE:=mtp-Qwen3.8-27B-Q4_0.gguf}"; : "${SPEC_TYPE:=draft-mtp}"; : "${DRAFT_N:=3}" ;;
    dflash) : "${DRAFT_FILE:=Qwen3.8-27B-DFlash2-Q4_K_M.gguf}"; : "${SPEC_TYPE:=draft-dflash}"; : "${DRAFT_N:=7}" ;;
    none)   : "${DRAFT_FILE:=}" ;;
    *) echo "Error: DRAFT must be mtp, dflash or none, got '$DRAFT'" >&2; exit 1 ;;
esac
: "${DRAFT_ADAPTIVE:=1}"               # size each draft from measured acceptance: Vulkan, 8 requests, prose 46.0 against 39.3 tok/s fixed
: "${SPEC_DRAFT_MAX_SLOTS:=0}"         # draft only while at most this many requests generate (0 = always); Vulkan, 8 requests: code 98.0 drafting against 61.6 without
: "${DRAFT_P_MIN:=0}"                 # stop a draft chain below this draft probability
: "${SPEC_N_RS_SEQ:=-1}"               # recurrent rollback snapshots per slot (#147); -1 follows DRAFT_N, 0 disables the fast path

# ── Sampling defaults (Qwen's thinking-mode values; a request's own values win) ─
: "${TEMPERATURE:=1.0}"
: "${TOP_P:=0.95}"
: "${TOP_K:=20}"
: "${MIN_P:=0}"

# ── Misc ─────────────────────────────────────────────────────────────────────
: "${EXTRA_ARGS:=}"                    # appended to llama-server; they win over the above
: "${READY_TIMEOUT:=1200}"             # seconds start.sh waits for /health
# GPU memory, from bench/memory.sh (UD-Q4_K_XL, DFlash2, vision on, ubatch 2048; see README, Memory):
: "${MODEL_GIB:=17.4}"                 # the model, its draft and vision tower
# Vulkan's compute buffers stay at 8.8-9.0 GiB from one to eight slots. ROCm's grow by ~2 GiB a slot, which is
# carried in its per-window figure, so its plan runs high for windows shorter than 262k.
if [[ $BACKEND == rocm ]]; then
    : "${COMPUTE_GIB:=$([[ $KV_DTYPE == q8_0 ]] && echo 7.6 || echo 5.8)}"
    : "${KV_GIB_PER_262K:=$([[ $KV_DTYPE == q8_0 ]] && echo 11.7 || echo 19.2)}"
else
    : "${COMPUTE_GIB:=9.0}"
    : "${KV_GIB_PER_262K:=$([[ $KV_DTYPE == q8_0 ]] && echo 9.7 || echo 17.2)}"  # KV, recurrent state and draft KV of one 262,144-token window
fi
: "${RAM_RESERVE_GIB:=10}"             # RAM kept for the OS (GTT is carved out of RAM); Mia's DGX Spark recipe keeps 9 GiB
: "${GTT_MARGIN_GIB:=2}"               # the memory plan stays this far under the GTT limit
