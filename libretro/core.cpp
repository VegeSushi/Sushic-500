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
static std::string save_dir;

void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { }
void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

static void keyboard_cb(bool down, unsigned keycode, uint32_t character, uint16_t key_modifiers) {
    if (!top) return;

    if (down) {
        uint8_t key = 0;

        if (keycode == RETROK_RETURN) {
            key = 0x0D;
        } else if (keycode == RETROK_BACKSPACE) {
            key = 0x08;
        } else if (character > 0 && character < 128) {
            key = character;
        } else if (keycode > 0 && keycode < 128) {
            key = keycode;
        }

        if (key >= 'a' && key <= 'z') key -= 32;

        if (key != 0) {
            top->emu_kbd_data = key;
            top->emu_kbd_ready = 1;
        }
    } else {
        top->emu_kbd_ready = 0;
    }
}

void retro_set_environment(retro_environment_t cb) { 
    environ_cb = cb; 
    
    struct retro_log_callback log;
    if (cb(RETRO_ENVIRONMENT_GET_LOG_INTERFACE, &log)) {
        log_cb = log.log;
    }

    const char* sys_dir = nullptr;
    if (cb(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, &sys_dir) && sys_dir) {
        system_dir = sys_dir;
    }

    const char* s_dir = nullptr;
    if (cb(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY, &s_dir) && s_dir) {
        save_dir = s_dir;
    } else {
        save_dir = system_dir; // Fallback if frontend doesn't support save dirs
    }

    bool no_rom = true;
    cb(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_rom);

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
    info->valid_extensions = "bin"; 
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

bool load_cartridge(const char* filepath, const std::string& out_hex) {
    if (!filepath) return false;
    std::ifstream bin_file(filepath, std::ios::binary);
    if (!bin_file) return false;

    std::ofstream hex_file(out_hex);
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
    
    if (log_cb) log_cb(RETRO_LOG_INFO, "[Sushic-500] Loaded %d bytes into %s\n", count, out_hex.c_str());
    return true;
}

void write_empty_cartridge(const std::string& out_hex) {
    std::ofstream hex_file(out_hex);
    for (int i = 0; i < 16384; i++) hex_file << "EA\n";
    if (log_cb) log_cb(RETRO_LOG_INFO, "[Sushic-500] Generated empty %s\n", out_hex.c_str());
}

bool retro_load_game(const struct retro_game_info *info) {
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    if (!environ_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt)) return false;

    std::string bios_path = system_dir + "/bios.hex";
    std::string char_path = system_dir + "/charset.hex";
    std::string cart_path = save_dir + "/sushic500_cart.hex"; 

    if (info && info->path) {
        if (!load_cartridge(info->path, cart_path)) write_empty_cartridge(cart_path);
    } else {
        write_empty_cartridge(cart_path);
    }

    // Inject absolute paths directly into the Verilog initial blocks
    std::string arg_bios = "+bios_rom=" + bios_path;
    std::string arg_char = "+char_rom=" + char_path;
    std::string arg_cart = "+cart_rom=" + cart_path;

    const char* v_args[] = {
        "sushic500", 
        arg_bios.c_str(), 
        arg_char.c_str(), 
        arg_cart.c_str()
    };
    Verilated::commandArgs(4, v_args);

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
    input_poll_cb();
    
    bool frame_done = false;
    static int px = 0, py = 0;

    while (!frame_done) {
        if (sim_time > 10) top->reset_btn = 1;

        top->clk_27mhz = 1;
        top->eval();

        if (!top->hblank && !top->vblank) {
            if (px < TEX_W && py >= 0 && py < TEX_H) {
                uint8_t r = (top->vga_r << 4) | top->vga_r;
                uint8_t g = (top->vga_g << 4) | top->vga_g;
                uint8_t b = (top->vga_b << 4) | top->vga_b;
                framebuffer[(py * TEX_W) + px] = (r << 16) | (g << 8) | b;
            }
            px++;
        }

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