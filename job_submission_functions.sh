#!/bin/bash


# ======== functions ========
# 1. job_submission_manager
# 2. submit_job
# 3. check_dependencies
# 4. update_job_dir_array
# 5. check_simulation_status
# 6. generate_job_csv_log
# ===========================


# Helper modules
PYTHON="/home/sahmed73/anaconda3/envs/saenv/bin/python3"

# Global variables
JOB_DIR_ARRAY=()


#------------------------------------------------------------------------------
# job_submission_manager
#
# Description:
#   Continuously scans the given parent directory for pending simulations,
#   checks dependency files, submits eligible jobs to SLURM partitions based
#   on available limits, and generates a CSV log of job statuses. The loop
#   continues until all eligible jobs are either submitted successfully
#   or reach a maximum submission attempt limit.
#
# Inputs:
#   $1 - parent_dir: The root directory containing simulation setup folders.
#
# Key Operations:
#   - Scan the parent directory for all simulation folders containing 'input.in' files.
#   - For each simulation:
#       - Check if the dependency file is ready (required file must exist).
#       - Count how many times the job has already been submitted (slurm-*.out files).
#       - If dependency is ready and the job has not exceeded maximum submission attempts:
#           - Submit the job to an available SLURM partition based on queue limits.
#           - If job submission is successful, or maximum attempts are reached:
#               - Remove the job from the tracking array (no longer process it).
#   - After one round of processing:
#       - Generate or update the 'simulation_job_report.csv' file showing all job statuses.
#   - Continue looping until there are no pending jobs left to process.
#
# Outputs:
#   - Submits simulation jobs via sbatch.
#   - Generates 'simulation_job_report.csv' inside the parent directory.
#
# Dependencies (Helper Functions Required):
#   - update_job_dir_array()  # Updates JOB_DIR_ARRAY based on simulation status
#   - check_dependencies()    # Verifies if job dependencies are satisfied
#   - submit_job()            # Submits job to SLURM based on partition limits
#   - generate_job_csv_log()  # Creates a CSV log of all jobs and their statuses
#
# Notes:
#   - Jobs with statuses COMPLETED, RUNNING, and PENDING are excluded.
#   - Maximum of 5 submission attempts per job directory is allowed.
#   - After successful submission, or max attempts, the job is removed from the list.
#   - A small sleep is added after each successful submission to avoid scheduler flooding.
#   - Automatically retries until all jobs are processed.
#------------------------------------------------------------------------------
job_submission_manager() {
    local parent_dir="$1"
    local job_dir
    local dependency
    local job_submitted
    local max_submission_attempts=5

    while :; do # infinite loop
        update_job_dir_array "$parent_dir" "Except:COMPLETED RUNNING PENDING"

        for i in "${!JOB_DIR_ARRAY[@]}"; do
            job_dir="${JOB_DIR_ARRAY[${i}]}"
            dependency=$(check_dependencies "$job_dir")

            # get the submission count 
            local submission_attempt_count
            submission_attempt_count=$(find "$job_dir" -maxdepth 1 -name "slurm-*.out" | wc -l)

            if [[ -f "$dependency" ]]; then
                pushd "$job_dir" > /dev/null
                
                job_submitted=$(submit_job "$job_dir" "short:12 long:3 medium:6 compute:0 amartini:0")

                if [[ "$job_submitted" == "true" ]] || (( submission_attempt_count >= max_submission_attempts )); then
                    unset JOB_DIR_ARRAY[i]
                    sleep 2
                fi

                popd > /dev/null
            fi
        done

        # generate status report
        generate_job_csv_log "$parent_dir"

        if [[ "${#JOB_DIR_ARRAY[@]}" -eq 0 ]]; then
            break
        fi
    done
}



#------------------------------------------------------------------------------
# submit_job
#
# Description:
#   Submits a simulation job by modifying its SLURM submission script to match
#   the available cluster partition (short, medium, long, compute, or pi.amartini),
#   according to real-time queue limits. If partition availability is found,
#   updates the SLURM parameters (partition, core count, wall time) and submits
#   the job using sbatch. Priority is given to partitions in a predefined order.
#
# Inputs:
#   $1 - job_dir: Path to the simulation directory containing 'submit.sh'.
#   $2 - partitions (Optional): Space-separated "partition:limit" pairs
#        (default: "short:12 long:3 medium:6 compute:0 pi.amartini:0").
#
# Key Operations:
#   - Define partition priorities (e.g., short > compute > medium > long > pi.amartini).
#   - Define maximum core counts and wall times for each partition.
#   - Check the current number of running or pending jobs in each partition.
#   - Find an available partition (under the allowed limit).
#   - Update the 'submit.sh' file to:
#       - Set correct partition name.
#       - Set correct number of cores.
#       - Set correct maximum wall time.
#   - Submit the job using sbatch (normal for Pinnacle, `-M merced` for compute partition).
#   - If submission is successful, return 'true'; otherwise 'false'.
#
# Outputs:
#   - Echoes "true" if the job was successfully submitted, "false" otherwise.
#
# Dependencies (Helper Functions Required):
#   - None

