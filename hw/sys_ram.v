module sys_ram (
    input wire clk,
    
    // Port A: 6502 CPU (Read/Write, 32KB space)
    input wire we_a,
    input wire [14:0] addr_a,
    input wire [7:0] din_a,
    output reg [7:0] dout_a,
    
    // Port B: MC6847 VDP (Read Only, 8KB space)
    input wire [12:0] addr_b,
    output reg [7:0] dout_b
);
    reg [7:0] ram [0:32767];

    always @(posedge clk) begin
        if (we_a) ram[addr_a] <= din_a;
        dout_a <= ram[addr_a];
    end

    // The VDP constantly reads the screen data. 
    // We add an offset of 0x0400 (1024) so the screen buffer starts 
    // safely AFTER the 6502's Zero Page (0x00) and Stack (0x0100).
    always @(posedge clk) begin
        dout_b <= ram[addr_b + 15'h0400]; 
    end
endmodule