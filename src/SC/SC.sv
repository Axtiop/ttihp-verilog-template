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
    output logic        dmem_load
);

    // ============================================================
    // Commands
    // ============================================================

    localparam logic [7:0] SOF      = 8'hF0;
    localparam logic [7:0] EOB      = 8'h0F;
    localparam logic [7:0] STARTCMD = 8'h81;
    localparam logic [7:0] STOPCMD  = 8'h11;

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
        .rst_ni      (rst_ni),
        .rx         (rx_2r),
        .tx         (tx),

        .uart_data   (uart_data),
        .uart_data_valid (uart_data_valid)
    );
    

    // Temporary assignments until UART is implemented.
    //
    // Remove these when the uart module is instantiated.
    //assign tx              = 1'b1;


    // ============================================================
    // State machine
    // ============================================================
    logic first_after_SOF;
    typedef enum logic [2:0] {
        ST_WAIT_BOOT,       // Waiting for SOF
        ST_BOOT,            // Receiving boot data
        ST_WAIT_START,      // EOB received, waiting for STARTCMD
        ST_RUNNING,         // Boot finished, application running
        ST_STOPPED,          // STOPCMD received
        ST_ERROR,
        ST_WAIT_EOB
    } state_t;

    state_t state, next_state;

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
                        // STARTCMD simply gets us out of stopped
                        // state and back into running.
                        next_state = ST_RUNNING;
                    end
                    else begin
                        next_state = state;
                    end

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

        end
        else begin

            state <= next_state;

            // data_valid is a one-clock pulse
            data_valid <= 1'b0;


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

                    end


                    // =================================================
                    // Application running
                    // =================================================
                    ST_RUNNING: begin

                        if (uart_data == STOPCMD) begin
                            boot_finished <= 1'b0;
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

                    end


                    default: begin
                        // Nothing
                    end

                endcase
            end
        end
    end

endmodule