module sys_rom (
    input wire clk,
    input wire [13:0] addr, 
    output reg [7:0] dout
);
    reg [7:0] rom [0:12287];
    initial $readmemh("bios.hex", rom);
    always @(posedge clk) dout <= rom[addr];
endmodule