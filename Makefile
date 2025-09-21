.PHONY: all ip cpc reusable verify clean

all: ip cpc reusable

ip:
	@techniques/identical-prefix/run.sh --out-dir techniques/identical-prefix/out

cpc:
	@techniques/chosen-prefix/run.sh --out-dir techniques/chosen-prefix/out

reusable:
	@techniques/reusable-format/run.sh --out-dir techniques/reusable-format/out

verify:
	@python3 tools/verify_all.py techniques/*/out/manifest.json || true

clean:
	@./scripts/clean.sh
