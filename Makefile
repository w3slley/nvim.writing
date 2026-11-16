NVIM ?= nvim
APPNAME ?= writing-dev
SCRATCH := .scratch
T ?=

.PHONY: help run test bench clean

help:
	@echo "make run      open nvim with the plugin and a scratch copy of sample.md"
	@echo "make test     run the headless test suite (T=context|core|buffer|dict|finder|define for one file)"
	@echo "make bench    run the latency benchmark (needs API keys or BENCH_TARGETS)"
	@echo "make clean    remove the scratch copy"

run:
	@mkdir -p $(SCRATCH)
	@cp sample.md $(SCRATCH)/sample.md
	NVIM_APPNAME=$(APPNAME) $(NVIM) -u $(CURDIR)/init.lua $(SCRATCH)/sample.md

test:
	$(NVIM) --headless -u NONE -l tests/run.lua $(T)

bench:
	$(NVIM) --headless -u NONE -l scripts/bench.lua

clean:
	rm -rf $(SCRATCH)
