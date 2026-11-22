# Vendored ComfyUI

`vendor/ComfyUI` is a **git submodule** pointing at
[Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI), pinned to a release
tag (currently `v0.9.2`).

It is here to provide local, open-weight image generation / editing: instruction
edits, inpainting, outpainting, upscaling, ControlNet-style conditioning. Nothing
in the Osintgram Python package imports it — it runs as a separate service that
talks HTTP on `http://localhost:8188`.

## Why a submodule and not a plain copy

- Osintgram's own diff / history stays clean (one gitlink entry, no 1,300 files).
- You can pin, bump, or drop it without touching Osintgram's source.
- Model weights are **never** in git — they live in `vendor/ComfyUI/models/`
  which is ignored by ComfyUI's own `.gitignore`.

## Setup

```bash
git submodule update --init --recursive   # once after cloning Osintgram
make comfy-setup                          # isolated .venv + pip install -r requirements.txt
make comfy-run                            # serves 0.0.0.0:8188
```

Then open `http://localhost:8188`. Weights are downloaded into
`vendor/ComfyUI/models/` on first use (or via ComfyUI-Manager).

> `--listen 0.0.0.0` binds to every interface. On a laptop that is fine; on a
> shared network drop it and ComfyUI will listen on loopback only.

## Suggested first nodes

For Osintgram-style media work the useful starting points are:

| Job | Node / model |
| --- | --- |
| Instruction edit ("remove the car", "make it night") | Qwen-Image-Edit 2511, FLUX.1 Kontext dev |
| Object removal / inpainting | LaMa, PowerPaint, SDXL inpaint |
| Expand frame / outpaint | PowerPaint, SDXL outpaint |
| Mask extraction | SAM2 (Segment Anything) |
| Face repair after edit | CodeFormer, GFPGAN |
| Upscale | Real-ESRGAN, SeedVR2 |

VRAM floor: ~8 GB (FLUX.2 klein 4B), 12–16 GB (Qwen-Image-Edit GGUF/FP8),
24 GB (Kontext dev / Qwen-Image-Edit FP8 comfortably).

## Updating / removing

```bash
make comfy-status                                   # what's pinned now
cd vendor/ComfyUI && git fetch --tags && git checkout v0.10.0
cd - && git add vendor/ComfyUI && git commit -m "Bump ComfyUI"

# remove entirely
git submodule deinit -f vendor/ComfyUI
git rm -f vendor/ComfyUI && git rm .gitmodules
```

## Licence note

ComfyUI itself is GPL-3.0; that applies to ComfyUI, not to Osintgram. Model
weights each carry their own licence — check before commercial use (FLUX.1 dev
and Kontext dev are non-commercial; Qwen-Image-Edit and FLUX.2 klein 4B are
Apache-2.0).
