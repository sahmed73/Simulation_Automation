#!/bin/bash


#====== Inputs ====== 
SCRIPT_DIR="/mnt/borgstore/amartini/sahmed73/data/REACTER/REACTER_AUTO/Molecule-wise_Automation"
PYTHON="/home/sahmed73/anaconda3/envs/saenv/bin/python3"
LUNAR_DIR="/mnt/borgstore/amartini/sahmed73/data/LUNAR"

TEMPLATE_DIR="${SCRIPT_DIR}/lammps_input_templates"
PRE_PAO_RADICAL_MOL="${SCRIPT_DIR}/PAOr_pre.mol" # same dir
POST_PAO_RADICAL_MOL="${SCRIPT_DIR}/PAOr_post.mol" # same dir
PAO_RADICAL_TYPED_PCFF="${SCRIPT_DIR}/PAO_radical_typed_PCFF.data" # same dir
PAO_RADICAL_MOL="${SCRIPT_DIR}/PAO_radical.mol"
FORCE_FIELD="PCFF-IFF"


PY_MERGE_MOL="${SCRIPT_DIR}/CL_merge_into_single_mol_file.py"
PY_DELETE_PHENOLIC_HYDROGEN="${SCRIPT_DIR}/CL_delete_single_phenolic_hydrogen_from_molfile.py"
PY_BOXSIZE_FROM_DENSITY="${SCRIPT_DIR}/CL_boxSize_from_density.py"
PY_UPDATE_MAPFILE="${SCRIPT_DIR}/CL_get_initiator_ids_and_update_mapfile.py"
PY_ALL2LMP_CUSTOMS="${LUNAR_DIR}/all2lmp_ME_REACTER.py"


TARGET_DENSITY=0.15


create_next_folder() {
    local parent_dir="$1"  # Parent directory where folders exist
    local prefix="$2"      # e.g. prefix = solubility, reactor; final folder name = solubility001, reactor005
    local last_folder
    local next_number
    local next_folder

    # Ensure the parent directory exists
    if [[ ! -d "$parent_dir" ]]; then
        echo "Error: Parent directory '$parent_dir' does not exist."
        return 1
    fi

    # Find existing '${prefix}###' folders and get the highest number
    last_folder=$(ls -d "$parent_dir"/${prefix}* 2>/dev/null | grep -Eo "${prefix}[0-9]+" | grep -Eo '[0-9]+' | sort -V | tail -1)

    # If no folder exists, start from prefix001
    if [[ -z "$last_folder" ]]; then
        next_folder="$parent_dir/${prefix}001"
    else
        next_number=$((10#$last_folder + 1))  # Convert to number and increment
        next_folder=$(printf "%s/%s%03d" "$parent_dir" "$prefix" "$next_number")  # Format with leading zeros
    fi

    # Create the next folder
    mkdir "$next_folder"
    
    # Print the new folder path for variable assignment
    echo "$next_folder"
}

create_reacter_inputs_from_smiles() {
    local name="$1"
    local smiles="$2"
    local output_dir="$3"
    
    local parent_dir="${output_dir}/${name}"
    if [ -d "$parent_dir" ]; then
	    echo "Directory '$parent_dir' already exists. Skipping..."
	    return
	fi

    local data_dir="${parent_dir}/DataFile"
    local single_molecules_dir="${data_dir}/Single_Molecules"
    local ao_mol
    local pre_reaction_mol
    local post_reaction_mol

    mkdir -p "${single_molecules_dir}"

    # Create antioxidant .mol file
    "$PYTHON" CL_single_smiles_to_mol.py "$name" "$smiles" "${single_molecules_dir}"
    ao_mol="${single_molecules_dir}/${name}.mol"

    # Create pre-reaction combined .mol file
    pre_reaction_mol="${single_molecules_dir}/pre_reaction_1.mol"
    "$PYTHON" "${PY_MERGE_MOL}" "${ao_mol}" "${PRE_PAO_RADICAL_MOL}" "${pre_reaction_mol}"

    # Create post-reaction combined .mol file
    post_reaction_mol="${single_molecules_dir}/post_reaction_1.mol"
    "$PYTHON" "${PY_MERGE_MOL}" "${ao_mol}" "${POST_PAO_RADICAL_MOL}" "${post_reaction_mol}"

    # Remove phenolic hydrogen
    "$PYTHON" "${PY_DELETE_PHENOLIC_HYDROGEN}" "${post_reaction_mol}"

    # ==================== LUNAR ====================
    pushd "$LUNAR_DIR" > /dev/null || exit 1

    "$PYTHON" "CL_all_in_one.py" -wd "${data_dir}" -ao "${name}" -paod "${PAO_RADICAL_MOL}" \
        -n1 50 -n2 25 -den "$TARGET_DENSITY" -ff "$FORCE_FIELD"

    popd > /dev/null

    # ================ Update reaction map files ================
    "$PYTHON" "$PY_UPDATE_MAPFILE" "$data_dir" "$FORCE_FIELD"

    # ================ Prepare bulk simulation inputs ================
    create_lammps_input_from_template "$parent_dir" "$TEMPLATE_DIR" 3
}


create_lammps_input_from_template() {
	local parent_dir="$1"       # Expects subdirectories: DataFile, Eq, Reaction
	local template_dir="$2"
	local number_of_simulations="$3"
	local antioxidant_name
	local sim_dir
	antioxidant_name=$(basename "$parent_dir")

	# static variable -- User can change
	Rmax="2.10"
	Rprob="0.25"
	ff="PCFF-IFF"

	local datafile
	datafile=$(find "$parent_dir/DataFile/Bulk" -maxdepth 1 -name "*.data" | head -n 1)

	for ((i = 1; i <= number_of_simulations; i++)); do

		######## Equilibration ######

		sim_dir="$parent_dir/Eq/Sim-${i}"
		mkdir -p "$sim_dir"

		# --- Eq INPUT.IN ---
		cp "$template_dir/Eq/Sim-X/input.in" "$sim_dir/input.in"
		sed -i "s|<<datafile>>|$datafile|g" "$sim_dir/input.in"
		sed -i "s|<<sim_number>>|$i|g" "$sim_dir/input.in"

		# --- Eq SUBMIT.SH ---
		cp "$template_dir/Eq/Sim-X/submit.sh" "$sim_dir/submit.sh"
		sed -i "s|<<job-name>>|Eq-S${i}-${antioxidant_name}|g" "$sim_dir/submit.sh"

		######## Reaction ######

		sim_dir="$parent_dir/Reaction/Rmax=${Rmax}_Rprob=${Rprob}/Sim-${i}"
		mkdir -p "$sim_dir"

		# --- Reaction INPUT.IN ---
		cp "$template_dir/Reaction/Rmax=X.XX_Rprob=X.XX/Sim-X/input.in" "$sim_dir/input.in"
		sed -i "s|<<Rmax>>|$Rmax|g" "$sim_dir/input.in"
		sed -i "s|<<Rprob>>|$Rprob|g" "$sim_dir/input.in"
		sed -i "s|<<ff>>|$ff|g" "$sim_dir/input.in"
		sed -i "s|<<sim_number>>|$i|g" "$sim_dir/input.in"

		# --- Reaction SUBMIT.SH ---
		cp "$template_dir/Reaction/Rmax=X.XX_Rprob=X.XX/Sim-X/submit.sh" "$sim_dir/submit.sh"
		sed -i "s|<<job-name>>|Rxn-S${i}-${antioxidant_name}_Rmax=${Rmax}_Rprob=${Rprob}|g" "$sim_dir/submit.sh"
	done
}