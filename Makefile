# Author: Alfonso Pedro Ridao (s243942)
# 02232 Applied Cryptography - Fall 2025

SHELL:=/bin/bash

.PHONY: default ubuntu-first-run deps-ubuntu all list run analysis verify clean help
.DEFAULT_GOAL:= default

# discover technique runners (and one level deeper)
RUNNERS:=$(shell find techniques -mindepth 2 -maxdepth 3 -type f -name run.sh | sort)

# default: deps (Ubuntu/Debian) → build everything
default: ubuntu-first-run

ubuntu-first-run: deps-ubuntu all
	@echo "[done] First run complete."


# nota: deps solo funciona en Ubuntu/Debian
deps-ubuntu:
	@command -v apt >/dev/null 2>&1 || { echo "[deps-ubuntu] apt not found; skipping (non-Ubuntu/Debian)."; exit 0; }
	@echo "[deps-ubuntu] Installing build deps (sudo may prompt)..."
	sudo apt update
	sudo apt install -y build-essential autoconf automake libtool pkg-config m4 \
	                    zlib1g-dev libbz2-dev git git-lfs libboost-all-dev \
	                    curl wget ca-certificates
	@# ensure git-lfs hooks are installed (if any LFS objects exist)
	git lfs install || true

# run all techniques
all:
	@set -e; \
	if [[ -z "$(RUNNERS)" ]]; then \
	  echo "No techniques found (no run.sh under techniques/*)."; exit 1; \
	fi; \
	for r in $(RUNNERS); do \
	  d="$$(dirname "$$r")"; \
	  echo ""; \
	  echo "==> $$r --out-dir $$d/out"; \
	  bash "$$r" --out-dir "$$d/out"; \
	done

# list discovered techniques
list:
	@printf "Discovered run.sh files:\n"; \
	for r in $(RUNNERS); do echo "  $$r"; done

# usage: make run TECH=identical-prefix
run:
	@if [[ -z "$(TECH)" ]]; then echo "Usage: make run TECH=identical-prefix"; exit 2; fi
	@r="$$(find techniques -mindepth 1 -maxdepth 3 -type f -name run.sh -path "techniques/$(TECH)/*" -print -quit)"
	@if [[ -z "$$r" ]]; then echo "No run.sh found under techniques/$(TECH)"; exit 1; fi
	@d="$$(dirname "$$r")"; \
	echo "==> $$r --out-dir $$d/out"; \
	bash "$$r" --out-dir "$$d/out"

analysis:
	@echo "==> Running per-format analysis"; \
	bash techniques/reusable-format/jpeg/analysis/run_analysis.sh || true; \
	bash techniques/reusable-format/pdf/analysis/run_analysis.sh || true; \
	if [[ -f techniques/reusable-format/gzip/out/collision1.tar.gz && -f techniques/reusable-format/gzip/out/collision2.tar.gz ]]; then \
	  ln -sf techniques/reusable-format/gzip/out/collision1.tar.gz techniques/reusable-format/gzip/out/collision1.gz; \
	  ln -sf techniques/reusable-format/gzip/out/collision2.tar.gz techniques/reusable-format/gzip/out/collision2.gz; \
	  bash techniques/reusable-format/gzip/analysis/run_analysis.sh; \
	else \
	  echo "[analysis] gzip outputs missing; skipping gzip analysis"; \
	fi; \
	echo ""; echo "==> Running identical-prefix analysis"; \
	bash techniques/identical-prefix/analysis/run_analysis.sh || true

verify:
	@echo "==> Verifying"
	@python3 tools/verify_all.py techniques/*/out/manifest.json techniques/*/*/out/manifest.json || true
clean:
	@bash scripts/clean.sh

help:
	@echo "Targets:"; \
	echo "  (default)      Install Ubuntu deps, then run all techniques"; \
	echo "  all            Run every techniques/*/run.sh with an out/ dir"; \
	echo "  deps-ubuntu    Install toolchain deps via apt (Ubuntu/Debian)"; \
	echo "  run            Run one technique: make run TECH=identical-prefix"; \
	echo "  analysis       Run format-specific analysis helpers"; \
	echo "  verify         Verify manifests"; \
	echo "  list           List discovered runner scripts"; \
	echo "  clean          Clean outputs"cd