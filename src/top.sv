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
    input  wire [NumGPIOS-1:0] gpio_i,
    output wire [NumGPIOS-1:0] gpio_oe,
    output wire [NumGPIOS-1:0] gpio_o,
    input  wire       clk_in1,
    input  wire [1:0] error_modes_i,
    output wire [4:0] hspio_gpio_o
);
    
    // ------------------------------------------------------------------------
    // System controller
    // ------------------------------------------------------------------------
    
    logic [7:0]  data_out;
    logic       data_valid;

    // Boot status
    logic        boot_finished;

    // Number of received words, saturating at 511
    logic [8:0]  word_count;
    logic        imem_load;
    logic        dmem_load;

    // ISR traces
    logic [127:0] isr_regs;
    logic [7:0]   isr_push;

    // Error output
    logic        error;


    logic [7:0] gpio_o_in;
    logic [7:0] and_mask_s, or_mask_s, xor_mask_s;
    logic [7:0] mask_s;
    logic [7:0] rpc_trigger_s, current_rpc_s, level_s;
    logic [3:0] jitter_count_s;
    logic       en_error_injection_s;

    logic [4:0] error_inject_addr_s;
    logic [7:0] error_inject_data_s;
    logic error_inject_valid_s;

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
        .dmem_load (dmem_load),

        .isr_regs   (isr_regs),
        .isr_push   (isr_push),

        .error_inject_addr (error_inject_addr_s),
        .error_inject_data (error_inject_data_s),
        .error_inject_valid (error_inject_valid_s)

    );
    
    // ------------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------------
    FSM uFSM (
        .clk    (clk),
        .rst_ni (rst_ni),
        .gpio_i (gpio_i),
        .gpio_oe (gpio_oe),
        .gpio_o  (gpio_o_in),
        .clk_in1 (clk_in1),
        .hspio_gpio_o (hspio_gpio_o),
        
        // Boot 
        .data_out (data_out),
        .data_valid (data_valid),

        .boot_finished (boot_finished),
        .word_count (word_count),
        .imem_load (imem_load),
        .dmem_load (dmem_load),

        // Traces
        .isr_regs   (isr_regs),
        .isr_push   (isr_push),

        .and_mask_o (and_mask_s),
        .or_mask_o (or_mask_s),
        .xor_mask_o (xor_mask_s),

        .mask_o (mask_s),                  // bit-select for modes 01..11 (1 = affected)
        .rpc_trigger_o (rpc_trigger_s),    // RPC value that triggers injection
        .current_rpc_o (current_rpc_s),    // current RPC
        .level_o (level_s),                // forced value (mode 01), corruption probability /256 (mode 11)
        .jitter_count_o (jitter_count_s),  // delay in cycles (mode 10), burst length-1 (mode 11)
        .en_error_injection_o (en_error_injection_s),

        .error_inject_addr_i (error_inject_addr_s),
        .error_inject_data_i (error_inject_data_s),
        .error_inject_valid_i (error_inject_valid_s)
    );

    error_injection uerror_injection (

        .clk (clk),
        .rst_ni (rst_ni),
        .en_error_injection_i (en_error_injection_s),

        // Mode 00 masks: out = ((in & and_mask_i) | or_mask_i) ^ xor_mask_i
        .and_mask_i (and_mask_s),
        .or_mask_i (or_mask_s),
        .xor_mask_i (xor_mask_s),

        .mask_i (mask_s),                  // bit-select for modes 01..11 (1 = affected)
        .rpc_trigger_i (rpc_trigger_s),    // RPC value that triggers injection
        .current_rpc_i (current_rpc_s),    // current RPC
        .level_i (level_s),                // forced value (mode 01), corruption probability /256 (mode 11)
        .jitter_count_i (jitter_count_s),  // delay in cycles (mode 10), burst length-1 (mode 11)

        .modes_i (error_modes_i),
        .gpio_o_in (gpio_o_in),
        .gpio_o_out (gpio_o)
    );


endmodule