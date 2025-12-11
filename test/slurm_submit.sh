#!/bin/bash

#SBATCH --job-name=nf-orchestrator
#SBATCH --cpus-per-task=2      # Just for Nextflow main process
#SBATCH --mem=4G               # Just for Nextflow main process
#SBATCH --time=24:00:00
#SBATCH -o logs/slurm-%j.out
#SBATCH -e logs/slurm-%j.err

# ---------------------------------------------------------------------

# ACTIVATE conda
eval "$(conda shell.bash hook)"
conda activate

conda activate nf-core-3
echo "Current working directory: `pwd`"
echo "Starting run at: `date`"
# ---------------------------------------------------------------------


nextflow run ../main.nf -profile singularity,test,slurm --outdir results

# ---------------------------------------------------------------------
echo "Job finished with exit code $? at: `date`"
conda deactivate
