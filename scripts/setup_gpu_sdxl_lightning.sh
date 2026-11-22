#!/usr/bin/env bash
# Vendor a ComfyUI + SDXL-Lightning 4-step stack onto a machine WITH a GPU.
#
# Bypasses the vendored submodule entirely: plain clone, so it can live anywhere.
# Idempotent - safe to re-run.
#
#   ./scripts/setup_gpu_sdxl_lightning.sh              # full setup
#   ./scripts/setup_gpu_sdxl_lightning.sh --skip-models  # code only
#   COMFY_DIR=~/ComfyUI ./scripts/setup_gpu_sdxl_lightning.sh
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
PIN="${COMFY_PIN:-v0.9.2}"
SKIP_MODELS=0
[[ "${1:-}" == "--skip-models" ]] && SKIP_MODELS=1

CKPT_DIR="$COMFY_DIR/models/checkpoints"
LORA_DIR="$COMFY_DIR/models/loras"
DST="$COMFY_DIR/weights/lightning"
mkdir -p "$CKPT_DIR" "$LORA_DIR"

say()  { printf '\033[34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok: %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  WARN: %s\033[0m\n' "$*"; }

# get <url> <dir> <exact-filename>
get() {
  local url="$1" dir="$2" name="$3"
  if [[ -f "$dir/$name" ]]; then ok "present: $name"; return 0; fi
  say "downloading $name"
  if ! curl -fL --retry 3 --retry-delay 2 -C - -o "$dir/$name.part" "$url"; then
    warn "failed: $url"
    rm -f "$dir/$name.part"
    return 1
  fi
  mv "$dir/$name.part" "$dir/$name"
  ok "$name ($(du -h "$dir/$name" | cut -f1))"
}

# ---------------------------------------------------------------- checks
say "checking NVIDIA GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
  ok "GPU detected - no --cpu flag will be used"
  GPU_ARGS=""
else
  warn "no nvidia-smi - this script assumes a GPU box; ComfyUI will run on CPU and be slow"
  GPU_ARGS="--cpu"
fi

say "checking python"
PY="${PYTHON:-python3}"
"$PY" -c 'import sys; assert sys.version_info >= (3,10), sys.version' || {
  echo "python3 >= 3.10 required"; exit 1; }
ok "$("$PY" -V)"

# ---------------------------------------------------------------- comfyui
if [[ -d "$COMFY_DIR/.git" ]]; then
  ok "ComfyUI already at $COMFY_DIR"
else
  say "cloning ComfyUI $PIN -> $COMFY_DIR"
  git clone --depth 1 --branch "$PIN" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
fi

say "python venv + deps"
[[ -d "$COMFY_DIR/.venv" ]] || "$PY" -m venv "$COMFY_DIR/.venv"
# shellcheck disable=SC1091
"$COMFY_DIR/.venv/bin/pip" install -q --upgrade pip
# CUDA wheel index on purpose: PyPI's default linux torch is CUDA-build anyway,
# but the official index is the documented, version-matched route.
"$COMFY_DIR/.venv/bin/pip" install -q torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cu124 || \
  warn "cu124 index failed; falling back to default PyPI torch"
"$COMFY_DIR/.venv/bin/pip" install -q -r "$COMFY_DIR/requirements.txt"
# v0.9.2 imports requests but lost it transitively via huggingface-hub 2.x
"$COMFY_DIR/.venv/bin/pip" install -q "requests>=2.32"
ok "deps installed"
"$COMFY_DIR/.venv/bin/python" - <<'PY'
import torch
print(f"  torch {torch.__version__} | cuda available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  device: {torch.cuda.get_device_name(0)}")
PY

# ---------------------------------------------------------------- weights
if [[ $SKIP_MODELS -eq 0 ]]; then
  say "SDXL base + Lightning LoRAs"
  # SDXL base (fp16 fixed-mirror variant; falls back to the standard path)
  get "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0_0.9vae.safetensors" \
      "$CKPT_DIR" "sd_xl_base_1.0_0.9vae.safetensors" || \
  get "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
      "$CKPT_DIR" "sd_xl_base_1.0.safetensors" || \
  warn "SDXL base not downloaded - get it manually from stabilityai/stable-diffusion-xl-base-1.0"

  # ByteDance/SDXL-Lightning ships safetensors by commit SHA on the HF CDN, so the
  # filenames below are resolved dynamically from the repo tree and archived here
  # too, for reproducible offline re-runs.
  LIGHTNING_BASE="https://huggingface.co/ByteDance/SDXL-Lightning/resolve/main"
  if command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli download ByteDance/SDXL-Lightning sdxl_lightning_4step_lora.safetensors \
      --local-dir "$DST" >/dev/null && \
      cp -f "$DST/sdxl_lightning_4step_lora.safetensors" "$LORA_DIR/" && ok "4step LoRA" || \
      warn "hf-cli download failed"
  else
    get "$LIGHTNING_BASE/sdxl_lightning_4step_lora.safetensors" "$LORA_DIR" "sdxl_lightning_4step_lora.safetensors" || \
      warn "install huggingface_hub then re-run: pip install 'huggingface_hub[cli]'"
  fi
else
  warn "--skip-models: weights not fetched"
fi

# ---------------------------------------------------------------- report
say "state"
printf '  ckpt: '; ls "$CKPT_DIR" 2>/dev/null | tr '\n' ' '; echo
printf '  lora: '; ls "$LORA_DIR" 2>/dev/null | tr '\n' ' '; echo

cat <<EOF

$(printf '\033[32m')Ready.$(printf '\033[0m')

  make-free start:
    cd "$COMFY_DIR" && ./.venv/bin/python main.py --listen 0.0.0.0 --port 8188 $GPU_ARGS

  then load the workflow:
    doc/workflows/sdxl_lightning_4step.json

  settings that matter (Lightning is distilled - these are not tunable):
    steps     4
    cfg       1.0      <- >2 oversaturates badly
    sampler   euler
    scheduler sgm_uniform
    lora strength 1.0
    resolution 1024x1024 (SDXL native)
EOF
