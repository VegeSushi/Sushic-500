module cart_rom (
    input wire clk,
    input wire [13:0] addr,
    output reg [7:0] dout
);
    reg [7:0] rom [0:16383];
    string file_path;
    
    initial begin
        if (!$value$plusargs("cart_rom=%s", file_path)) begin
            file_path = "cart.hex";
        end
        $readmemh(file_path, rom);
    end
    
    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule