# -*- coding: utf-8 -*-
"""
Author: Shihab Ahmed
Created on Wed Apr 23 16:59:29 2025
"""

import os
import re

def extract_lammps_variables(input_file_path):   
    variables = {}
    styles = "(string|equal)"  # Only handling a subset of variable styles
    variable_pattern = re.compile(
        rf"^\s*variable\s+(\w+)\s+{styles}(?:\s+(.*))?", re.IGNORECASE
    )

    with open(input_file_path, 'r') as file:
        for line in file:
            line = line.split('#', 1)[0].strip()  # Remove comments
            if not line:
                continue
            match = variable_pattern.match(line)
            if match:
                var_name = match.group(1)
                var_value = match.group(3).strip() if match.group(3) else ""
                variables[var_name] = var_value
    
    return variables

def check_dependencies(dirr):
    input_file_path = os.path.join(dirr, 'input.in')
    variables = extract_lammps_variables(input_file_path)
        
    max_try = 20
    with open(input_file_path, 'r') as file:
        for line in file: 
            if line.strip().startswith('read_restart') or line.strip().startswith('read_data'):
                parts = line.split()
                if len(parts) > 1:
                    file_location = parts[1].strip()
                    pattern = r"\$\{?(\w+)\}?"
                    try_count = 0
                    while try_count < max_try:
                        try_count+=1
                        match = re.search(pattern, file_location)
                        if match:
                            var_name = match.group(1)
                            var_value = variables.get(var_name, f"${{{var_name}}}")
                            file_location = re.sub(pattern, var_value, file_location, count=1)
                        else:
                            break

                    if not os.path.isabs(file_location) and file_location:
                        file_location = os.path.abspath(os.path.join(dirr, file_location))

                    return file_location