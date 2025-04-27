# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Wed Apr 16 01:54:24 2025

Description:
------------
This script takes a molecule's name and SMILES string as input, generates
a 3D structure using RDKit, and saves it as a .mol file in the specified output directory.

Usage:
------
python script.py <molecule_name> <molecule_SMILES> <output_dir>

Arguments:
    molecule_name   - A short name or ID for the molecule.
    molecule_SMILES - The SMILES representation of the molecule.
    data_dir        - Directory where the generated .mol file will be saved.
"""

import os
import sys
from rdkit import Chem
from rdkit.Chem import AllChem

# Validate argument count
if len(sys.argv) != 4:
    print("Error: Expected exactly 3 arguments.")
    print("Usage: python script.py <molecule_name> <molecule_SMILES> <output_dir>")
    sys.exit(1)


# Extract input arguments
name       = sys.argv[1]
smiles     = sys.argv[2]
data_dir   = sys.argv[3]

# Convert SMILES to RDKit molecule
mol = Chem.MolFromSmiles(smiles)

if mol is None:
    print(f"Warning: Could not parse SMILES for '{name}'")
    sys.exit(1)

# Add hydrogens and generate 3D coordinates
mol = Chem.AddHs(mol)
AllChem.EmbedMolecule(mol, randomSeed=42)
AllChem.MMFFOptimizeMolecule(mol)

# Define output .mol file path
mol_file_path = os.path.join(data_dir, f"{name}.mol")

# Write molecule to .mol file
Chem.MolToMolFile(mol, mol_file_path)
