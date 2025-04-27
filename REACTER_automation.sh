#!/usr/bin/env bash
#SBATCH --job-name=REACTER_AUTOMATION
#SBATCH --partition=pi.amartini
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=48
#SBATCH --time=10-00:00:00
#SBATCH --mail-type=ALL
#SBATCH --export=ALL
#SBATCH --mem=60G
#SBATCH --output=automation_log.out
#SBATCH --error=automation_error.out

# source my_functions.sh
source job_submission_functions.sh
source reacter_input_generation_functions.sh

# User Inputs
ROOT_DIR="/mnt/borgstore/amartini/sahmed73/data/REACTER"

#=============================================================================
#                          Create Simulations Inputs
#=============================================================================

WORKING_DIR=$(create_next_folder "$ROOT_DIR" "Batch")

# CSV should have a header: name,smiles
CSV_FILE="FILTERED_PubChem_compound_text_antioxidant.csv"

cp "$CSV_FILE" "$WORKING_DIR/"

# Loop through each row after the header
tail -n +2 "$CSV_FILE" | while IFS=',' read -r name smiles; do
    if [[ -n "$name" && -n "$smiles" ]]; then
        echo "Processing: $name"
        create_reacter_inputs_from_smiles "$name" "$smiles" "$WORKING_DIR"
    else
        echo "Skipping invalid line: $name, $smiles"
    fi
done

echo "ALL REACTER INPUT FILES CREATED!!"

#=============================================================================
#                              Submitting Jobs
#=============================================================================

job_submission_manager "${WORKING_DIR}"