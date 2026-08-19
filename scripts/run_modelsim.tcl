set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_file [file join $repo_dir "vivado" "CORDIC_LS_only.xpr"]

open_project $project_file
set_property target_simulator ModelSim [current_project]
set_property modelsim.simulate.runtime 5ms [get_filesets sim_1]
generate_target simulation [get_ips]
launch_simulation -simset sim_1 -mode behavioral
close_project
