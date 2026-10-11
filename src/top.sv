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
    inout wire [NumGPIOS-1:0] gpio_io
);

    // ------------------------------------------------------------------------
    // System controller
    // ------------------------------------------------------------------------

    logic [7:0] data_out;
    logic       data_valid;

    // Boot status
    logic boot_finished;

    // Number of received words, saturating at 511
    logic [8:0] word_count;
    logic       imem_load;

    // Error output
    logic error;

    SC u_SC (
        .clk           (clk),
        .rst_ni        (rst_ni),
        .rx            (rx),
        .tx            (tx),
        .data_out      (data_out),
        .data_valid    (data_valid),
        .boot_finished (boot_finished),
        .word_count    (word_count),
        .error         (error),
        .imem_load     (imem_load)
    );

    // ------------------------------------------------------------------------
    // GPIO outputs
    // ------------------------------------------------------------------------
    // Drive all GPIO pins to logic 1.
    // These pins are independent of the internal SC signals.


    // ------------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------------
    
    FSM uFSM (
        .clk           (clk),
        .rst_ni        (rst_ni),
        .gpio_io       (gpio_io),

        // Boot
        .data_out      (data_out),
        .data_valid    (data_valid),
        .boot_finished (boot_finished),
        .word_count    (word_count),
        .imem_load     (imem_load)
    );
    

endmodule