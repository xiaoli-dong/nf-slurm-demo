# Nextflow SLURM Configuration Tutorial

## Overview

This tutorial explains how to use SLURM with Nextflow to run bioinformatics pipelines on HPC clusters. The setup uses a two-tier job submission approach: a main orchestrator job that manages the workflow, and individual compute jobs for each pipeline task.

## Architecture

```
┌─────────────────────────────────────┐
│   SLURM Submit Script               │
│   (slurm_submit.sh)                 │
│   - Lightweight orchestrator job    │
│   - Runs Nextflow main process      │
│   - 2 CPUs, 4GB RAM                 │
└──────────────┬──────────────────────┘
               │
               │ submits individual jobs
               ▼
┌─────────────────────────────────────┐
│   Nextflow Pipeline Tasks           │
│   (Submitted by Nextflow to SLURM)  │
│   - Each task = separate SLURM job  │
│   - Resources defined in base.config│
└─────────────────────────────────────┘
```

## File Structure

```
project/
├── main.nf                    # Your pipeline script
├── nextflow.config            # Main configuration file
├── conf/
│   ├── base.config           # Resource definitions per process
│   ├── modules.config        # Module-specific settings
│   └── test.config           # Test profile settings
└── test/slurm_submit.sh           # SLURM submission script

```

## Step-by-Step Breakdown

### 1. The SLURM Submit Script (`slurm_submit.sh`)

```bash
#!/bin/bash
#SBATCH --job-name=nf-orchestrator
#SBATCH --cpus-per-task=2      # Just for Nextflow main process
#SBATCH --mem=4G               # Just for Nextflow main process
#SBATCH --time=24:00:00
#SBATCH -o slurm-%j.out
#SBATCH -e slurm-%j.err
```

**What it does:**
- Creates a lightweight SLURM job to run the Nextflow orchestrator
- This job only runs the Nextflow main process (not the actual pipeline tasks)
- Resources are minimal because it just coordinates other jobs

**Key parameters:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--job-name` | nf-orchestrator | Names the orchestrator job for easy identification |
| `--cpus-per-task` | 2 | Allocates 2 CPUs for Nextflow coordination |
| `--mem` | 4G | Allocates 4GB RAM for the main Nextflow process |
| `--time` | 24:00:00 | Allows 24 hours for the entire pipeline to complete |
| `-o/-e` | slurm-%j.* | Captures logs from the orchestrator itself |

### 2. Environment Setup

```bash
eval "$(conda shell.bash hook)"
conda activate
conda activate nf-core-3
```

**What it does:**
- Initializes conda in the current shell
- Activates the `nf-core-3` environment containing Nextflow

> **Important:** Ensure this environment has:
> - Nextflow (version ≥25.04.0 per your config)
> - Java (required by Nextflow)

### 3. Running the Pipeline

```bash
nextflow run ../main.nf -profile singularity,test,slurm --outdir results
```

**What it does:**
- Executes your Nextflow pipeline with multiple profiles

**Profile breakdown:**

#### `singularity` Profile

From your `nextflow.config`:

```groovy
singularity {
    singularity.enabled     = true
    singularity.autoMounts  = true
    conda.enabled           = false
    docker.enabled          = false
    // ... other settings disabled
}
```

- Enables Singularity containers for reproducible environments
- Auto-mounts necessary directories
- Disables other container systems

#### `test` Profile

From `conf/test.config`:
- Provides test data and parameters
- Useful for validating the pipeline setup

#### `slurm` Profile

From your `nextflow.config`:

```groovy
slurm {
    process {
        executor = 'slurm'
        clusterOptions = "--partition=vm-cpu,big-ram --output=slurm-%j.out --error=slurm-%j.err"
    }
}
```

**How it works:**

- Sets SLURM as the executor for all pipeline tasks
- Each Nextflow process becomes a separate SLURM job
- Jobs are submitted to partitions: tries `vm-cpu` first, then `big-ram` if needed
- Each task gets its own log files: `slurm-<jobid>.out` and `slurm-<jobid>.err`

## How Job Submission Works

### Job Flow

1. User submits `slurm_submit.sh`
2. SLURM creates orchestrator job (Job ID: 12345)
3. Nextflow starts inside Job 12345
4. Nextflow reads `main.nf` and identifies tasks
5. For each task, Nextflow submits new SLURM job:
   - Task A → SLURM Job 12346
   - Task B → SLURM Job 12347
   - Task C → SLURM Job 12348
6. Nextflow monitors all jobs until completion
7. Orchestrator job (12345) exits when pipeline finishes

### Resource Allocation

Each task in your pipeline can have different resource requirements defined in `conf/base.config`:

```groovy
process {
    // Default resources for all processes
    cpus   = 1
    memory = 6.GB
    time   = 4.h
    
    // Specific resources for certain processes
    withLabel: process_high {
        cpus   = 12
        memory = 72.GB
        time   = 16.h
    }
}
```

**When a task runs:**

1. Nextflow reads the resource requirements
2. Submits a SLURM job with those specifications
3. Includes the clusterOptions from the slurm profile
4. Example submission: `sbatch --partition=vm-cpu,big-ram --cpus-per-task=12 --mem=72G ...`

## Log Files

### Orchestrator Logs

**Location:** `slurm-<orchestrator-job-id>.out/err`

**Contains:**
- Nextflow workflow progress
- Job submission messages
- Overall pipeline status

### Task Logs

**Location:** `work/*/*/slurm-<task-job-id>.out/err`

**Contains:**
- Individual task execution details
- Software output
- Error messages from specific tasks

### Nextflow Work Directory

**Location:** `work/`

**Contains:**
- Task-specific directories: `work/xx/yyyyyy.../`
- Command scripts: `.command.sh`
- Output files: `.command.out`, `.command.err`
- Exit status: `.exitcode`

## Common Configuration Patterns

### 1. Adjust Orchestrator Resources

If your pipeline metadata is large or you have many tasks:

```bash
#SBATCH --cpus-per-task=4      # More CPUs for coordination
#SBATCH --mem=8G               # More memory for tracking
```

### 2. Customize Partition Selection

In `nextflow.config`:

```groovy
slurm {
    process {
        executor = 'slurm'
        queue = 'high-priority,standard'  // Try high-priority first
        clusterOptions = "--output=slurm-%j.out --error=slurm-%j.err"
    }
}
```

### 3. Process-Specific SLURM Options

In `conf/base.config`:

```groovy
process {
    withName: 'ASSEMBLY' {
        clusterOptions = '--partition=big-ram --constraint=large_tmp'
    }
    
    withName: 'ALIGNMENT' {
        clusterOptions = '--partition=gpu --gres=gpu:1'
    }
}
```

### 4. Set Account or QOS

```groovy
slurm {
    process {
        executor = 'slurm'
        clusterOptions = "--account=myproject --qos=normal --output=slurm-%j.out --error=slurm-%j.err"
    }
}
```

## Running Your Pipeline

### 1. Make Script Executable

```bash
chmod +x slurm_submit.sh
```

### 2. Submit the Job

```bash
sbatch slurm_submit.sh
```

### 3. Monitor Progress

```bash
# Check orchestrator job status
squeue -u $USER

