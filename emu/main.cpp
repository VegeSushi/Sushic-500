#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstdio>
#include <string>
#include <cstring>
#include <SDL2/SDL.h>
#include "Vsushic500_top.h"
#include "verilated.h"

#if defined(_WIN32)
  #include <windows.h>
  #include <commdlg.h>
#endif

// MC6847 NTSC Approximate Resolution
const int TEX_W = 320;   // or keep 320, negligible
const int TEX_H = 490;

bool load_cartridge(const std::string& filepath) {
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
    return true;
}

void write_empty_cartridge() {
    std::ofstream hex_file("cart.hex");
    for (int i = 0; i < 16384; i++) hex_file << "EA\n";
}

// ---------------------------------------------------------------------
// Native "attach cartridge" file picker. No extra dependencies: uses the
// OS-provided dialog (Win32 common dialog, macOS `osascript`, Linux
// `zenity`/`kdialog`). Returns an empty string if nothing was chosen.
// ---------------------------------------------------------------------
#if defined(_WIN32)
std::string open_file_dialog() {
    char filename[MAX_PATH] = "";
    OPENFILENAMEA ofn = {};
    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = "Cartridge Images (*.bin)\0*.bin\0All Files (*.*)\0*.*\0";
    ofn.lpstrFile = filename;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = "Attach Cartridge";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (GetOpenFileNameA(&ofn)) return std::string(filename);
    return "";
}
#elif defined(__APPLE__)
std::string open_file_dialog() {
    FILE* f = popen(
        "osascript -e 'POSIX path of (choose file with prompt \"Attach Cartridge\")' 2>/dev/null",
        "r");
    if (!f) return "";
    char buf[4096] = {0};
    std::string result;
    if (fgets(buf, sizeof(buf), f)) result = buf;
    pclose(f);
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        result.pop_back();
    return result;
}
#else
std::string open_file_dialog() {
    // Try zenity first, fall back to kdialog.
    FILE* f = popen(
        "zenity --file-selection --title='Attach Cartridge' 2>/dev/null || "
        "kdialog --getopenfilename . 2>/dev/null",
        "r");
    if (!f) return "";
    char buf[4096] = {0};
    std::string result;
    if (fgets(buf, sizeof(buf), f)) result = buf;
    pclose(f);
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        result.pop_back();
    return result;
}
#endif

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::string cart_path;
    if (argc > 1) cart_path = argv[1];

    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);

    // Window remains 640x480, but texture matches vintage hardware
    SDL_Window* window = SDL_CreateWindow("Sushic-500 Emulator",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 640, 480, SDL_WINDOW_RESIZABLE);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);

    // Use the native resolution for the pixel buffer
    SDL_Texture* texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, TEX_W, TEX_H);
    uint32_t* framebuffer = new uint32_t[TEX_W * TEX_H];

    bool quit = false;

    // Outer loop: each pass = one "power cycle" of the machine with the
    // cartridge currently selected. Re-entering it is what performs the
    // cartridge swap + auto-reset.
    while (!quit) {
        if (!cart_path.empty()) {
            std::cout << "Sushic-500 loading cartridge: " << cart_path << "\n";
            if (!load_cartridge(cart_path)) {
                std::cerr << "Failed to load " << cart_path << ", booting empty.\n";
                write_empty_cartridge();
                cart_path.clear();
            }
        } else {
            std::cout << "Sushic-500 booted with empty cartridge slot.\n";
            write_empty_cartridge();
        }

        // Fresh Verilated model: its constructor runs the module's initial
        // blocks, which is what re-reads build/cart.hex via $readmemh.
        Vsushic500_top* top = new Vsushic500_top;

        int px = 0, py = 0;
        uint8_t prev_hsync = 0, prev_vsync = 0, prev_vblank = 1;
        vluint64_t sim_time = 0;

        top->reset_btn = 0;
        top->clk_27mhz = 0;
        top->emu_kbd_ready = 0;

        memset(framebuffer, 0, TEX_W * TEX_H * sizeof(uint32_t));

        bool swap_cartridge = false;
        SDL_Event e;

        while (!quit && !swap_cartridge && !Verilated::gotFinish()) {

            // Poll SDL events every 50k ticks to keep simulation fast
            if (sim_time % 50000 == 0) {
                while (SDL_PollEvent(&e)) {
                    if (e.type == SDL_QUIT) quit = true;
                    if (e.type == SDL_KEYDOWN) {
                        if (e.key.keysym.sym == SDLK_BACKQUOTE) {
                            // '`' pressed: open the file picker to attach a
                            // new cartridge. Selecting a file tears down and
                            // rebuilds the model above, which is an implicit
                            // full reset with the new cartridge inserted.
                            std::string picked = open_file_dialog();
                            if (!picked.empty()) {
                                cart_path = picked;
                                swap_cartridge = true;
                                continue;
                            }
                        }

                        char key = e.key.keysym.sym;
                        if (key >= 'a' && key <= 'z') key -= 32;
                        if (e.key.keysym.sym == SDLK_RETURN) key = 0x0D;
                        if (e.key.keysym.sym == SDLK_BACKSPACE) key = 0x08;

                        top->emu_kbd_data = key;
                        top->emu_kbd_ready = 1;
                    } else if (e.type == SDL_KEYUP) {
                        top->emu_kbd_ready = 0;
                    }
                }
            }

            if (swap_cartridge) break;

            if (sim_time > 10) top->reset_btn = 1;

            top->clk_27mhz = 1;
            top->eval();

            // 1. Plot Pixels (active display = not in hblank/vblank)
            if (!top->hblank && !top->vblank) {
                if (px < TEX_W && py >= 0 && py < TEX_H) {
                    uint8_t r = (top->vga_r << 4) | top->vga_r;
                    uint8_t g = (top->vga_g << 4) | top->vga_g;
                    uint8_t b = (top->vga_b << 4) | top->vga_b;

                    framebuffer[(py * TEX_W) + px] = (0xFF000000 | (r << 16) | (g << 8) | b);
                }
                px++;
            }

            // 2. Handle Sync Pulses
            if (top->hsync == 1 && prev_hsync == 0) {
                px = 0;
                py++;
            }

            // Reset py exactly when active video starts (vblank falling edge),
            // not from a guessed vsync-to-active-video line offset.
            if (top->vblank == 0 && prev_vblank == 1) {
                py = 0;
            }

            if (top->vsync == 1 && prev_vsync == 0) {
                SDL_UpdateTexture(texture, NULL, framebuffer, TEX_W * sizeof(uint32_t));
                SDL_RenderClear(renderer);
                SDL_RenderCopy(renderer, texture, NULL, NULL);
                SDL_RenderPresent(renderer);
                memset(framebuffer, 0, TEX_W * TEX_H * sizeof(uint32_t));
            }

            prev_hsync  = top->hsync;
            prev_vsync  = top->vsync;
            prev_vblank = top->vblank;

            top->clk_27mhz = 0;
            top->eval();
            sim_time++;
        }

        delete top;
        // Loop back around if a cartridge swap was requested; otherwise quit.
    }

    delete[] framebuffer;
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}