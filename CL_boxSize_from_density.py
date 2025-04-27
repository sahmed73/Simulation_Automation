# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Tue Mar  4 14:08:19 2025
"""

from periodictable import elements
import sys

def read_lammps_data(filename):
    """Extract atomic symbols and molecule composition from a LAMMPS data file."""
    atom_symbols = []
    with open(filename, 'r') as file:
        inside_atoms_section = False
        for line in file:
            if line.strip().startswith("Atoms"):
                inside_atoms_section = True
                continue
            if inside_atoms_section and line.strip() == "":
                continue  # Skip blank lines
            
            if inside_atoms_section and line[0].isalpha():
                break  # Stop when leaving Atoms section

            if inside_atoms_section:
                parts = line.split("#")
                if len(parts) > 1:
                    symbol = parts[1].strip().split('/')[-1]  # Extract element after "/"
                    atom_symbols.append(symbol)

    return atom_symbols

def molecular_weight(symbols):
    """Calculate molecular weight from atomic symbols."""
    total_mass = 0
    for sym in symbols:
        try:
            total_mass += elements.symbol(sym).mass
        except KeyError:
            print(f"Warning: Element {sym} not found in periodic table.")
    return total_mass

def compute_box_size(lammps_files, molecule_counts, target_density):
    """
    Compute cubic box size given multiple LAMMPS data files, molecule counts, and density.

    Parameters:
    - lammps_files: List of LAMMPS data filenames.
    - molecule_counts: List of molecule counts (same order as files).
    - target_density: Target density in g/cm³.

    Returns:
    - Box size in Å.
    """
    total_mass = 0

    for i, lammps_file in enumerate(lammps_files):
        symbols = read_lammps_data(lammps_file)
        mol_weight = molecular_weight(symbols)
        total_mass += mol_weight * molecule_counts[i]

    # Convert density from g/cm³ to atomic mass unit (amu) per Å³
    density_in_amu_per_a3 = target_density * 0.6022140857  # Conversion factor

    # Compute volume in Å³
    volume = total_mass / density_in_amu_per_a3

    # Compute cubic box length
    box_length = volume ** (1/3)

    return box_length

def parse_file_string(file_string):
    """
    Parse a file_string of the format "datafile1:qty1,datafile2:qty2,..." into two lists.
    
    Returns:
    - lammps_files: List of file names.
    - molecule_counts: List of molecule quantities as integers.
    """
    lammps_files = []
    molecule_counts = []

    pairs = file_string.split(',')
    for pair in pairs:
        file, qty = pair.split(':')
        lammps_files.append(file.strip())
        molecule_counts.append(int(qty.strip()))

    return lammps_files, molecule_counts

# Ensure proper usage
if len(sys.argv) < 3:
    print("Usage: python boxSize_from_density.py <file_string> <target_density>")
    sys.exit(1)

file_string = sys.argv[1]  # "datafile1:qty1,datafile2:qty2, ..."
target_density = float(sys.argv[2])  # g/cm³

# Parse file_string
lammps_files, molecule_counts = parse_file_string(file_string)

# Compute box size
box_size = compute_box_size(lammps_files, molecule_counts, target_density)

# Print the box size as an integer
print(f"{box_size:.0f}")
