module uart #(
    parameter int CLK_FREQ  = 25_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_ni,

    input  logic       rx,
    output logic       tx,
    output logic       tx_ongoing,
    input  logic [7:0] uart_data_out,
    input  logic       uart_data_out_valid,
    output logic [7:0] uart_data,
    output logic       uart_data_valid
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int HALF_BIT     = CLKS_PER_BIT / 2;
    localparam int COUNT_WIDTH  = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    // ============================================================
    // RX
    // ============================================================

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    rx_state_t rx_state;

    logic [COUNT_WIDTH-1:0] rx_clk_count;
    logic [2:0]             rx_bit_count;
    logic [7:0]             rx_data;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_state        <= RX_IDLE;
            rx_clk_count    <= '0;
            rx_bit_count    <= '0;
            rx_data         <= '0;
            uart_data       <= '0;
            uart_data_valid <= 1'b0;
        end else begin
            // One-clock pulse
            uart_data_valid <= 1'b0;

            case (rx_state)

                RX_IDLE: begin
                    rx_clk_count <= '0;
                    rx_bit_count <= '0;

                    if (!rx) begin
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    // Sample in the middle of the start bit
                    if (rx_clk_count == COUNT_WIDTH'(HALF_BIT - 1)) begin
                        rx_clk_count <= '0;

                        if (!rx) begin
                            rx_state     <= RX_DATA;
                            rx_bit_count <= '0;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 1'b1;
                    end
                end

                RX_DATA: begin
                    // Sample each data bit
                    if (rx_clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        rx_clk_count        <= '0;
                        rx_data[rx_bit_count] <= rx;

                        if (rx_bit_count == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_count <= rx_bit_count + 1'b1;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 1'b1;
                    end
                end

                RX_STOP: begin
                    if (rx_clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        rx_clk_count <= '0;
                        rx_state     <= RX_IDLE;

                        uart_data       <= rx_data;
                        uart_data_valid <= 1'b1;
                    end else begin
                        rx_clk_count <= rx_clk_count + 1'b1;
                    end
                end

                default: begin
                    rx_state <= RX_IDLE;
                end

            endcase
        end
    end

    // ============================================================
    // TX
    // ============================================================

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t tx_state;

    logic [COUNT_WIDTH-1:0] tx_clk_count;
    logic [2:0]             tx_bit_count;
    logic [7:0]             tx_data;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_state     <= TX_IDLE;
            tx_clk_count <= '0;
            tx_bit_count <= '0;
            tx_data      <= '0;
            tx           <= 1'b1;
            tx_ongoing   <= 1'b0;
        end else begin
            case (tx_state)

                TX_IDLE: begin
                    tx           <= 1'b1;
                    tx_clk_count <= '0;
                    tx_bit_count <= '0;
                    tx_ongoing   <= 1'b0;
                    // Accept data only when the transmitter is idle.
                    // Valid pulses during transmission are ignored.
                    if (uart_data_out_valid) begin
                        tx_data    <= uart_data_out;
                        tx         <= 1'b0;
                        tx_state   <= TX_START;
                        tx_ongoing <= 1'b1;
                    end
                end

                TX_START: begin
                    // Hold start bit for one bit period
                    if (tx_clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= '0;
                        tx            <= tx_data[0];
                        tx_state      <= TX_DATA;
                        tx_bit_count  <= '0;
                    end else begin
                        tx_clk_count <= tx_clk_count + 1'b1;
                    end
                end

                TX_DATA: begin
                    // Hold each data bit for one bit period
                    if (tx_clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= '0;

                        if (tx_bit_count == 3'd7) begin
                            tx        <= 1'b1;
                            tx_state  <= TX_STOP;
                        end else begin
                            tx_bit_count <= tx_bit_count + 1'b1;
                            tx          <= tx_data[tx_bit_count + 1'b1];
                        end
                    end else begin
                        tx_clk_count <= tx_clk_count + 1'b1;
                    end
                end

                TX_STOP: begin
                    // Hold stop bit for one bit period
                    if (tx_clk_count == COUNT_WIDTH'(CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= '0;
                        tx_state     <= TX_IDLE;
                    end else begin
                        tx_clk_count <= tx_clk_count + 1'b1;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                    tx       <= 1'b1;
                end

            endcase
        end
    end

endmodule