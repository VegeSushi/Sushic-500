#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <string>
#include "libretro.h"
#include "Vsushic500_top.h"
#include "verilated.h"

// MC6847 NTSC Approximate Resolution from main.cpp
const int TEX_W = 320;
const int TEX_H = 490;

static retro_video_refresh_t video_cb;
static retro_environment_t environ_cb;
static retro_input_poll_t input_poll_cb;
static retro_input_state_t input_state_cb;
static retro_log_printf_t log_cb = nullptr;

static Vsushic500_top* top = nullptr;
static uint32_t* framebuffer = nullptr;
static vluint64_t sim_time = 0;
static uint8_t prev_hsync = 0, prev_vsync = 0, prev_vblank = 1;

static std::string system_dir;

void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { }
void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

static void keyboard_cb(bool down, unsigned keycode, uint32_t character, uint16_t key_modifiers) {
    // Prevent inputs from crashing the core if the model isn't instantiated yet
    if (!top) return;

    if (down) {
        uint8_t key = 0;

        if (keycode == RETROK_RETURN) {
            key = 0x0D;
        } else if (keycode == RETROK_BACKSPACE) {
            key = 0x08;
        } else if (character > 0 && character < 128) {
            // Use the translated character if the frontend provides it
            key = character;
        } else if (keycode > 0 && keycode < 128) {
            // Fallback to the raw keycode for basic ASCII
            key = keycode;
        }

        // Convert lowercase to uppercase to match the hardware's expected input
        if (key >= 'a' && key <= 'z') {
            key -= 32;
        }

        if (key != 0) {
            top->emu_kbd_data = key;
            top->emu_kbd_ready = 1;
        }
    } else {
        // Drop the ready line on key release
        top->emu_kbd_ready = 0;
    }
}

void retro_set_environment(retro_environment_t cb) { 
    environ_cb = cb; 
    
    // Setup logging
    struct retro_log_callback log;
    if (cb(RETRO_ENVIRONMENT_GET_LOG_INTERFACE, &log)) {
        log_cb = log.log;
    }

    // Get the frontend's system (BIOS) directory
    const char* dir = nullptr;
    if (cb(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, &dir) && dir) {
        system_dir = dir;
    }

    // Tell RetroArch this core can run without loading a ROM
    bool no_rom = true;
    cb(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_rom);

    // Register the physical keyboard callback
    struct retro_keyboard_callback kbd;
    kbd.callback = keyboard_cb;
    cb(RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK, &kbd);
}

void retro_init() {
    framebuffer = new uint32_t[TEX_W * TEX_H];
}

void retro_deinit() {
    delete[] framebuffer;
    if (top) {
        delete top;
        top = nullptr;
    }
}

unsigned retro_api_version() { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
    info->library_name     = "Sushic-500";
    info->library_version  = "1.0";
    info->need_fullpath    = true;
    info->valid_extensions = "bin"; // Allows the frontend to pass .bin ROMs to the core
}

void retro_get_system_av_info(struct retro_system_av_info *info) {
    info->geometry.base_width   = TEX_W;
    info->geometry.base_height  = TEX_H;
    info->geometry.max_width    = TEX_W;
    info->geometry.max_height   = TEX_H;
    info->geometry.aspect_ratio = 4.0f / 3.0f;
    info->timing.fps            = 60.0;
    info->timing.sample_rate    = 0.0;
}

// Converts the raw .bin ROM provided by the frontend into the cart.hex expected by Verilator
bool load_cartridge(const char* filepath) {
    if (!filepath) return false;
    std::ifstream bin_file(filepath, std::ios::binary);
    if (!bin_file) return false;

    std::ofstream hex_file("cart.hex");
    char byte;
    int count = 0;

    while (bin_file.read(&byte, 1) && count < 16384) {
        hex_file << std::hex << std::setw(2) << std::setfill('0')
                 << (static_cast<int>(byte) & 0xFF) << "\n";
        count++;
    }
    while (count < 16384) {
        hex_file << "EA\n";
        count++;
    }
    
    if (log_cb) log_cb(RETRO_LOG_INFO, "[Sushic-500] Loaded %d bytes into cart.hex\n", count);
    return true;
}

void write_empty_cartridge() {
    std::ofstream hex_file("cart.hex");
    for (int i = 0; i < 16384; i++) hex_file << "EA\n";
    if (log_cb) log_cb(RETRO_LOG_INFO, "[Sushic-500] Generated empty cart.hex\n");
}

// Helper to pull hex system files from RetroArch's System folder into the CWD
void prepare_system_file(const char* filename) {
    if (system_dir.empty()) {
        if (log_cb) log_cb(RETRO_LOG_WARN, "[Sushic-500] System directory not found, cannot load %s\n", filename);
        return;
    }
    
    std::string src_path = system_dir + "/" + filename;
    std::ifstream src(src_path, std::ios::binary);
    
    if (src) {
        std::ofstream dst(filename, std::ios::binary);
        dst << src.rdbuf();
        if (log_cb) log_cb(RETRO_LOG_INFO, "[Sushic-500] Copied %s from system directory to CWD.\n", filename);
    } else {
        if (log_cb) log_cb(RETRO_LOG_ERROR, "[Sushic-500] Missing required system file: %s\n", src_path.c_str());
    }
}

bool retro_load_game(const struct retro_game_info *info) {
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    if (!environ_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt)) return false;

    // Pull bios.hex and charset.hex from the Libretro system directory so Verilator can find them
    prepare_system_file("bios.hex");
    prepare_system_file("charset.hex");

    // Load the .bin ROM into cart.hex
    if (info && info->path) {
        if (!load_cartridge(info->path)) write_empty_cartridge();
    } else {
        write_empty_cartridge();
    }

    top = new Vsushic500_top;
    top->reset_btn = 0;
    top->clk_27mhz = 0;
    top->emu_kbd_ready = 0;
    sim_time = 0;
    
    return true;
}

void retro_unload_game() {
    if (top) { delete top; top = nullptr; }
}

void retro_run() {
    // This polls inputs and triggers the keyboard_cb under the hood
    input_poll_cb();
    
    bool frame_done = false;
    static int px = 0, py = 0;

    while (!frame_done) {
        if (sim_time > 10) top->reset_btn = 1;

        top->clk_27mhz = 1;
        top->eval();

        // 1. Plot Pixels (active display = not in hblank/vblank)
        if (!top->hblank && !top->vblank) {
            if (px < TEX_W && py >= 0 && py < TEX_H) {
                uint8_t r = (top->vga_r << 4) | top->vga_r;
                uint8_t g = (top->vga_g << 4) | top->vga_g;
                uint8_t b = (top->vga_b << 4) | top->vga_b;
                framebuffer[(py * TEX_W) + px] = (r << 16) | (g << 8) | b;
            }
            px++;
        }

        // 2. Handle Sync Pulses
        if (top->hsync == 1 && prev_hsync == 0) { px = 0; py++; }
        if (top->vblank == 0 && prev_vblank == 1) { py = 0; }
        if (top->vsync == 1 && prev_vsync == 0) { frame_done = true; }

        prev_hsync  = top->hsync;
        prev_vsync  = top->vsync;
        prev_vblank = top->vblank;

        top->clk_27mhz = 0;
        top->eval();
        sim_time++;
    }

    video_cb(framebuffer, TEX_W, TEX_H, TEX_W * sizeof(uint32_t));
}

// Stubs
void retro_reset() { top->reset_btn = 0; sim_time = 0; }
size_t retro_serialize_size() { return 0; }
bool retro_serialize(void *data, size_t size) { return false; }
bool retro_unserialize(const void *data, size_t size) { return false; }
void retro_cheat_reset() {}
void retro_cheat_set(unsigned, bool, const char*) {}
bool retro_load_game_special(unsigned, const struct retro_game_info*, size_t) { return false; }
void retro_set_controller_port_device(unsigned, unsigned) {}
unsigned retro_get_region() { return RETRO_REGION_NTSC; }
void* retro_get_memory_data(unsigned) { return nullptr; }
size_t retro_get_memory_size(unsigned) { return 0; }