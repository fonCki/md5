
SHELL := /bin/bash

.PHONY: all verify clean list

.PHONY: analysis

analysis:
	@echo ""; echo "==> Running per-format analysis"
	@bash techniques/reusable-format/jpeg/analysis/run_analysis.sh
	@bash techniques/reusable-format/pdf/analysis/run_analysis.sh
	@# Ensure .gz names exist for the analyzer (it expects *.gz)
	@ln -sf techniques/reusable-format/gzip/out/collision1.tar.gz techniques/reusable-format/gzip/out/collision1.gz
	@ln -sf techniques/reusable-format/gzip/out/collision2.tar.gz techniques/reusable-format/gzip/out/collision2.gz
	@bash techniques/reusable-format/gzip/analysis/run_analysis.sh

# Find run.sh at depth 2 or 3: techniques/<name>/run.sh and techniques/<name>/<sub>/run.sh
RUNNERS := $(shell find techniques -mindepth 2 -maxdepth 3 -type f -name run.sh | sort)

all:
	@set -e; \
	if [[ -z "$(RUNNERS)" ]]; then \
	  echo "No techniques found (no run.sh under techniques/*)."; exit 1; \
	fi; \
	for r in $(RUNNERS); do \
	  d="$$(dirname "$$r")"; \
	  echo ""; \
	  echo "==> $$r --out-dir $$d/out"; \
	  "$$r" --out-dir "$$d/out"; \
	done

list:
	@printf "Discovered run.sh files:\n"; \
	for r in $(RUNNERS); do echo "  $$r"; done

verify:
	@echo ""; echo "==> Verifying"; \
	python3 tools/verify_all.py techniques/*/out/manifest.json techniques/*/*/out/manifest.json || true

clean:
	@bash scripts/clean.sh