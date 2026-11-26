# project.sdc: replaces LibreLane's default base.sdc
# Target PDK: ihp-sg13cmos5l (PDK-neutral; takes cell names from the flow)

# Helper: read a flow variable if it exists, else use a fallback
proc cfg {name default} {
    if {[info exists ::env($name)]} { return $::env($name) }
    return $default
}

# Return the ports of 'ports' whose names are not in 'excluded_names'
proc ports_without {ports excluded_names} {
    set result {}
    foreach p $ports {
        if {[lsearch -exact $excluded_names [get_property $p name]] < 0} {
            lappend result $p
        }
    }
    return $result
}

set period [cfg CLOCK_PERIOD 40.0]

# Placeholders: replace them with the values from the base.sdc of the
# *CMOS5L* LibreLane/PDK install (they were SG13G2 values).
set io_pct       0.2
set uncertainty  0.25
set transition   0.15
set derate       0.05
set cap_load_pf  0.033

# ---- Clocks ----
create_clock [get_ports clk]        -name main_clk -period $period
create_clock [get_ports {ui_in[6]}] -name aux_clk  -period $period

set_clock_uncertainty $uncertainty [get_clocks {main_clk aux_clk}]
set_clock_transition  $transition  [get_clocks {main_clk aux_clk}]

# Asynchronous domains: no timing on paths between them.
# The CDC itself must be verified by lint or simulation, not by STA.
set_clock_groups -asynchronous -group {main_clk} -group {aux_clk}

# ---- Port lists ----
set data_in  [ports_without [all_inputs] {clk ui_in[6]}]

set aux_out_names {uo_out[0] uo_out[1] uo_out[2] uo_out[3] uo_out[4]}
set aux_out  [get_ports $aux_out_names]
set main_out [ports_without [all_outputs] $aux_out_names]

# ---- I/O timing ----
set io_delay [expr {$period * $io_pct}]

set_input_delay  $io_delay -clock main_clk $data_in
set_output_delay $io_delay -clock aux_clk  $aux_out
set_output_delay $io_delay -clock main_clk $main_out

# ---- Electrical environment ----
# SYNTH_DRIVING_CELL is set by the PDK config ("cell/pin" or just "cell").
# Fallback: first *_buf_4 cell in the loaded libraries, so no SG13G2 name
# is hardcoded.
set drv [cfg SYNTH_DRIVING_CELL ""]
if {$drv eq ""} {
    set cands [get_lib_cells -quiet {*/*_buf_4}]
    if {[llength $cands] == 0} {
        error "project.sdc: SYNTH_DRIVING_CELL unset and no *_buf_4 lib cell found"
    }
    set drv "[lindex [split [get_full_name [lindex $cands 0]] /] end]/[cfg SYNTH_DRIVING_CELL_PIN X]"
}
if {[string first / $drv] >= 0} {
    lassign [split $drv /] drv_cell drv_pin
} else {
    set drv_cell $drv
    set drv_pin  [cfg SYNTH_DRIVING_CELL_PIN X]
}
set_driving_cell -lib_cell $drv_cell -pin $drv_pin $data_in

set_load $cap_load_pf [all_outputs]
set_max_fanout [cfg MAX_FANOUT_CONSTRAINT 10] [current_design]

set_timing_derate -early [expr {1 - $derate}]
set_timing_derate -late  [expr {1 + $derate}]