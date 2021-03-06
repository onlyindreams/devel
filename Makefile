#
# Makefile of PG-Strom
#
PG_CONFIG=pg_config
PG_VERSION_NUM=$(shell $(PG_CONFIG) --version | awk '{print $$NF}'	\
	| sed -e 's/\./ /g' -e 's/[A-Za-z].*$$//g'			\
	| awk '{printf "%d%02d%02d", $$1, $$2, (NF >=3) ? $$3 : 0}')
#
# Definition of PG-Strom Extension
#
EXTENSION = pg_strom
ifeq ($(shell test $(PG_VERSION_NUM) -ge 90600; echo $??),0)
DATA = src/pg_strom--1.0.sql
else
DATA = src/pg_strom--1.0.sql
endif

# Source file of CPU portion
STROM_OBJS = main.o codegen.o datastore.o aggfuncs.o \
		cuda_control.o cuda_program.o cuda_mmgr.o \
		gpuscan.o gpujoin.o gpupreagg.o gpusort.o

# Source file of GPU portion
CUDA_OBJS = cuda_common.o \
	cuda_gpuscan.o \
	cuda_gpujoin.o \
	cuda_gpupreagg.o \
	cuda_gpusort.o \
	cuda_mathlib.o \
	cuda_textlib.o \
	cuda_timelib.o \
	cuda_numeric.o
CUDA_SOURCES = $(addprefix src/,$(CUDA_OBJS:.o=.c))

# Header and Libraries of CUDA
CUDA_PATH_LIST := /usr/local/cuda /usr/local/cuda-*
CUDA_PATH := $(shell for x in $(CUDA_PATH_LIST);	\
	       do test -e "$$x/include/cuda.h" && echo $$x; done | head -1)
IPATH := $(CUDA_PATH)/include
LPATH := $(CUDA_PATH)/lib64

# Module definition
MODULE_big = pg_strom
OBJS =  $(addprefix src/,$(STROM_OBJS)) $(addprefix src/,$(CUDA_OBJS))

# Support utilities
SCRIPTS_built = src/gpuinfo

# Regression test options
REGRESS = --schedule=test/parallel_schedule
REGRESS_OPTS = --inputdir=test
ifdef TEMP_INSTANCE
	REGRESS_OPTS += --temp-instance=tmp_check
	ifndef CPUTEST 
		REGRESS_OPTS += --temp-config=test/enable.conf
	else
		REGRESS_OPTS += --temp-config=test/disable.conf
	endif
endif

PGSTROM_FLAGS := $(shell $(PG_CONFIG) --configure | \
  awk '/'--enable-debug'/ {print "-Wall -DPGSTROM_DEBUG=1"}')
PGSTROM_FLAGS += $(shell $(PG_CONFIG) --cflags | \
  sed -E 's/[ ]+/\n/g' | \
  awk 'BEGIN{ CCOPT="" } /^-O[0-9]$$/{ CCOPT=$$1 } END{ print CCOPT }')
PGSTROM_FLAGS += -DCMD_GPUINFO_PATH=\"$(shell $(PG_CONFIG) --bindir)/gpuinfo\"
PG_CPPFLAGS := $(PGSTROM_FLAGS) -I $(IPATH)
SHLIB_LINK := -L $(LPATH) -lnvrtc -lcuda

EXTRA_CLEAN := $(CUDA_SOURCES)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(CUDA_SOURCES): $(CUDA_SOURCES:.c=.h)
	@(echo "const char *pgstrom_$(@:src/%.c=%)_code ="; \
	  sed -e 's/\\/\\\\/g' -e 's/\t/\\t/g' -e 's/"/\\"/g' \
	      -e 's/^/  "/g' -e 's/$$/\\n"/g' < $*.h; \
	  echo ";") > $@

src/gpuinfo: src/gpuinfo.c
	$(CC) $(CFLAGS) src/gpuinfo.c $(PGSTROM_FLAGS) -I $(IPATH) -L $(LPATH) -lcuda -o $@$(X)
