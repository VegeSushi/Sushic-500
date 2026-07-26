CA65 = ca65
LD65 = ld65
VERILATOR = verilator
PYTHON = python3

BUILD_DIR = build
SW_DIR = sw
HW_DIR = hw
EMU_DIR = emu
EXT_DIR = ext

VERILOG_SRCS = $(HW_DIR)/sushic500_top.v \
               $(HW_DIR)/sys_ram.v \
               $(HW_DIR)/sys_rom.v \
               $(HW_DIR)/cart_rom.v \
               $(HW_DIR)/char_rom.v \
               $(HW_DIR)/mc6847.v \
               $(EXT_DIR)/verilog-6502/cpu.v \
               $(EXT_DIR)/verilog-6502/ALU.v

VERILATOR_ROOT ?= /usr/share/verilator

.PHONY: all rom cart charset emu clean libretro

all: rom cart charset emu libretro

# --- BIOS ROM ---
rom: $(BUILD_DIR)/bios.hex

$(BUILD_DIR)/bios.o: $(SW_DIR)/bios.asm
	@mkdir -p $(BUILD_DIR)
	$(CA65) -t none $< -o $@

$(BUILD_DIR)/bios.bin: $(BUILD_DIR)/bios.o $(SW_DIR)/link.ld
	$(LD65) -C $(SW_DIR)/link.ld $< -o $@

$(BUILD_DIR)/bios.hex: $(BUILD_DIR)/bios.bin
	xxd -p -c 1 $< > $@

# --- CARTRIDGE ---
cart: $(BUILD_DIR)/hello.bin

$(BUILD_DIR)/hello_cart.o: $(SW_DIR)/hello_cart.asm
	@mkdir -p $(BUILD_DIR)
	$(CA65) -t none $< -o $@

$(BUILD_DIR)/hello.bin: $(BUILD_DIR)/hello_cart.o $(SW_DIR)/cart_link.ld
	$(LD65) -C $(SW_DIR)/cart_link.ld $< -o $@

# --- CHARACTER ROM ---
charset: $(BUILD_DIR)/charset.hex

$(BUILD_DIR)/charset.hex: $(SW_DIR)/gen_charset.py
	@mkdir -p $(BUILD_DIR)
	$(PYTHON) $(SW_DIR)/gen_charset.py

# --- EMULATOR ---
emu: $(BUILD_DIR)/bios.hex $(BUILD_DIR)/charset.hex
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) -cc --exe --build -j 4 \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		-Wno-CASEX -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
		-Mdir $(BUILD_DIR)/verilator \
		-I$(HW_DIR) -I$(EXT_DIR)/verilog-6502 \
		--top-module sushic500_top \
		$(EMU_DIR)/main.cpp $(VERILOG_SRCS) \
		-CFLAGS "$$(sdl2-config --cflags)" \
		-LDFLAGS "$$(sdl2-config --libs)"
	
	cp $(BUILD_DIR)/verilator/Vsushic500_top $(BUILD_DIR)/sushic500-emu

# --- LIBRETRO CORE ---
libretro: $(BUILD_DIR)/bios.hex $(BUILD_DIR)/charset.hex
	@mkdir -p $(BUILD_DIR)/libretro_obj
	
	# Fetch the libretro API header
	curl -sL https://raw.githubusercontent.com/libretro/RetroArch/master/libretro-common/include/libretro.h -o $(BUILD_DIR)/libretro.h
	
	# Generate C++ model and pass -fPIC so it can be linked into a shared object
	$(VERILATOR) -cc --build -j 4 \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		-Wno-CASEX -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
		-CFLAGS "-fPIC" \
		-Mdir $(BUILD_DIR)/libretro_obj \
		-I$(HW_DIR) -I$(EXT_DIR)/verilog-6502 \
		--top-module sushic500_top $(VERILOG_SRCS)
		
	# Compile as a dynamic shared library for RetroArch (.so)
	$(CXX) -fPIC -shared -o $(BUILD_DIR)/sushic500_libretro.so \
		libretro/core.cpp \
		$(BUILD_DIR)/libretro_obj/Vsushic500_top__ALL.a \
		$(VERILATOR_ROOT)/include/verilated.cpp \
		$(VERILATOR_ROOT)/include/verilated_threads.cpp \
		-I$(BUILD_DIR) -I$(BUILD_DIR)/libretro_obj \
		-I$(HW_DIR) -I$(EXT_DIR)/verilog-6502 \
		-I$(VERILATOR_ROOT)/include -I$(VERILATOR_ROOT)/include/vltstd

clean:
	rm -rf $(BUILD_DIR)