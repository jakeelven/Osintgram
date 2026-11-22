# SDXL Lightning 4-step (GPU box)

Fastest sane text-to-image path: SDXL base + ByteDance's 4-step Lightning LoRA.
**2–3 s per 1024×1024 image** on a mid-range GPU (RTX 3060/4060 class).

This does **not** run in the Arena sandbox — no GPU, and model hosts are blocked
at the network layer. It's meant to be run on your own machine.

## One command

```bash
cd Osintgram
./scripts/setup_gpu_sdxl_lightning.sh
```

What it does: checks for an NVIDIA GPU, clones ComfyUI `v0.9.2` to `$HOME/ComfyUI`
(override with `COMFY_DIR=`), builds a venv, installs CUDA torch + deps, then pulls:

| File | Destination | Size |
| --- | --- | --- |
| `sd_xl_base_1.0_0.9vae.safetensors` | `models/checkpoints/` | ~6.9 GB |
| `sdxl_lightning_4step_lora.safetensors` | `models/loras/` | ~400 MB |

Idempotent — re-running skips anything already present. `--skip-models` for
code-only setup.

Then start it:

```bash
cd "$HOME/ComfyUI" && ./.venv/bin/python main.py --listen 0.0.0.0 --port 8188
```

## Load the workflow

`doc/workflows/sdxl_lightning_4step.json` — drag it onto the ComfyUI canvas, or
`Workflow → Open`. Eight nodes: checkpoint → Lightning LoRA → two CLIP encodes →
KSampler → VAE decode → save.

This graph was validated against a live ComfyUI 0.9.2 server's `/prompt`
endpoint and returned `prompt_id` with `node_errors: {}`.

## The settings are not suggestions

Lightning is a distilled model. Deviating from these makes output *worse*, not better:

| Setting | Value | Why |
| --- | --- | --- |
| steps | **4** | trained for exactly 4; 20 steps gives oversaturated mush |
| cfg | **1.0** | above ~2 blows out colours; also 2× compute |
| sampler | **euler** | required for the `sgm_uniform` schedule to line up |
| scheduler | **sgm_uniform** | the trailing timestep spacing Lightning was trained on |
| LoRA strength | **1.0** | lower values under-bake the distillation |
| resolution | **1024×1024** | SDXL native; 512 gives poor anatomy |

Negative prompts are effectively ignored at cfg 1.0 (no guidance step to apply
them) — harmless to leave in the graph, just don't expect them to do work.

## Alternative: SDXL-Turbo (even faster, lower quality)

If 2–3 s is somehow too slow, swap in `stabilityai/sdxl-turbo` as a single
checkpoint: **1 step**, cfg **0.0**, sampler `euler_ancestral`, scheduler
`normal`, 512×512. Sub-second on a 4090, ~1 s on a 3060. Lower fidelity and no
negative-prompt control at all — good for thumbnails and iteration, not finals.

## VRAM

- fp16 SDXL + Lightning: **~8 GB** comfortably; 6 GB with `--lowvram`
- 12 GB+ lets ComfyUI keep the model resident between runs (first run pays the load cost)

## Sanity checks on the GPU box

```bash
nvidia-smi                                             # driver + VRAM
./.venv/bin/python -c "import torch;print(torch.cuda.is_available())"   # must be True
```

If `torch.cuda.is_available()` is `False`, the wheel is CPU-only or the driver is
missing — fix that before blaming ComfyUI.
