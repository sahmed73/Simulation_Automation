# Simulation_Automation

**Simulation_Automation** is a Bash-based automation framework designed for high-throughput molecular dynamics (MD) simulations.
It automates simulation input generation, job submission to SLURM clusters, dependency management, and job status logging into CSV format.

---

## 📂 Repository Structure

| File/Folder | Purpose |
| :-- | :-- |
| `job_submission_functions.sh` | Automates job submission, monitoring, and logging |
| `REACTER_inputs_generation_functions.sh` | Generates simulation inputs from SMILES strings |
| `lammps_input_templates/` | Contains template `input.in` and `submit.sh` files |
| `PAOr_pre.mol`, `PAOr_post.mol` | PAO radical molecule files (pre/post reaction) |
| `Python Scripts (CL_*.py)` | Helper Python scripts for molecule processing and box size calculation |

---

## ⚙️ Key Functionalities

- **Simulation Input Generation**
  - Converts SMILES to `.mol` files.
  - Prepares pre- and post-reaction structures.
  - Builds LAMMPS-compatible data files.
  - Generates necessary `input.in` and `submit.sh` files.

- **Automated Job Submission**
  - Dynamically chooses the best available SLURM partition.
  - Updates SLURM scripts with partition, cores, and wall time.
  - Monitors the submission limits for each partition.

- **Dependency Checking**
  - Verifies if all prerequisites are satisfied before submission.

- **Job Status Logging**
  - Generates `simulation_job_report.csv` containing:
    - Job ID, Name, Status, Partition, Timing Info
    - Allocated CPUs, Node List, Memory Usage
    - Simulation Directory, and Detected Errors

---

## 💻 How to Use

1. **Clone the Repository**
   ```bash
   git clone https://github.com/your-username/Simulation_Automation.git
   cd Simulation_Automation
   ```

2. **Prepare the Environment**
   - Ensure Python environment is ready.
   - Ensure templates and Python helper scripts are available.

3. **Generate Simulation Inputs**
   ```bash
   source REACTER_inputs_generation_functions.sh
   WORKING_DIR=$(create_next_folder "$ROOT_DIR" "Batch")
   tail -n +2 FILTERED_PubChem_compound_text_antioxidant.csv | while IFS=',' read -r name smiles; do
       create_reacter_inputs_from_smiles "$name" "$smiles" "$WORKING_DIR"
   done
   ```

4. **Submit Jobs and Track Progress**
   ```bash
   source job_submission_functions.sh
   job_submission_manager "$WORKING_DIR"
   ```

5. **Monitor Progress**
   - Monitor job status using the generated `simulation_job_report.csv`.
   - Check SLURM jobs manually if needed with `squeue`.

---

## 🛠️ Requirements

- Bash Shell
- SLURM Job Scheduler (Pinnacle, Merced Clusters)
- Python 3.x
- `dos2unix` utility
- LAMMPS Input Templates

---

## 📜 License

This project is intended for academic and research purposes.

---

> For any issues, improvements, or questions, feel free to contribute or open an issue!

