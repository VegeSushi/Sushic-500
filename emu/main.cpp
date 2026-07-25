#include <iostream>
#include <fstream>
#include <iomanip>
#include <SDL2/SDL.h>
#include "Vsushic500_top.h"
#include "verilated.h"

// MC6847 NTSC Approximate Resolution
const int TEX_W = 320;   // or keep 320, negligible
const int TEX_H = 490; 

bool load_cartridge(const char* filepath) {
    std::ifstream bin_file(filepath, std::ios::binary);
    if (!bin_file) return false;

    std::ofstream hex_file("build/cart.hex");
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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc > 1) {
        std::cout << "Sushic-500 loading cartridge: " << argv[1] << "\n";
        if (!load_cartridge(argv[1])) {
            std::cerr << "Failed to load " << argv[1] << "\n";
            return 1;
        }
    } else {
        std::cout << "Sushic-500 booted with empty cartridge slot.\n";
        std::ofstream hex_file("build/cart.hex");
        for (int i = 0; i < 16384; i++) hex_file << "EA\n";
    }

    Vsushic500_top* top = new Vsushic500_top;
    
    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
    
    // Window remains 640x480, but texture matches vintage hardware
    SDL_Window* window = SDL_CreateWindow("Sushic-500 Emulator", 
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 640, 480, SDL_WINDOW_RESIZABLE);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    
    // Use the native resolution for the pixel buffer
    SDL_Texture* texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, TEX_W, TEX_H);
    uint32_t* framebuffer = new uint32_t[TEX_W * TEX_H];
    
    // Lines between vsync rising edge (mc6847.v: V2_FRONT_PORCH = 2) and the
    // start of the visible border/video area (mc6847.v: V2_BACK_PORCH = 16).
    // vsync and hsync share the same line-counter pipeline, so resetting off
    // vsync (rather than vblank, which lags by a line or so) keeps the count
    // accurate. If the picture still drifts a line or two, nudge PY_FUDGE.
    const int PY_START_OFFSET = 16 - 2; // = 14
    const int PY_FUDGE = 0;             // adjust by +/-1 if still off slightly

    int px = 0, py = 0;
    uint8_t prev_hsync = 0, prev_vsync = 0, prev_vblank = 1;

    top->reset_btn = 0; 
    top->clk_27mhz = 0; 
    top->emu_kbd_ready = 0;

    SDL_Event e;
    bool quit = false;
    vluint64_t sim_time = 0;

    while (!quit && !Verilated::gotFinish()) {
        
        // Poll SDL events every 50k ticks to keep simulation fast
        if (sim_time % 50000 == 0) {
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) quit = true;
                if (e.type == SDL_KEYDOWN) {
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

        if (sim_time > 10) top->reset_btn = 1; 
        
        top->clk_27mhz = 1; 
        top->eval();

        // 1. Plot Pixels (active display = not in hblank/vblank)
        if (!top->hblank && !top->vblank) {
            if (px < TEX_W && py >= 0 && py < TEX_H) {
                // The Verilog module outputs 4-bit color (0-15).
                // Multiply by 17 (<< 4 | bitwise OR) to scale to 8-bit color (0-255).
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

    delete[] framebuffer;
    delete top;
    SDL_Quit();
    return 0;
}