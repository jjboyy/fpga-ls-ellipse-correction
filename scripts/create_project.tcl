set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_dir [file join $repo_dir "vivado"]

create_project CORDIC_LS_only $project_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator ModelSim [current_project]
set_property ip_repo_paths [file join $repo_dir "ip_repo"] [current_project]
update_ip_catalog

add_files -norecurse [glob -nocomplain [file join $repo_dir "rtl" "*.v"]]
foreach xci [glob -nocomplain [file join $repo_dir "ip" "*" "*.xci"]] {
    import_ip -files $xci
}

add_files -fileset sim_1 -norecurse [file join $repo_dir "tb" "tb_ls.v"]
add_files -fileset sim_1 -norecurse [glob -nocomplain [file join $repo_dir "data" "*.hex"]]

set_property top mac_matrix_calc [get_filesets sources_1]
set_property top tb_ls [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created [file join $project_dir CORDIC_LS_only.xpr]"
close_project
