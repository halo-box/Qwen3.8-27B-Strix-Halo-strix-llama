# Credits

This recipe is glue around other people's work. Where a file, setting or idea came from:

## Engine

- `media/halo-box.png`: the Halo Box logo, from [halo-box/strix-llama.cpp](https://github.com/halo-box/strix-llama.cpp).
- [halo-box/strix-llama.cpp](https://github.com/halo-box/strix-llama.cpp): the Strix Halo fork of llama.cpp this
  recipe serves with, from its own `server-vulkan` and `server-rocm` images (b12474, master `c054baa8e`). It includes
  [#147](https://github.com/halo-box/strix-llama.cpp/pull/147) by [LaurentZuijdwijk](https://github.com/LaurentZuijdwijk)
  (`--spec-n-rs-seq`, recurrent-state rollback for drafts on a hybrid model),
  [#151](https://github.com/halo-box/strix-llama.cpp/pull/151) (`--spec-draft-max-slots`),
  [#254](https://github.com/halo-box/strix-llama.cpp/pull/254) (the MTP carry reset),
  [#284](https://github.com/halo-box/strix-llama.cpp/pull/284) (the grammar limit raised for large tool schemas, first
  reported by KYmidnight in [kyuz0/amd-strix-halo-toolboxes#70](https://github.com/kyuz0/amd-strix-halo-toolboxes/issues/70)),
  and [#285](https://github.com/halo-box/strix-llama.cpp/pull/285) (keep-alive after a streamed response).
- The strix-llama.cpp [v1.0.0 release notes](https://github.com/halo-box/strix-llama.cpp/releases/tag/v1.0.0), by
  [Nathanw1014](https://github.com/Nathanw1014): the 27B measurements this recipe starts from (Vulkan ahead of ROCm on
  the dense model, a q8_0 KV cache, unsloth's Q4_0 MTP head with 3 drafts).
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) and [ggml](https://github.com/ggml-org/ggml), by
  Georgi Gerganov and the llama.cpp contributors (MIT): the `qwen35` architecture, the MTP draft
  ([#27739](https://github.com/ggml-org/llama.cpp/pull/27739) by JJJYmmm), DFlash drafting
  ([#22105](https://github.com/ggml-org/llama.cpp/pull/22105)), and `--kv-unified-per-slot`
  ([#24124](https://github.com/ggml-org/llama.cpp/pull/24124)).

## Model

- [Qwen/Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B), by the Qwen team (Apache 2.0).
- [unsloth/Qwen3.8-27B-GGUF](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF), quantized by [Unsloth](https://unsloth.ai):
  `UD-Q4_K_XL`, the `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` draft head, and the vision tower `mmproj-F16.gguf`.
- [z-lab/Qwen3.8-27B-DFlash2-GGUF](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF), the DFlash2 block-diffusion
  draft by [z-lab](https://huggingface.co/z-lab) and [Inco AI](https://huggingface.co/incoai) (Apache 2.0), measured
  against the MTP head (see the README, "How the defaults were chosen").

## Settings and measurements

- [MiaAI-Lab/sparkDash](https://github.com/MiaAI-Lab/sparkDash) (Apache 2.0): the Decode and Prefill benchmarks behind
  every speed figure. `bench/sparkdash.py` only drives its API; the prompts and the arithmetic are sparkDash's.
- [MiaAI-Lab/Qwen3.8-27B-DGX-Spark-TensorFold](https://github.com/MiaAI-Lab/Qwen3.8-27B-DGX-Spark-TensorFold): the
  sparkDash tables this recipe is compared with (decode at 1 / 2 / 4 / 8 requests, prefill 8k to 128k), eight requests
  with a full window each as the default, and the KV-cache quality check `bench/quality.sh` repeats (KL divergence
  and top-1 agreement against a 16-bit cache, on 4 wikitext-2 and 4 CPython sequences of 4,096 tokens).
- [MiaAI-Lab/Qwen3.8-27B-SGLang-DGX-Spark](https://github.com/MiaAI-Lab/Qwen3.8-27B-SGLang-DGX-Spark): the model's own
  sampling defaults (1.0 / 0.95 / 20 / 0), and MTP, DFlash2 and DSpark as the draft candidates for this model.
- `--no-spec-draft-backend-sampling` comes from [AgentionAI](https://agention.ai)'s model cards, by way of the
  Flash-Next recipe.
- [Nathanw1014/strix-halo-llamacpp](https://github.com/Nathanw1014/strix-halo-llamacpp): ubatch sizing and a quantized
  KV cache at depth.
- [halo-box/Qwen3.8-Flash-Next-Strix-Halo-llama](https://github.com/halo-box/Qwen3.8-Flash-Next-Strix-Halo-llama), the
  sibling recipe: every script here starts from its scripts (the memory plan and loading guard, `--load-mode none`,
  `bench/`, `tests/`), and its notes on mmap, CMA-free RAM and Vulkan's first-touch GTT apply unchanged.

## Structure

- [MiaAI-Lab](https://github.com/MiaAI-Lab) ([Mia's AI Lab](https://x.com/MiaAI_lab)), in particular
  [Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold](https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold):
  the shape of this repository and README — one `./start.sh` that prepares, checks, launches, waits and smoke-tests;
  `scripts/config.sh` with `.env` and environment overrides; measured performance and memory tables up front.
- [claudejaune/Qwen3.8-Halogen-Flash-Strix-Halo](https://github.com/claudejaune/Qwen3.8-Halogen-Flash-Strix-Halo):
  `setup.sh` follows its setup.sh (host checks, the GTT kernel parameters, `amd_iommu=off`, the
  `accelerator-performance` tuned profile, one reboot at the end), plus `--ipc=host` and the rule that a `.env` file
  is data, never sourced.
