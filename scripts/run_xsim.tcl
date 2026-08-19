set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_file [file join $repo_dir "vivado" "CORDIC_LS_only.xpr"]

open_project $project_file
set_property target_simulator XSim [current_project]
generate_target simulation [get_ips]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
set_property target_simulator ModelSim [current_project]
close_project
