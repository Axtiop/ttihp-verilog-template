module SC (
    input  logic        clk,
    input  logic        rst_ni,

    // UART physical interface
    input  logic        rx,
    output logic        tx,

    // Data output
    output logic [7:0]  data_out,
    output logic       data_valid,

    // Boot status
    output logic        boot_finished,

    // Number of received words, saturating at 512
    output logic [8:0]  word_count,

    // Error output
    output logic        error,

    // boot state
    output logic        imem_load,
    output logic        dmem_load,

    // isr traces
    input logic [127:0] isr_regs,
    input logic [7:0]   isr_push,

    // Error injection interface
    output logic [4:0] error_inject_addr,
    output logic [7:0] error_inject_data,
    output logic       error_inject_valid,

    output logic [7:0] addr_debug_o
);

    // ============================================================
    // Commands
    // ============================================================

    localparam logic [7:0] SOF      = 8'hF0;
    localparam logic [7:0] EOB      = 8'h0F;
    localparam logic [7:0] STARTCMD = 8'h81;
    localparam logic [7:0] STOPCMD  = 8'h11;
    localparam logic [7:0] SETERROR = 8'hAA;
    localparam logic [7:0] SETDEBUG = 8'hAF;

    localparam logic [8:0] MAX_COUNT = 9'd511;

    // ============================================================
    // UART interface
    //
    // Replace this section with the actual UART module when
    // implemented.
    //
    // uart_data_valid should pulse for one clock when a byte has
    // been received.
    // ============================================================

    logic [7:0] uart_data;
    logic       uart_data_valid;
    logic [7:0] uart_data_out;
    logic       uart_data_out_valid;
    logic       tx_ongoing;

    logic rx_r;
    logic rx_2r;

    

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_r        <= 1'b1;
            rx_2r       <= 1'b1;
        end
        else begin
            rx_r <= rx;
            rx_2r <= rx_r;
        end
    end
    
    uart uart_inst (
        .clk        (clk),
        .rst_ni     (rst_ni),
        .rx         (rx_2r),
        .tx         (tx),

        .tx_ongoing    (tx_ongoing),
        .uart_data_out (uart_data_out),
        .uart_data_out_valid (uart_data_out_valid),

        .uart_data   (uart_data),
        .uart_data_valid (uart_data_valid)
    );

    tracer_fifo tracer_fifo_inst (
        .clk           (clk),
        .rst_ni        (rst_ni),
        .isr_regs      (isr_regs),
        .isr_push      (isr_push),
        .tx_ongoing    (tx_ongoing),
        .uart_data_out (uart_data_out),
        .uart_data_out_valid (uart_data_out_valid)
    );


    // ============================================================
    // State machine
    // ============================================================
    logic first_after_SOF;
    typedef enum logic [3:0] {
        ST_WAIT_BOOT,
        ST_BOOT,
        ST_WAIT_START,
        ST_RUNNING,
        ST_STOPPED,
        ST_ERROR,
        ST_WAIT_EOB,
        ST_SETERROR_ADDR,
        ST_SETERROR_DATA,
        ST_SETDEBUG_ADDR
    } state_t;

    state_t state, next_state, return_state;

    // TODO: the command send_error_injection data can be sent during ST_WAIT_START, ST_RUNNING, ST_STOPPED states
    // ============================================================
    // Next-state logic
    // ============================================================

 always_comb begin
        
        if (uart_data_valid) begin

            case (state)

                // ------------------------------------------------
                // Initial state
                // ------------------------------------------------
                ST_WAIT_BOOT: begin
                    if (uart_data == SOF) begin
                        next_state = ST_BOOT;
                    end
                    else begin
                        next_state = state;
                    end
                end


                // ------------------------------------------------
                // Boot data reception
                // ------------------------------------------------
                ST_BOOT: begin

                    if (word_count == 510 && imem_load == 0 && dmem_load == 0) begin
                        // End of boot block
                        next_state = ST_WAIT_EOB;
                    end
                    else begin
                        next_state = state;
                    end
                end

                // ------------------------------------------------
                // Boot data reception
                // ------------------------------------------------
                ST_WAIT_EOB: begin

                    if (uart_data == EOB) begin
                        // End of boot block
                        next_state = ST_WAIT_START;
                    end
                    else begin
                        next_state = ST_ERROR;
                    end
                end

                ST_ERROR: begin

                    if (uart_data == SOF) begin
                        next_state = ST_BOOT;
                    end
                    else begin
                        next_state = state;
                    end
                end

                // ------------------------------------------------
                // Boot data has ended.
                // Wait for STARTCMD.
                // ------------------------------------------------
                ST_WAIT_START: begin

                    if (uart_data == STARTCMD) begin
                        next_state = ST_RUNNING;
                    end
                    else if (uart_data == SOF) begin
                        // Optional: allow a new boot immediately
                        // without STARTCMD.
                        next_state = ST_BOOT;
                    end
                    else if (uart_data == SETERROR) begin 
                        next_state = ST_SETERROR_ADDR;
                    end 
                    else if (uart_data == SETDEBUG) begin
                        next_state = ST_SETDEBUG_ADDR;
                    end
                    else begin
                        next_state = state;
                    end
                end


                // ------------------------------------------------
                // Boot finished / application running
                // ------------------------------------------------
                ST_RUNNING: begin

                    if (uart_data == STOPCMD) begin
                        next_state = ST_STOPPED;
                    end
                    else if (uart_data == SETERROR) begin
                        next_state = ST_SETERROR_ADDR;
                    end
                    else if (uart_data == SETDEBUG) begin
                        next_state = ST_SETDEBUG_ADDR;
                    end
                    else begin
                        next_state = state;
                    end
                end


                // ------------------------------------------------
                // Stopped state
                // ------------------------------------------------
                ST_STOPPED: begin

                    if (uart_data == SOF) begin
                        next_state = ST_BOOT;
                    end
                    else if (uart_data == STARTCMD) begin
                        next_state = ST_RUNNING;
                    end
                    else if (uart_data == SETERROR) begin
                        next_state = ST_SETERROR_ADDR;
                    end
                    else if (uart_data == SETDEBUG) begin
                        next_state = ST_SETDEBUG_ADDR;
                    end
                    else begin
                        next_state = state;
                    end

                end

                ST_SETERROR_ADDR: begin
                    next_state = ST_SETERROR_DATA;
                end

                ST_SETERROR_DATA: begin
                    next_state = return_state;
                end

                ST_SETDEBUG_ADDR: begin
                    next_state = return_state;
                end

                default: begin
                    next_state = ST_WAIT_BOOT;
                end

            endcase
               
        end
        else begin 
            next_state = state;
        end 
    end
    // ============================================================
    // Sequential state / counter / outputs
    // ============================================================

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin

            state         <= ST_WAIT_BOOT;

            data_out      <= 8'h00;
            data_valid    <= 1'b0;

            first_after_SOF <= 1'b0;
            boot_finished <= 1'b0;
            word_count    <= 9'd0;

            error         <= 1'b0;

            imem_load     <= 1'b1;
            dmem_load     <= 1'b1;

            error_inject_addr  <= 5'b00000;
            error_inject_data  <= 8'h00;
            error_inject_valid <= 1'b0;

            return_state <= ST_WAIT_START;

            addr_debug_o <= 8'h00;

        end
        else begin

            state <= next_state;

            // data_valid is a one-clock pulse
            data_valid <= 1'b0;
            error_inject_valid <= 1'b0;

            if (uart_data_valid) begin

                case (state)

                    // =================================================
                    // Waiting for SOF
                    // =================================================
                    ST_WAIT_BOOT: begin

                        if (uart_data == SOF) begin
                            word_count <= 9'd0;
                            error      <= 1'b0;
                            first_after_SOF <= 1'b1;
                        end

                    end


                    // =================================================
                    // Receiving boot data
                    // =================================================
                    ST_BOOT: begin

                        // Forward received byte.
                        data_out   <= uart_data;
                        data_valid <= 1'b1;

                        // Saturating counter.
                        //
                        // Once 512 is reached, it remains at 512.
                        if (first_after_SOF) begin
                            first_after_SOF <= 1'b0;
                        end
                        else if (word_count < MAX_COUNT) begin
                            word_count <= word_count + 9'd1;
                        end
                        else begin
                            word_count <= 9'd0;
                            if(imem_load == 1'b0) begin
                                dmem_load <= 1'b0;
                            end else begin
                                imem_load <= 1'b0;
                            end
                            
                        end


                    end

                    ST_ERROR: begin
                        error      <= 1'b1;
                        word_count <= 9'd0;
                    end 


                    // =================================================
                    // Waiting for STARTCMD after EOB
                    // =================================================
                    ST_WAIT_START: begin

                        if (uart_data == STARTCMD) begin
                            boot_finished <= 1'b1;
                        end
                        else if (uart_data == SOF) begin
                            // New boot sequence.
                            word_count <= 9'd0;
                            error      <= 1'b0;
                        end
                        else if (uart_data == SETERROR) begin
                            return_state <= ST_WAIT_START;
                        end
                        else if (uart_data == SETDEBUG) begin
                            return_state <= ST_WAIT_START;
                        end

                    end


                    // =================================================
                    // Application running
                    // =================================================
                    ST_RUNNING: begin

                        if (uart_data == STOPCMD) begin
                            boot_finished <= 1'b0;
                        end
                        else if (uart_data == SETERROR) begin
                            return_state <= ST_RUNNING;
                        end
                        else if (uart_data == SETDEBUG) begin
                            return_state <= ST_RUNNING;
                        end

                    end


                    // =================================================
                    // Stopped
                    // =================================================
                    ST_STOPPED: begin

                        if (uart_data == SOF) begin
                            // Start a new boot.
                            word_count <= 9'd0;
                            error      <= 1'b0;
                        end
                        else if (uart_data == STARTCMD) begin
                            // Leave stopped state.
                            boot_finished <= 1'b1;
                        end
                        else if (uart_data == SETERROR) begin
                            return_state <= ST_STOPPED;
                        end
                        else if (uart_data == SETDEBUG) begin
                            return_state <= ST_STOPPED;
                        end

                    end

                    // Receive error injection address
                    ST_SETERROR_ADDR: begin
                        error_inject_addr <= uart_data[4:0];
                    end


                    // Receive error injection data
                    ST_SETERROR_DATA: begin
                        error_inject_data  <= uart_data;
                        error_inject_valid <= 1'b1;
                    end

                    ST_SETDEBUG_ADDR: begin
                        addr_debug_o <= uart_data[7:0];
                    end


                    default: begin
                        // Nothing
                    end

                endcase
            end
        end
    end

endmodule