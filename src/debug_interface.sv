module debug_interface #(
    parameter int DATA_WIDTH = 256,
    parameter int ADDR_WIDTH = 8
)(
    input  logic [DATA_WIDTH-1:0] debug_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    output logic                  debug_o
);

    always_comb begin
        debug_o = debug_i[addr_i];
    end

endmodule
