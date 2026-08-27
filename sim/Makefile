# AXI4 -> AHB-Lite bridge : QuestaSim flow
# Run from anywhere:  make -C sim run
# ROOT is the repo root, derived from this Makefile's own location.

ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
WORK    := build/work
TOP     := tb_top
OPT     := tb_opt
FILELIST:= sim/tb.f

# Run knobs, overridable:  make run SEED=42 TEST=smoke
SEED    ?= 1
TEST    ?= base_test
COVDIR  := build/cov

VLOG_FLAGS := -sv -work $(WORK) -f $(FILELIST)

# Two build flavors: debug keeps full visibility, fast drops it for regressions.
VOPT_DEBUG := -work $(WORK) $(TOP) -o $(OPT) -debug
VOPT_FAST  := -work $(WORK) $(TOP) -o $(OPT) +cover=bcefsx

VSIM_FLAGS := -c -lib $(WORK) $(OPT) -sv_seed $(SEED)

.PHONY: all lib compile opt run gui wave regress cov clean

all: run

lib:
	@cd $(ROOT) && test -d $(WORK) || vlib $(WORK)

compile: lib
	cd $(ROOT) && vlog $(VLOG_FLAGS)

opt: compile
	cd $(ROOT) && vopt $(VOPT_DEBUG)

# One interactive run. Waves land in build/run_$(SEED).wlf for post-hoc debug.
run: opt
	cd $(ROOT) && mkdir -p build && vsim $(VSIM_FLAGS) \
	  -wlf build/run_$(SEED).wlf \
	  -do "log -r /*; run -all; quit"

# Same run, GUI up front. Use when you already know you'll be poking at it.
gui: opt
	cd $(ROOT) && vsim -gui -lib $(WORK) $(OPT) -sv_seed $(SEED) \
	  -do "log -r /*; run -all"

# Post-hoc: open the waves from the last `make run` without re-simulating.
wave:
	cd $(ROOT) && vsim -view build/run_$(SEED).wlf

# Regression: N seeds, no visibility, coverage on, one UCDB per seed.
# Usage: make regress N=50
N ?= 10
regress: compile
	cd $(ROOT) && vopt $(VOPT_FAST) && mkdir -p $(COVDIR) && \
	for s in $$(seq 1 $(N)); do \
	  echo "=== seed $$s ==="; \
	  vsim -c -lib $(WORK) $(OPT) -coverage -sv_seed $$s \
	    -do "run -all; coverage save $(COVDIR)/run_$$s.ucdb; quit" \
	    || exit 1; \
	done

cov:
	cd $(ROOT) && vcover merge $(COVDIR)/merged.ucdb $(COVDIR)/run_*.ucdb && \
	  vcover report -details -html -htmldir docs/coverage $(COVDIR)/merged.ucdb && \
	  vcover report -details $(COVDIR)/merged.ucdb

clean:
	cd $(ROOT) && rm -rf build transcript vsim.wlf vsim.dbg* *.log
