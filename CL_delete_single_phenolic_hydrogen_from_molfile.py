# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Apr 16, 2025

Description:
------------
Reads a .mol file, finds phenolic -OH groups attached to benzene rings,
and removes one phenolic hydrogen atom from the structure.
"""

from rdkit import Chem
from rdkit.Chem import rdmolops
import sys

# === Inputs ===
mol_path = sys.argv[1]
which = 1  # 1-based index to select which phenolic H to remove

# === Load the molecule ===
mol = Chem.MolFromMolFile(mol_path, removeHs=False)

# Add bond info and explicit hydrogens if needed
mol = Chem.AddHs(mol)
rdmolops.Kekulize(mol, clearAromaticFlags=True)

# Build molecular graph
G = rdmolops.GetAdjacencyMatrix(mol)
symbols = [atom.GetSymbol() for atom in mol.GetAtoms()]

# === Step 1: Find benzene rings ===
sssr = Chem.GetSymmSSSR(mol)
benzene_rings = [
    list(ring) for ring in sssr
    if len(ring) == 6 and all(symbols[i] == 'C' for i in ring)
]

# === Step 2: Find phenolic oxygens (O attached to benzene C) ===
phenolic_O_indices = []
for ring in benzene_rings:
    for c_idx in ring:
        atom = mol.GetAtomWithIdx(c_idx)
        for neighbor in atom.GetNeighbors():
            if neighbor.GetSymbol() == 'O':
                phenolic_O_indices.append(neighbor.GetIdx())

# === Step 3: Find hydrogens bonded to phenolic O ===
phenolic_H_indices = []
for o_idx in phenolic_O_indices:
    atom = mol.GetAtomWithIdx(o_idx)
    for neighbor in atom.GetNeighbors():
        if neighbor.GetSymbol() == 'H':
            phenolic_H_indices.append(neighbor.GetIdx())
            break  # Only one H per OH group

print(f"Detected phenolic H indices: {phenolic_H_indices}")

# === Step 4: Remove selected phenolic H ===
if len(phenolic_H_indices) >= which:
    editable_mol = Chem.EditableMol(mol)
    editable_mol.RemoveAtom(phenolic_H_indices[which - 1])
    new_mol = editable_mol.GetMol()
    Chem.MolToMolFile(new_mol, mol_path)
    print("Phenolic hydrogen removed and updated")
else:
    print(f"Not enough phenolic H atoms to remove index {which}")
