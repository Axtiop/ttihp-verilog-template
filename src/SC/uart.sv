module uart #(
    parameter int CLK_FREQ  = 25_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_ni,

    input  logic       rx,
    output logic       tx,

    output logic [7:0] uart_data,
    output logic       uart_data_valid
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int HALF_BIT     = CLKS_PER_BIT / 2;

    // 217 clocks/bit -> 8 bits is enough
    localparam int COUNT_WIDTH = $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;

    logic [COUNT_WIDTH-1:0] clk_count;
    logic [2:0]             bit_count;
    logic [7:0]             rx_data;

    // TX unused
    assign tx = 1'b1;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            state      <= IDLE;
            clk_count  <= '0;
            bit_count  <= '0;
            rx_data    <= '0;
            uart_data   <= '0;
            uart_data_valid <= 1'b0;
        end else begin
            // One-clock pulse
            uart_data_valid <= 1'b0;

            case (state)

                IDLE: begin
                    clk_count <= '0;
                    bit_count <= '0;

                    if (!rx) begin
                        state <= START;
                    end
                end

                START: begin
                    // Sample in the middle of the start bit
                    if (clk_count == COUNT_WIDTH'(HALF_BIT - 1)) begin
                        clk_count <= '0;

                        if (!rx) begin
                            state     <= DATA;
                            bit_count <= '0;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    // Sample each data bit
                    if (clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        clk_count          <= '0;
                        rx_data[bit_count] <= rx;

                        if (bit_count == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        clk_count <= '0;
                        state     <= IDLE;

                        uart_data   <= rx_data;
                        uart_data_valid <= 1'b1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule