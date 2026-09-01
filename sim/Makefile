# AXI4 -> AHB-Lite bridge : QuestaSim flow
# Run from inside project:  make -C sim run

THIS_MK := $(abspath $(lastword $(MAKEFILE_LIST)))
ROOT    := $(abspath $(dir $(THIS_MK))/..)
WORK    := build/work
TOP     := tb_top
OPT     := tb_opt
FILELIST:= sim/tb.f

# Run knobs, overridable:  make run SEED=42 N_TRANS=1000 TIMEOUT_NS=100000
SEED    ?= 1
TEST    ?= base_test
TIMEOUT_NS ?= 100000
N_TRANS ?= 1000
COVDIR  := build/cov
LOGDIR  := $(ROOT)/build/logs
SUMFILE := $(LOGDIR)/summary.txt
RESULTS := $(LOGDIR)/results.txt
GENERICS := -gTIMEOUT_NS=$(TIMEOUT_NS) -gN_TRANS=$(N_TRANS)

RUNDIR   := $(ROOT)/build
ABS_WORK := $(ROOT)/$(WORK)
DESIGNBIN:= $(ROOT)/build/design.bin
WAVEDB   := $(RUNDIR)/run_$(SEED).db
QWAVE    := -qwavedb=+signal+memory+msgmode=both+wavefile=$(WAVEDB)

# Optional signal list
WAVEDO   := $(ROOT)/sim/wave.do
DOWAVE   := $(if $(wildcard $(WAVEDO)),do $(WAVEDO); ,)

VLOG_FLAGS := -sv -work $(WORK) -f $(FILELIST)

# Two build flavors: debug keeps full visibility, fast drops it for regressions.
VOPT_DEBUG := -work $(WORK) $(TOP) -o $(OPT) $(GENERICS) -debug -designfile $(DESIGNBIN)
VOPT_FAST  := -work $(WORK) $(TOP) -o $(OPT) $(GENERICS) +cover=bcefsx

VSIM_FLAGS := -c -lib $(ABS_WORK) $(OPT) -sv_seed $(SEED)

.PHONY: all lib compile opt run gui wave regress summary cov clean

all: run

# vlib does not create parent directories, and `clean` removes build/ entirely.
lib:
	@cd $(ROOT) && mkdir -p $(dir $(WORK)) && { test -d $(WORK) || vlib $(WORK); }

compile: lib
	cd $(ROOT) && vlog $(VLOG_FLAGS)

opt: compile
	cd $(ROOT) && vopt $(VOPT_DEBUG)

# One batch run. Waves land in $(WAVEDB) for post-hoc debug.
run: opt
	cd $(RUNDIR) && vsim $(VSIM_FLAGS) $(QWAVE) \
	  -do "run -all; quit"

# Same run with Visualizer up front. Use when you know you'll be poking at it.
gui: opt
	cd $(RUNDIR) && vsim -visualizer=$(DESIGNBIN) -lib $(ABS_WORK) $(OPT) \
	  -sv_seed $(SEED) $(QWAVE) -do "$(DOWAVE)run -all"

# Post-hoc: open the waves from the last `make run` without re-simulating.
wave:
	cd $(RUNDIR) && visualizer -designfile $(DESIGNBIN) -wavefile $(WAVEDB)

# Regression: N seeds, no visibility, coverage on, one UCDB per seed.
# Usage: make regress N=50
N ?= 10
regress: compile
	cd $(ROOT) && vopt $(VOPT_FAST) && mkdir -p $(COVDIR) $(LOGDIR)
	@rm -f $(RESULTS)
	-@cd $(RUNDIR) && for s in $$(seq 1 $(N)); do \
	  log=$(LOGDIR)/seed_$$s.log; \
	  vsim -c -lib $(ABS_WORK) $(OPT) -coverage -sv_seed $$s \
	    -l $$log \
	    -do "run -all; coverage save $(ROOT)/$(COVDIR)/run_$$s.ucdb; quit" \
	    > /dev/null 2>&1; \
	  if [ ! -f $$log ]; then v="FAIL  no log"; \
	  elif grep -qE '\*\* (Error|Fatal)' $$log; then \
	    v="FAIL  $$(grep -cE '\*\* (Error|Fatal)' $$log) error(s)"; \
	  elif ! grep -qE 'TEST (DONE|PASSED)' $$log; then \
	    v="FAIL  did not finish"; \
	  else v="PASS"; fi; \
	  printf 'seed %-4s %s\n' $$s "$$v" | tee -a $(RESULTS); \
	done
	@$(MAKE) --no-print-directory -f $(THIS_MK) summary N=$(N) BRIEF=1

# Verdict for the last regression, tallied from the per-seed results that
# `regress` recorded. Re-runnable without re-simulating.
summary:
	@if [ ! -f $(RESULTS) ]; then \
	  echo "no results -- run 'make regress N=<n>' first"; exit 1; fi; \
	{ if [ -z "$(BRIEF)" ]; then grep -v 'PASS$$' $(RESULTS) || true; fi; \
	  t=$$(wc -l < $(RESULTS) | tr -d ' '); \
	  p=$$(grep -c 'PASS$$' $(RESULTS) || true); \
	  if [ "$$p" = "$$t" ]; then \
	    echo "REGRESSION PASSED  $$t/$$t seeds"; echo 0 > $(LOGDIR)/.status; \
	  else \
	    echo "REGRESSION FAILED  $$(($$t-$$p))/$$t seeds -- logs in $(LOGDIR)"; \
	    echo 1 > $(LOGDIR)/.status; fi; \
	} | tee $(SUMFILE); \
	exit $$(cat $(LOGDIR)/.status)

cov:
	cd $(ROOT) && vcover merge $(COVDIR)/merged.ucdb $(COVDIR)/run_*.ucdb && \
	  vcover report -details -html -htmldir docs/coverage $(COVDIR)/merged.ucdb && \
	  vcover report -details $(COVDIR)/merged.ucdb

clean:
	cd $(ROOT) && rm -rf build transcript vsim.wlf vsim.dbg* qwave.db *.db *.log \
	  sysinfo.log visualizer*.ses* .visualizer
