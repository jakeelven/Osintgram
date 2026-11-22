SHELL := /bin/bash

# Use --cpu when there's no usable NVIDIA driver; ComfyUI otherwise assumes CUDA
# and crashes with "Found no NVIDIA driver" before it ever opens a port.
COMFY_FLAGS ?= $(shell command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 || echo --cpu)

# torch defaults to 1 thread and leaves the extra cores idle; give it one per core.
COMFY_THREADS ?= $(shell nproc 2>/dev/null || echo 4)

setup:

	@echo -e "\e[34m####### Setup for Osintgram #######\e[0m"
	@[ -d config ] || mkdir config || exit 1
	@echo -n "{}" > config/settings.json
	@read -p "Instagram Username: " uservar; \
	read -sp "Instagram Password: " passvar; \
	echo -en "[Credentials]\nusername = $$uservar\npassword = $$passvar"  > config/credentials.ini || exit 1
	@echo ""
	@echo -e "\e[32mSetup Successful - config/credentials.ini created\e[0m"

run:

	@echo -e "\e[34m######## Building and Running Osintgram with Docker-compose ########\e[0m"
	@[ -d config ] || { echo -e "\e[31mConfig folder not found! Please run 'make setup' before running this command.\e[0m"; exit 1; }
	@echo -e "\e[34m[#] Killing old docker processes\e[0m"
	@docker-compose rm -fs || exit 1
	@echo -e "\e[34m[#] Building docker container\e[0m"
	@docker-compose build || exit 1
	@read -p "Target Username: " username; \
	docker-compose run --rm osintgram $$username

build-run-testing:

	@echo -e "\e[34m######## Building and Running Osintgram with Docker-compose for Testing/Debugging ########\e[0m"
	@[ -d config ] || { echo -e "\e[31mConfig folder not found! Please run 'make setup' before running this command.\e[0m"; exit 1; }
	@echo -e "\e[34m[#] Killing old docker processes\e[0m"
	@docker-compose rm -fs || exit 1
	@echo -e "\e[34m[#] Building docker container\e[0m"
	@docker-compose build || exit 1
	@echo -e "\e[34m[#] Running docker container in detached mode\e[0m"
	@docker-compose run --name osintgram-testing -d --rm --entrypoint "sleep infinity" osintgram || exit 1
	@echo -e "\e[32m[#] osintgram-test container is now Running!\e[0m"

cleanup-testing:
	@echo -e "\e[34m######## Cleanup Build-run-testing Container ########\e[0m"
	@docker-compose down
	@echo -e "\e[32m[#] osintgram-test container has been removed\e[0m"

comfy-setup:

	@echo -e "\e[34m######## ComfyUI: creating isolated venv + deps ########\e[0m"
	@cd vendor/ComfyUI && git submodule update --init --recursive 2>/dev/null || true
	@cd vendor/ComfyUI && [ -d .venv ] || python3 -m venv .venv
	@cd vendor/ComfyUI && ./.venv/bin/pip install --upgrade pip
	@cd vendor/ComfyUI && ./.venv/bin/pip install -r requirements.txt
	@# ComfyUI v0.9.2 imports 'requests' (app/frontend_management.py) but no
	@# longer gets it transitively - huggingface-hub 2.x dropped it for httpx2.
	@cd vendor/ComfyUI && ./.venv/bin/pip install "requests>=2.32"
	@echo -e "\e[32mComfyUI ready. Run 'make comfy-run' then open http://localhost:8188\e[0m"

comfy-run:

	@echo -e "\e[34m######## ComfyUI: starting on 0.0.0.0:8188 $(COMFY_FLAGS) ########\e[0m"
	@cd vendor/ComfyUI && OMP_NUM_THREADS=$(COMFY_THREADS) MKL_NUM_THREADS=$(COMFY_THREADS) \
		./.venv/bin/python main.py --listen 0.0.0.0 --port 8188 $(COMFY_FLAGS)

comfy-status:

	@git submodule status vendor/ComfyUI
	@cd vendor/ComfyUI && git describe --tags 2>/dev/null || true