# Watch real-time Nextflow output
tail -f slurm-<jobid>.out

# View Nextflow dashboard
# Access the URL shown in the Nextflow output
```

### 5. Check Results

```bash
# Pipeline outputs
ls results/

# Execution reports
ls results/pipeline_info/
```

## Troubleshooting

### Issue: "Executor busy" or Jobs Not Submitting

**Check:** SLURM partition availability

```bash
sinfo -p vm-cpu,big-ram
```

**Solution:** Adjust partition names in config to match available partitions

### Issue: Tasks Failing with Memory Errors

**Check:** Task-specific logs in `work/` directory

**Solution:** Increase memory in `conf/base.config`:

```groovy
withLabel: process_high {
    memory = { 72.GB * task.attempt }
}
```


### Issue: Nextflow Can't Submit Jobs

**Check:** Nextflow permissions

```bash
# Test if you can submit SLURM jobs
sbatch --wrap="echo test"
```

**Solution:** Ensure your account has submission privileges

## Advanced: Resume Failed Runs

Nextflow caches completed tasks. To resume after failure:

```bash
nextflow run ../main.nf -profile singularity,test,slurm --outdir results -resume
```

**This will:**
- Skip successfully completed tasks
- Rerun only failed or new tasks
- Save time and compute resources

## Best Practices

2. **Test with small data** using the `test` profile first
3. **Monitor orchestrator logs** to catch submission issues early
4. **Use `-resume`** when debugging to avoid rerunning successful tasks
5. **Set reasonable time limits** based on expected runtime
6. **Keep orchestrator resources minimal** (current 2 CPU/4GB is good)
7. **Define process-specific resources** in `base.config` for efficiency

## Summary

This setup provides a robust way to run Nextflow pipelines on SLURM:

| Component | Purpose | Resources |
|-----------|---------|-----------|
| **Orchestrator job** (`slurm_submit.sh`) | Lightweight, long-running job that manages the workflow | 2 CPU, 4GB RAM |
| **SLURM profile** (`nextflow.config`) | Configures how tasks are submitted to SLURM | Defined per task |
| **Individual task jobs** | Each pipeline step runs as a separate SLURM job | Process-specific |
| **Automatic job management** | Nextflow handles submission, monitoring, and cleanup | N/A |

**Key advantage:** Nextflow automatically parallelizes your pipeline and manages hundreds of SLURM jobs without manual intervention.

---

## Quick Reference

### Useful Commands

```bash
# Submit pipeline
sbatch slurm_submit.sh

# Check job status
squeue -u $USER

# View orchestrator log
tail -f slurm-<jobid>.out

# Cancel all jobs
scancel -u $USER

# Resume failed pipeline
nextflow run ../main.nf -profile singularity,test,slurm --outdir results -resume

# Clean up work directory
nextflow clean -f

# View execution report
firefox results/pipeline_info/execution_report_*.html
```

### Configuration File Locations

| File | Purpose |
|------|---------|
| `nextflow.config` | Main configuration, profiles |
| `conf/base.config` | Process resource definitions |
| `conf/modules.config` | Module-specific settings |
| `slurm_submit.sh` | Job submission script |

---

**Need help?** Check the [Nextflow documentation](https://www.nextflow.io/docs/latest/) or [SLURM documentation](https://slurm.schedmd.com/)
