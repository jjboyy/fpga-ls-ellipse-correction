set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_file [file join $repo_dir "vivado" "CORDIC_LS_only.xpr"]

open_project $project_file
set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] != 0} {
    puts "ERROR: locked IPs: $locked_ips"
    close_project
    exit 1
}

puts "Design top: [get_property top [get_filesets sources_1]]"
puts "Simulation top: [get_property top [get_filesets sim_1]]"
puts "IP count: [llength [get_ips -quiet]]"
puts "Locked IP count: [llength $locked_ips]"
report_compile_order -used_in simulation -file [file join $repo_dir "results" "compile_order.txt"]
close_project
