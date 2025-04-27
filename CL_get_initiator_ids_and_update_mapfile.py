# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Sun Apr 20 13:10:06 2025
"""
import pandas as pd
import re
import periodictable
import os
import networkx as nx
import sys

def remove_delete_ids_section(lines):
    """
    Removes the DeleteIDs section, including:
    - The 'DeleteIDs' header
    - All numeric lines under it
    - The summary line like '74 deleteIDs'
    """
    new_lines = []
    skip = False
    for line in lines:
        stripped = line.strip()

        # Remove the "74 deleteIDs" style line
        if re.match(r"^\d+\s+deleteIDs$", stripped, re.IGNORECASE):
            continue

        # Start skipping when "DeleteIDs" section begins
        if stripped == "DeleteIDs":
            skip = True
            continue

        # Continue skipping numeric lines in DeleteIDs section
        if skip:
            if stripped.isdigit() or stripped == "":
                continue
            else:
                skip = False  # End of DeleteIDs section

        if not skip:
            new_lines.append(line)

    return new_lines

def get_symbol_from_mass(mass, tol=0.01):
    closest = None
    min_diff = float("inf")

    for element in periodictable.elements:
        if element.number == 0:
            continue  # skip "None" element
        diff = abs(element.mass - mass)
        if diff < tol and diff < min_diff:
            min_diff = diff
            closest = element

    if closest:
        return closest.symbol
    else:
        return None
    
def read_lammps_data(filepath):
    atom_lines = []
    bond_tuples = []
    mass_lines = []
    
    with open(filepath, 'r') as file:
        lines = file.readlines()

    section = None
    for line in lines:
        line = line.strip()

        if not line or line.startswith("#"):
            continue  # skip empty/comment lines

        # Detect section headers
        if "Masses" in line:
            section = "masses"
            continue
        elif "Atoms" in line:
            section = "atoms"
            continue
        elif "Bonds" in line:
            section = "bonds"
            continue
        elif line.endswith("Coeffs") or "Velocities" in line:
            section = None  # skip non-relevant sections
            
        # Parse relevant sections
        if section == "masses":
            if line[0].isdigit():
                parts = re.split(r'\s+', line, maxsplit=2)
                atom_type = int(parts[0])
                mass = float(parts[1])
                mass_lines.append([atom_type, mass])
            else: # blank lines are skipped at the top so no worries
                section = None
                
        elif section == "atoms":
            if line[0].isdigit():
                parts = line.split()
                atom_id = int(parts[0])
                mol_id   = int(parts[1])
                atom_type = int(parts[2])
                x, y, z = map(float, parts[3:6])
                atom_lines.append([atom_id, mol_id, atom_type, x, y, z])
            else: # blank lines are skipped at the top so no worries
                section = None

        elif section == "bonds":
            if line[0].isdigit():
                parts = line.split()
                atom1 = int(parts[2])
                atom2 = int(parts[3])
                bond_tuples.append((atom1, atom2))
            else: # blank lines are skipped at the top so no worries
                section = None

    # Convert atoms to DataFrame
    atom_df = pd.DataFrame(atom_lines, columns=['id', 'mol-id', 'type', 'x', 'y', 'z'])
    mass_df = pd.DataFrame(mass_lines, columns=['type', 'mass'])
    mass_df['symbol'] = mass_df['mass'].apply(get_symbol_from_mass)

    return mass_df, atom_df, bond_tuples

def compare_graph_changes(G1, G2, id_map, G1_mid_map):
    # Step 1: Remap G2 to G1 node IDs
    G2_mapped = nx.relabel_nodes(G2, id_map)

    # Step 2: Create canonical edge sets
    edges_G1 = set(frozenset((i, j)) for i, j in G1.edges())
    edges_G2 = set(frozenset((i, j)) for i, j in G2_mapped.edges())

    # Step 3: Identify formed bonds
    formed = edges_G2 - edges_G1
    formed_edges = [tuple(sorted(e)) for e in formed]

    # Step 4: Keep only those where both atoms are from the same mol-id
    filtered_formed_edges = [
        (i, j) for i, j in formed_edges
        if G1_mid_map.get(i) != G1_mid_map.get(j)
    ]
    
    flat_filteredformed_edges = sorted([atom for edge in filtered_formed_edges for atom in edge])

    return flat_filteredformed_edges



def get_map_from_mapfile(mapfile):
    """
    Parses a REACTER map file to extract node ID mapping from pre-Graph to post-Graph.

    Parameters:
        mapfile (str): Path to the map file.

    Returns:
        dict: A dictionary where keys are post-Graph node IDs and values are pre-Graph node IDs.
    """
    map_dict = {}
    in_equiv_section = False

    with open(mapfile, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("Equivalences"):
                in_equiv_section = True
                continue
            if in_equiv_section:
                if not line[0].isdigit():
                    break  # exit if a non-numeric line appears after Equivalences
                parts = line.split()
                if len(parts) >= 2:
                    g1_id = int(parts[0])
                    g2_id = int(parts[1])
                    map_dict[g2_id] = g1_id
    return map_dict


which = 1
working_dir = sys.argv[1]
ff = sys.argv[2] 

pre_reaction = os.path.join(working_dir, 'from_LUNAR', 'from_all2lmp', f'pre_reaction_{which}_typed_{ff}.data')
post_reaction = os.path.join(working_dir, 'from_LUNAR', 'from_all2lmp', f'post_reaction_{which}_typed_{ff}.data')
rxn_map = os.path.join(working_dir, 'from_LUNAR', 'from_bond_react_merge', f'pre{which}-post{which}_rxn-map_uncommented.txt')

# === Load structures ===
prerxn_masses, prerxn_atoms, prerxn_bonds = read_lammps_data(pre_reaction)
postrxn_masses, postrxn_atoms, postrxn_bonds = read_lammps_data(post_reaction)
post_pre_rxn_map = get_map_from_mapfile(rxn_map)

prerxn_id_molid_map = dict(zip(prerxn_atoms['id'], prerxn_atoms['mol-id']))

pre_Graph  = nx.Graph(prerxn_bonds)
post_Graph = nx.Graph(postrxn_bonds)
initiator_ids = compare_graph_changes(pre_Graph, post_Graph, post_pre_rxn_map,
                                       prerxn_id_molid_map)

print(f"Initiator ids: {initiator_ids}")

# Read the file and modify the content
with open(rxn_map, 'r') as file:
    lines = file.readlines()

# Define backup path
backup_path = rxn_map.replace('.txt', '_backup.txt')

# Only create backup if it doesn't already exist
if not os.path.exists(backup_path):
    with open(backup_path, 'w') as backup_file:
        backup_file.writelines(lines)
    print("--Backup saved!")
else:
    print("--Backup already exists!!")

    
# Replace 'ID1' and 'ID2' with values from initiator_atoms
updated_lines = []
for line in lines:
    if 'ID1' in line or 'ID2' in line:
        line = line.replace('ID1', str(initiator_ids[0]))
        line = line.replace('ID2', str(initiator_ids[1]))
    updated_lines.append(line)

# Remove DeleteIDs section
final_lines = remove_delete_ids_section(updated_lines)

# Write the updated content back to the file
with open(rxn_map, 'w') as file:
    file.writelines(final_lines)

print(f"Replaced 'ID1' and 'ID2' with {initiator_ids} in the file.")