# Notes:
#   - Automatically uses dos2unix to fix Windows line endings in 'submit.sh' before editing.
#   - Only submits to a partition if the current job count is below its limit.
#   - Priority order ensures faster queues (like 'short') are attempted first.
#   - Designed for SLURM job management on mixed-cluster environments (Pinnacle and Merced).
#------------------------------------------------------------------------------

submit_job() {
    local job_dir="$1"
    local partitions="${2:-short:12 long:3 medium:6 compute:0 pi.amartini:0}"
    
    local submit_file="$job_dir/submit.sh"
    local job_submitted=false

    # Priority order: highest to lowest
    local partition_priority=()
    declare -A partition_limit

    # Fill arrays
    for item in $partitions; do
        local name=${item%%:*}   # text before colon
        local limit=${item##*:}  # text after colon

        partition_priority+=("$name")
        partition_limit["$name"]="$limit"
    done

    # Time and core settings
    declare -A partition_time=(
        ["short"]="6:00:00"
        ["long"]="72:00:00"
        ["medium"]="24:00:00"
        ["compute"]="120:00:00"
        ["pi.amartini"]="72:00:00"
    )

    declare -A partition_cores=(
        ["short"]=48
        ["long"]=48
        ["medium"]=48
        ["compute"]=32
        ["pi.amartini"]=48
    )

    dos2unix "$submit_file" > /dev/null

    for partition in "${partition_priority[@]}"; do
        # Get limit and queue info
        local core_count="${partition_cores[$partition]}"
        local wall_time="${partition_time[$partition]}"

        # Get queue count
        local count
        if [[ "$partition" == "compute" ]]; then
            count=$(squeue -M merced -u sahmed73 | grep -cw "$partition")
        else
            count=$(squeue -u sahmed73 | grep -cw "$partition")
        fi


        if (( count < "${partition_limit[$partition]}" )); then
            # Update SLURM script
            sed -i "/^#SBATCH --partition=/c\\#SBATCH --partition=$partition" "$submit_file"
            sed -i "/^#SBATCH --ntasks-per-node=/c\\#SBATCH --ntasks-per-node=$core_count" "$submit_file"
            sed -i "/^#SBATCH --time=/c\\#SBATCH --time=$wall_time" "$submit_file"

            # Submit job
            if [[ "$partition" == "compute" ]]; then
                sbatch -M merced "$submit_file" > /dev/null && job_submitted=true
            else
                sbatch "$submit_file" > /dev/null && job_submitted=true
            fi

            break
        fi
    done

    echo "$job_submitted"
}


#------------------------------------------------------------------------------
# check_dependencies
#
# Description:
#   Checks whether the necessary dependency files for a given simulation job
#   are ready. Runs a Python script (dependency_checker.py) that performs the 
#   actual dependency check logic, with a timeout to avoid hanging indefinitely.
#
# Inputs:
#   $1 - job_dir: Path to the simulation directory to check for dependencies.
#
# Key Operations:
#   - Calls an external Python script ('dependency_checker.py') with job_dir as input.
#   - Limits the Python call to 10 seconds using 'timeout' command.
#   - Captures and returns the output from the Python script.
#
# Outputs:
#   - Echoes the dependency status (file path of satisfied dependency, or empty string if missing).
#
# Dependencies (Helper Functions Required):
#   - None inside Bash.
#   - Requires 'dependency_checker.py' Python script to be available and properly working.
#
# Notes:
#   - If the dependency check Python script exceeds 10 seconds, the command will fail.
#   - It is assumed that dependency_checker.py prints a filepath if successful, or nothing otherwise.
#   - Requires the environment variable $PYTHON to point to the correct Python executable.
#------------------------------------------------------------------------------
check_dependencies() {
    local job_dir="$1"
    local output
    output=$(timeout 10s "$PYTHON" -c "import dependency_checker; print(dependency_checker.check_dependencies('$job_dir'))")
    echo "$output"
}


#------------------------------------------------------------------------------
# update_job_dir_array
#
# Description:
#   Updates the global JOB_DIR_ARRAY with simulation directories that are 
#   eligible for submission. It filters out directories whose simulation status 
#   matches any of the excluded statuses provided.
#
# Inputs:
#   $1 - parent_dir: The root directory where all simulation subfolders are located.
#   $2 - except_string (Optional): Space-separated statuses to exclude.
#        Default: "Except:COMPLETED RUNNING PENDING"
#
# Key Operations:
#   - Finds all simulation directories that contain an 'input.in' file.
#   - Checks the current status of each simulation by calling check_simulation_status().
#   - Excludes directories whose status matches any provided in except_string.
#   - Populates the JOB_DIR_ARRAY with only eligible simulation directories.
#
# Outputs:
#   - Updates the global array variable JOB_DIR_ARRAY.
#
# Dependencies (Helper Functions Required):
#   - check_simulation_status()   # Determines the status of a simulation directory
#
# Notes:
#   - The exclusion statuses are space-separated after the prefix "Except:".
#   - The JOB_DIR_ARRAY is cleared and repopulated fresh each time this function runs.
#   - Only simulation directories containing 'input.in' files are considered.
#------------------------------------------------------------------------------
update_job_dir_array() {
	# except_string="Except:COMPLETED RUNNING PENDING" # space separted
    local parent_dir="$1"
    local except_string="${2:-Except:COMPLETED RUNNING PENDING}"

    JOB_DIR_ARRAY=()  # Clear previous entries

    while IFS= read -r sim_dir; do
        local status
        status=$(check_simulation_status "$sim_dir")

        if [[ ! " ${except_string#Except:} " =~ " $status " ]]; then
            JOB_DIR_ARRAY+=("$sim_dir")
        fi
    done < <(find "$parent_dir" -type f -name "input.in" -exec dirname {} \;)
}


#------------------------------------------------------------------------------
# check_simulation_status
#
# Description:
#   Determines the current status of a simulation directory based on:
#   (1) the LAMMPS output file and 
#   (2) the SLURM job status. 
#   It intelligently distinguishes between successfully completed, incomplete, failed, or not submitted jobs.
#
# Inputs:
#   $1 - job_dir: The directory path containing simulation files, including 'output.out' and 'slurm-*.out'.
#
# Key Operations:
#   - Checks if 'output.out' exists and contains the string "Total wall time".
#     - If found → marks as 'complete'.
#     - If not found → marks as 'incomplete'.
#     - If missing → marks as 'missing'.
#     - If 'output.out' is not missing:
#     - Finds the latest 'slurm-*.out' file and extracts the job ID.
#     - Uses 'sacct' to query SLURM for the job status.
#     - First tries the default cluster; if no info, tries the 'merced' cluster.
#   - Combines the LAMMPS output check and SLURM status to decide the final status:
#     - 'HARD_FAIL' : SLURM job failed.
#     - 'COMPLETED' : SLURM completed + output file complete.
#     - 'SOFT_FAIL' : SLURM completed + output file incomplete.
#     - Other SLURM statuses returned directly (e.g., PENDING, RUNNING).
#
# Outputs:
#   - Prints the determined simulation status to stdout.
#
# Dependencies (Helper functions Used):
#   - None
#
# Notes:
#   - Assumes job output files follow the naming 'slurm-*.out'.
#   - Assumes 'sacct' is available and configured for both Pinnacle and Merced clusters.
#------------------------------------------------------------------------------
check_simulation_status() {
    local job_dir="$1"

    # Check LAMMPS output file
    local completion
    local lammps_output_file="$job_dir/output.out"
    if [ -f "$lammps_output_file" ]; then
        if grep -q "Total wall time" "$lammps_output_file"; then
            completion="complete"
        else
            completion="incomplete"
        fi
    else
        completion="missing"
    fi


    # Check SLURM job status
    local slurm_status
    if [[ "$completion" != "missing" ]]; then
        if ls "$job_dir"/slurm-*.out &> /dev/null; then
            local slurm_file
            slurm_file=$(ls -t "$job_dir"/slurm-*.out | head -n 1)
            local job_id
            job_id=$(basename "$slurm_file" | sed -E 's/slurm-([0-9]+)\.out/\1/')

            slurm_status=$(sacct -j "$job_id" --format=State --noheader | awk 'NR==1{gsub(/\+/, "", $1); print $1}') # try pinnacle
            if [[ -z "$slurm_status" ]]; then
                slurm_status=$(sacct -M merced -j "$job_id" --format=State --noheader | awk 'NR==1{gsub(/\+/, "", $1); print $1}') # then try merced
            fi
        else
            slurm_status="NOT_SUBMITTED"
        fi
    else
        slurm_status="NOT_SUBMITTED"
    fi

    # Decide final simulation status
    if [[ "$slurm_status" == "FAILED" ]]; then
        echo "HARD_FAIL"
    elif [[ "$slurm_status" == "COMPLETED" && "$completion" == "complete" ]]; then
        echo "COMPLETED"
    elif [[ "$slurm_status" == "COMPLETED" && "$completion" == "incomplete" ]]; then
        echo "SOFT_FAIL"
    else
        echo "$slurm_status"
    fi
}


#------------------------------------------------------------------------------
# generate_job_csv_log
#
# Description:
#   Generates a detailed CSV report summarizing the status and resource usage
#   of all simulation jobs within a given parent directory. It collects
#   information from LAMMPS output files and SLURM job records (using sacct).
#
# Inputs:
#   $1 - parent_dir: The root directory containing simulation setup folders.
#
# Key Operations:
#   - Searches for all simulation directories containing 'input.in' files.
#   - For each simulation:
#     - Checks the simulation status using 'check_simulation_status'.
#     - Extracts job metadata (JobID, Partition, Start, End, etc.) using 'sacct'.
#     - Captures any LAMMPS error message from 'output.out'.
#     - Falls back to default values ('N/A') if fields are unavailable.
#   - Writes the collected information into a CSV file named 'simulation_job_report.csv'.
#
# Outputs:
#   - A CSV file ('simulation_job_report.csv') created inside the parent directory
#     with the following columns:
#     JobID, JobName, Status, Partition, Submit, Start, End, Elapsed,
#     AllocCPUs, NodeList, MaxRSS, ReqMem, SimDir, Error
#
# Dependencies (Helper Functions/Commands Used):
#   - check_simulation_status()   # To determine job state
#
# Notes:
#   - If the job info is missing on the default cluster (Pinnacle), it retries using the Merced cluster.
#   - Empty or missing fields are recorded as 'N/A' to maintain consistency.
#   - Automatically captures and logs any detected LAMMPS runtime errors.
#------------------------------------------------------------------------------
generate_job_csv_log() {
    local parent_dir="$1"
    local csv_file="${parent_dir}/simulation_job_report.csv"
    local sim_dir status job_id
    local sacct_output

    # Write header line first
    echo "JobID,JobName,Status,Partition,Submit,Start,End,Elapsed,AllocCPUs,NodeList,MaxRSS,ReqMem,SimDir,Error" > "$csv_file"

    # Loop over all simulation directories
    while IFS= read -r sim_dir; do
        status=$(check_simulation_status "$sim_dir")

        # Default values
        local jobid="N/A" jobname="N/A" partition="N/A" submit="N/A"
        local start="N/A" end="N/A" elapsed="N/A" alloccpus="N/A"
        local nodelist="N/A" maxrss="N/A" reqmem="N/A" error="None"

        # Getting lammps error (if any)
        if [[ -f "${sim_dir}/output.out" ]]; then
            error=$(grep -i "error" "${sim_dir}/output.out" || echo "None")
        fi

        if [[ "$status" != "NOT_SUBMITTED" ]]; then
            if ls "$sim_dir"/slurm-*.out &> /dev/null; then
                local slurm_file
                slurm_file=$(ls -t "$sim_dir"/slurm-*.out | head -n 1)
                job_id=$(basename "$slurm_file" | sed -E 's/slurm-([0-9]+)\.out/\1/')

                # First try Pinnacle cluster
                sacct_output=$(sacct -j "$job_id" --format=JobID,JobName,Start,End,Elapsed,Submit,AllocCPUs,NodeList,MaxRSS,ReqMem,Partition --noheader --parsable2 | grep -E "^${job_id}\|")

                # If not found, try Merced cluster
                if [[ -z "$sacct_output" ]]; then
                    sacct_output=$(sacct -M merced -j "$job_id" --format=JobID,JobName,Start,End,Elapsed,Submit,AllocCPUs,NodeList,MaxRSS,ReqMem,Partition --noheader --parsable2 | grep -E "^${job_id}\|")
                fi

                # Parse output only if available
                if [[ -n "$sacct_output" ]]; then
                    IFS="|" read -r jobid jobname start end elapsed submit alloccpus nodelist maxrss reqmem partition <<< "$sacct_output"
                fi
            fi
        fi

        # Write final line to CSV
        echo "\"$jobid\",\"$jobname\",\"$status\",\"$partition\",\"$submit\",\"$start\",\"$end\",\"$elapsed\",\"$alloccpus\",\"$nodelist\",\"$maxrss\",\"$reqmem\",\"$sim_dir\",\"$error\"" >> "$csv_file"

    done < <(find "$parent_dir" -type f -name "input.in" -exec dirname {} \;)
}

