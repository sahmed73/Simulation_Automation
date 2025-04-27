# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Wed Apr 16 09:06:20 2025

Description:
------------
This script merges two molecules from separate .mol files into a single .mol file,
ensuring that atoms from the two molecules do not overlap.

The second molecule (mol2) is translated iteratively along the +z direction
until no atoms are closer than a defined minimum distance to atoms in the first molecule (mol1).
If a non-overlapping configuration is found within the allowed number of attempts,
the combined molecule is saved as a new .mol file.

Dependencies:
-------------
- RDKit
- NumPy
- os (standard library)

Usage:
------
python combine_mols.py <mol1_path> <mol2_path> <output_path>

Example:
--------
python combine_mols.py A0010_pre.mol PAOr_pre.mol pre-reaction-test-combined.mol
"""

from rdkit import Chem
import numpy as np
import sys

# === Argument check ===
if len(sys.argv) != 4:
    print("Usage: python combine_mols.py <mol1_path> <mol2_path> <output_path>")
    sys.exit(1)

# === Command-line inputs ===
mol1_path = sys.argv[1]
mol2_path = sys.argv[2]
output_path = sys.argv[3]

# === Parameters ===
min_distance = 3.0     # Minimum allowed interatomic distance (Å)
step_size = 0.5        # Translation step size (Å)
max_attempts = 1000    # Max attempts before giving up

# === Load molecules ===
mol1 = Chem.MolFromMolFile(mol1_path, removeHs=False)
mol2_orig = Chem.MolFromMolFile(mol2_path, removeHs=False)

conf1 = mol1.GetConformer()
positions1 = conf1.GetPositions()

for attempt in range(max_attempts):
    mol2 = Chem.Mol(mol2_orig)
    conf2 = mol2.GetConformer()

    # Translate mol2 in +z direction
    offset = np.array([0.0, 0.0, attempt * step_size])
    for i in range(conf2.GetNumAtoms()):
        pos = np.array(conf2.GetAtomPosition(i))
        conf2.SetAtomPosition(i, pos + offset)

    positions2 = conf2.GetPositions()

    # Check for atomic overlap
    too_close = False
    for a1 in positions1:
        for a2 in positions2:
            if np.linalg.norm(a1 - a2) < min_distance:
                too_close = True
                break
        if too_close:
            break

    if not too_close:
        combined = Chem.CombineMols(mol1, mol2)
        Chem.MolToMolFile(combined, output_path)
        print(f"Molecules combined successfully after {attempt} translations.")
        print(f"Output saved to: {output_path}")
        break
else:
    print("Failed to separate molecules after max_attempts.")
