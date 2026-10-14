# AXI4 -> AHB-Lite bridge : Vivado xsim flow (native Windows, cmd.exe shell)
# Run from the repo root:  mingw32-make -C sim/vivado run
# Needs GNU make for Windows (e.g. MSYS2 ucrt64 mingw32-make) and Vivado's bin
# directory on PATH, or VIVADO_BIN set to it.

SHELL := cmd.exe

# Run knobs, overridable:  make run SEED=42 N_TRANS=5000
SEED       ?= 1
TEST       ?= ahb_base_test
TIMEOUT_NS ?= 100000
N_TRANS    ?= 1000
N          ?= 10

ifdef VIVADO_BIN
export PATH := $(VIVADO_BIN);$(PATH)
endif

BUILD := ../../build/xsim
SNAP  := tb_snap
TOP   := tb_top

# Same compile order as sim/tb.f; paths made relative to $(BUILD)
SRCS := $(addprefix ../../,$(strip $(file < ../tb.f)))

.PHONY: all compile elab run gui regress clean

all: run

compile:
	@if not exist "$(BUILD)" mkdir "$(BUILD)"
	cd $(BUILD) && xvlog -sv -L uvm $(SRCS) -log xvlog.log

elab: compile
	cd $(BUILD) && xelab $(TOP) -s $(SNAP) -L uvm -debug typical -timescale 1ns/1ps -generic_top "TIMEOUT_NS=$(TIMEOUT_NS)" -generic_top "N_TRANS=$(N_TRANS)" -log xelab.log

# One batch run. Fails if the log lacks "TEST DONE" or has UVM/xsim errors.
run: elab
	@$(MAKE) --no-print-directory run_only SEED=$(SEED)

run_only:
	@cd $(BUILD) && xsim $(SNAP) -runall -testplusarg "UVM_TESTNAME=$(TEST)" -sv_seed $(SEED) -wdb run_$(SEED).wdb -log xsim_$(SEED).log > nul
	@cd $(BUILD) && findstr /C:"TEST DONE" xsim_$(SEED).log > nul || (echo seed $(SEED) FAIL: did not finish & exit 1)
	@cd $(BUILD) && findstr /R /C:"^UVM_ERROR .*@" /C:"^UVM_FATAL .*@" /C:"^Error:" /C:"^Fatal:" xsim_$(SEED).log > nul && (echo seed $(SEED) FAIL: errors in log & exit 1) || echo seed $(SEED) PASS

gui: elab
	cd $(BUILD) && xsim $(SNAP) -gui -testplusarg "UVM_TESTNAME=$(TEST)" -sv_seed $(SEED)

# Elaborate once, then N seeds. Usage: make regress N=50
regress: elab
	@set FAILS=0& for /L %%s in (1,1,$(N)) do @$(MAKE) --no-print-directory run_only SEED=%%s || set /a FAILS+=1
	@echo regress done: see seed lines above

clean:
	@if exist "$(BUILD)" rmdir /s /q "$(BUILD)"
