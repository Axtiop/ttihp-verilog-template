package isr_config_pkg;

    typedef enum logic [1:0] {
        SHIFT_NONE  = 2'b00,
        SHIFT_CLOCK = 2'b01,
        SHIFT_EVENT = 2'b10,
        SHIFT_MOV  = 2'b11
    } shift_mode_t;

    typedef enum logic [1:0] {
        EVENT_RISING  = 2'b00,
        EVENT_FALLING = 2'b01,
        EVENT_HIGH    = 2'b10,
        EVENT_LOW     = 2'b11
    } event_type_t;

typedef struct packed {
    logic [2:0]  isr_id;       // [6:4]
    event_type_t event_type;   // [3:2]
    shift_mode_t shift_mode;   // [1:0]
} isr_config_t;

endpackage