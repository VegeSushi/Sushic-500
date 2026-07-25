module sushic500_top (
    input wire clk_27mhz,
    input wire reset_btn,
    
    // Video
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire hsync,
    output wire vsync,
    output wire hblank,
    output wire vblank,

    // Emulator Keyboard
    input wire [7:0] emu_kbd_data,
    input wire       emu_kbd_ready
);

    wire clk_1mhz  = clk_27mhz;  
    
    wire [15:0] cpu_addr;
    wire [7:0]  cpu_data_out;
    reg  [7:0]  cpu_data_in;
    wire        cpu_we; 

    wire [7:0] ram_data_out;
    wire [7:0] rom_data_out;
    wire [7:0] cart_data_out;

    wire cs_ram  = (cpu_addr < 16'h8000);                      // 0x0000 - 0x7FFF
    wire cs_cart = (cpu_addr >= 16'h8000 && cpu_addr < 16'hC000); // 0x8000 - 0xBFFF
    wire cs_kbd  = (cpu_addr == 16'hC002 || cpu_addr == 16'hC003); // 0xC002 - 0xC003
    wire cs_rom  = (cpu_addr >= 16'hD000);                     // 0xD000 - 0xFFFF

    always @(*) begin
        if (cs_ram)           cpu_data_in = ram_data_out;
        else if (cs_cart)     cpu_data_in = cart_data_out;
        else if (cs_rom)      cpu_data_in = rom_data_out;
        else if (cpu_addr == 16'hC002) cpu_data_in = emu_kbd_data;
        else if (cpu_addr == 16'hC003) cpu_data_in = {7'b0, emu_kbd_ready};
        else                  cpu_data_in = 8'hEA; // NOP
    end

    cpu main_cpu (
        .clk(clk_1mhz), .reset(~reset_btn),
        .AB(cpu_addr), .DI(cpu_data_in), .DO(cpu_data_out), .WE(cpu_we),
        .IRQ(1'b0), .NMI(1'b0), .RDY(1'b1)
    );

    // --- Video System ---
    wire [12:0] vdp_addr;
    wire [7:0]  vdp_data;
    
    sys_ram ram (
        .clk(clk_1mhz),
        .we_a(cs_ram & cpu_we), .addr_a(cpu_addr[14:0]), .din_a(cpu_data_out), .dout_a(ram_data_out),
        .addr_b(vdp_addr), .dout_b(vdp_data)
    );

    wire [10:0] char_a;
    wire [7:0]  char_d_o;

    // MC6847 instantiated with ALL pins explicitly mapped
    mc6847 vdp (
        .clk(clk_27mhz),
        .clk_ena(1'b1),        
        .reset(~reset_btn),
        
        .da0(),                // Unused LSB address
        .videoaddr(vdp_addr),  
        .dd(vdp_data),
        
        // Sync outputs
        .hsync(hsync),
        .vsync(vsync),
        .hs_n(),               // Unused active-low sync
        .fs_n(),               // Unused active-low sync
        .hblank(hblank),
        .vblank(vblank),
        
        // Direct RGB outputs
        .red(vga_r),
        .green(vga_g),
        .blue(vga_b),
        .cvbs(),               // Unused composite signal
        
        // Mode Selectors
        .an_g(1'b0),           
        .an_s(1'b0),           
        .intn_ext(1'b0),       
        .inv(1'b0),
        .css(1'b0),
        .gm(3'b000),
        
        // Artifacting & Background (Tie off to disable)
        .artifact_en(1'b0),
        .artifact_set(1'b0),
        .artifact_phase(1'b0),
        .black_backgnd(1'b0),
        
        // External Font ROM Interface
        .char_a(char_a),
        .char_d_o(char_d_o)
    );

    char_rom font (.clk(clk_27mhz), .addr(char_a), .dout(char_d_o));

    cart_rom cart (.clk(clk_1mhz), .addr(cpu_addr - 16'h8000), .dout(cart_data_out));
    sys_rom rom (.clk(clk_1mhz), .addr(cpu_addr - 16'hD000), .dout(rom_data_out));

endmodule