module top #(
    parameter int unsigned NumFSM   = 1,
    parameter int unsigned NumGPIOS = 8
) (
    // Clock and reset
    input  logic clk,
    input  logic rst_ni,

    // UART communication (SW loader and debugger)
    input  logic rx,
    output logic tx,

    // I/Os
    inout wire [NumGPIOS-1:0] gpio_io,
    input  wire [5:0] hspio_gpio_i,
    output wire [5:0] hspio_gpio_o
);

    // ------------------------------------------------------------------------
    // System controller
    // ------------------------------------------------------------------------

    logic [7:0] data_out;
    logic       data_valid;

    // Boot status
    logic boot_finished;

    // Number of received words, saturating at 511
    logic [8:0]  word_count;
    logic        imem_load;
    logic        dmem_load;

    // Error output
    logic error;

    SC u_SC (
        .clk   (clk),
        .rst_ni(rst_ni),
        .rx (rx),
        .tx (tx),
        .data_out (data_out),
        .data_valid (data_valid),

        .boot_finished (boot_finished),
        .word_count (word_count),

        .error (error),

        .imem_load (imem_load),
        .dmem_load (dmem_load)
    );

    // ------------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------------
    
    FSM uFSM (
        .clk    (clk),
        .rst_ni (rst_ni),
        .gpio_io(gpio_io),
        .hspio_gpio_i (hspio_gpio_i),
        .hspio_gpio_o (hspio_gpio_o),

        // Boot
        .data_out (data_out),
        .data_valid (data_valid),

        .boot_finished (boot_finished),
        .word_count (word_count),
        .imem_load (imem_load),
        .dmem_load (dmem_load)
    );
    

endmodule