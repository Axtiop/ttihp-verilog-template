module tracer_fifo #(
    parameter int         DEPTH = 4,       // entries per FIFO, power of 2, >= 2
    parameter logic [3:0] DELIM = 4'hA     // frame start marker in Byte0[7:4]
)(
    input  logic        clk,
    input  logic        rst_ni,

    // input data
    input  logic [127:0] isr_regs,
    input  logic [7:0]   isr_push,

    // output data
    input  logic         tx_ongoing,
    output logic [7:0]   uart_data_out,
    output logic         uart_data_out_valid
);

    localparam int NF = 8;
    localparam int AW = $clog2(DEPTH);

    // ------------------------------------------------------------------
    // Rising edge detection on isr_push
    // ------------------------------------------------------------------
    logic [NF-1:0] push_q, push_rise;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) push_q <= '0;
        else         push_q <= isr_push;
    end

    assign push_rise = isr_push & ~push_q;

    // ------------------------------------------------------------------
    // 8 small flip-flop based FIFOs (16-bit data + "loss after me" bit)
    // ------------------------------------------------------------------
    logic [15:0]  mem      [NF][DEPTH];
    logic         mem_lost [NF][DEPTH];   // data was dropped right after this entry
    logic [AW:0]  wptr     [NF];
    logic [AW:0]  rptr     [NF];
    logic [NF-1:0] empty, full, pop;

    for (genvar i = 0; i < NF; i++) begin : g_fifo
        assign empty[i] = (wptr[i] == rptr[i]);
        assign full[i]  = (wptr[i][AW-1:0] == rptr[i][AW-1:0]) &&
                          (wptr[i][AW]     != rptr[i][AW]);

        wire [AW-1:0] last_idx = wptr[i][AW-1:0] - 1'b1;   // newest entry

        always_ff @(posedge clk or negedge rst_ni) begin
            if (!rst_ni) begin
                wptr[i] <= '0;
                rptr[i] <= '0;
            end else begin
                if (push_rise[i] && !full[i]) wptr[i] <= wptr[i] + 1'b1;
                if (pop[i])                   rptr[i] <= rptr[i] + 1'b1;
            end
        end

        // Storage: no reset needed (saves area), validity is tracked by pointers
        always_ff @(posedge clk) begin
            if (push_rise[i]) begin
                if (!full[i]) begin
                    mem[i][wptr[i][AW-1:0]]      <= isr_regs[16*i +: 16];
                    mem_lost[i][wptr[i][AW-1:0]] <= 1'b0;
                end else begin
                    // FIFO full: new sample is dropped, remember the loss
                    mem_lost[i][last_idx] <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Round-robin selection: first non-empty FIFO after the last served one
    // ------------------------------------------------------------------
    logic [2:0] last_served;
    logic [2:0] sel;
    logic       found;

    always_comb begin
        found = 1'b0;
        sel   = last_served;
        for (int k = 1; k <= NF; k++) begin
            logic [2:0] idx;
            idx = last_served + 3'(k);          // wraps naturally mod 8
            if (!found && !empty[idx]) begin
                found = 1'b1;
                sel   = idx;
            end
        end
    end

    // ------------------------------------------------------------------
    // Frame sender
    //   Byte0 = {DELIM[3:0], lost, fifo_id[2:0]}
    //   Byte1 = data[15:8]
    //   Byte2 = data[7:0]
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE,       // pick next FIFO and latch a frame
        S_SEND,       // wait for UART free, pulse valid
        S_WAIT_BUSY,  // wait for UART to accept the byte (tx_ongoing rises)
        S_WAIT_DONE   // wait for UART to finish (tx_ongoing falls)
    } state_t;

    state_t     state;
    logic [1:0] byte_idx;
    logic [15:0] frame_data;
    logic        frame_lost;
    logic [2:0]  frame_id;

    // Pop the selected FIFO when a frame is latched
    always_comb begin
        pop = '0;
        if (state == S_IDLE && found) pop[sel] = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            state               <= S_IDLE;
            byte_idx            <= '0;
            last_served         <= 3'd7;   // so FIFO 0 gets first priority
            frame_data          <= '0;
            frame_lost          <= 1'b0;
            frame_id            <= '0;
            uart_data_out       <= '0;
            uart_data_out_valid <= 1'b0;
        end else begin
            uart_data_out_valid <= 1'b0;   // default: one-cycle pulse

            case (state)
                S_IDLE: begin
                    if (found) begin
                        frame_data  <= mem[sel][rptr[sel][AW-1:0]];
                        frame_lost  <= mem_lost[sel][rptr[sel][AW-1:0]];
                        frame_id    <= sel;
                        last_served <= sel;
                        byte_idx    <= '0;
                        state       <= S_SEND;
                    end
                end

                S_SEND: begin
                    if (!tx_ongoing) begin
                        case (byte_idx)
                            2'd0:    uart_data_out <= {DELIM, frame_lost, frame_id};
                            2'd1:    uart_data_out <= frame_data[15:8];
                            default: uart_data_out <= frame_data[7:0];
                        endcase
                        uart_data_out_valid <= 1'b1;
                        state               <= S_WAIT_BUSY;
                    end
                end

                S_WAIT_BUSY: begin
                    if (tx_ongoing) state <= S_WAIT_DONE;
                end

                S_WAIT_DONE: begin
                    if (!tx_ongoing) begin
                        if (byte_idx == 2'd2) begin
                            state <= S_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= S_SEND;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Parameter sanity check
    initial begin
        assert (DEPTH >= 2 && (DEPTH & (DEPTH-1)) == 0)
            else $fatal(1, "DEPTH must be a power of 2 and >= 2");
    end

endmodule