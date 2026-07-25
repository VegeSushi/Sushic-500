module cart_rom (
    input wire clk,
    input wire [13:0] addr,
    output reg [7:0] dout
);
    reg [7:0] rom [0:16383];
    
    initial begin
        $readmemh("build/cart.hex", rom);
    end
    
    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule