#!/bin/bash
#SBATCH --job-name=pipeline_launcher
#SBATCH --output=logs/launcher_%j.out
#SBATCH --error=logs/launcher_%j.err
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:30:00
# =============================================================================
# submit_downloads.sh
# Reads a two-column TSV (accession_id  dataset) and submits a three-job
# chain per sample:  download → trim (Trim Galore) → classify (Kraken2)
#
# Usage:  sbatch submit_downloads.sh <input_list.tsv> [launch_dir]
#
# Input TSV format (tab or space separated, no header):
#   SRR8526905          giraldez_standard
#   SAMP6082_EXP243_56  prjeb90290
#   SRRISOLATE_2552     some_label
#   X13031              some_label
#   RNA020109_S115      ega_dataset
#
# Required files in LAUNCH_DIR:
#   - ena-file-downloader.jar
#   - merge_fastqs.py  + SraRunTable.csv        (SRRISOLATE_ samples)
#   - merge_fastqs.sh  + runs_to_biosamples.csv (X##### samples)
#   - ega_mapping.tsv  + credentials.json       (RNA##### samples)
# =============================================================================

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
INPUT_FILE="${1:?Usage: sbatch $0 <input_list.tsv> [launch_dir]}"
LAUNCH_DIR="${2:-$(pwd)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/download_sample.sh"
TRIM_SCRIPT="${SCRIPT_DIR}/trim_sample.sh"
KRAKEN_SCRIPT="${SCRIPT_DIR}/kraken2_sample.sh"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
for f in "$INPUT_FILE" "$DOWNLOAD_SCRIPT" "$TRIM_SCRIPT" "$KRAKEN_SCRIPT"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required file not found: $f" >&2
        exit 1
    fi
done

mkdir -p "${LAUNCH_DIR}/logs"

echo "========================================"
echo " Download -> Trim -> Kraken2 pipeline"
echo " Input  : $INPUT_FILE"
echo " WorkDir: $LAUNCH_DIR"
echo "========================================"

# ── Helper: resolve expected R1/R2 paths produced by the download step ────────
# Each accession type lands its files in a predictable location so the
# trim and kraken2 scripts know exactly where to look.
resolve_fastq_paths() {
    local accession="$1"

    if [[ "$accession" =~ ^SRR[0-9]+$ ]]; then
        # ena-file-downloader places files directly in LAUNCH_DIR
        R1="${LAUNCH_DIR}/${accession}_1.fastq.gz"
        R2="${LAUNCH_DIR}/${accession}_2.fastq.gz"

    elif [[ "$accession" =~ ^SRRISOLATE_[0-9]+$ ]]; then
        # merge_fastqs.py writes to merged_fastqs/
        R1="${LAUNCH_DIR}/merged_fastqs/${accession}_1.fastq.gz"
        R2="${LAUNCH_DIR}/merged_fastqs/${accession}_2.fastq.gz"

    elif [[ "$accession" =~ ^X[0-9]+$ ]]; then
        # merge_fastqs.sh writes to merged_fastqs/
        R1="${LAUNCH_DIR}/merged_fastqs/${accession}_1.fastq.gz"
        R2="${LAUNCH_DIR}/merged_fastqs/${accession}_2.fastq.gz"

    elif [[ "$accession" =~ ^SAMP[0-9]+_EXP[0-9]+_[0-9]+$ ]]; then
        # ena-file-downloader, same layout as plain SRR
        R1="${LAUNCH_DIR}/${accession}_1.fastq.gz"
        R2="${LAUNCH_DIR}/${accession}_2.fastq.gz"

    elif [[ "$accession" =~ ^RNA[0-9]+_S[0-9]+$ ]]; then
        # pyega3 writes to ega_downloads/
        R1="${LAUNCH_DIR}/ega_downloads/${accession}_1.fastq.gz"
        R2="${LAUNCH_DIR}/ega_downloads/${accession}_2.fastq.gz"

    else
        echo "ERROR: Cannot resolve FASTQ paths for unknown pattern: $accession" >&2
        exit 1
    fi
}

# ── Submit one three-job chain per sample ─────────────────────────────────────
SUBMITTED=0

while IFS=$'\t ' read -r ACCESSION DATASET || [[ -n "$ACCESSION" ]]; do

    # Skip empty lines and comments
    [[ -z "$ACCESSION" || "$ACCESSION" =~ ^# ]] && continue

    resolve_fastq_paths "$ACCESSION"   # sets $R1 and $R2

    # Trim Galore paired-end output naming convention:
    #   <basename>_1_val_1.fq.gz  and  <basename>_2_val_2.fq.gz
    # where <basename> is derived from the R1 filename stem.
    # We pass these expected paths to kraken2_sample.sh so it knows
    # where to pick up without having to guess.
    TRIM_DIR="${LAUNCH_DIR}/trimmed"
    TRIM_R1="${TRIM_DIR}/${ACCESSION}_1_val_1.fq.gz"
    TRIM_R2="${TRIM_DIR}/${ACCESSION}_2_val_2.fq.gz"

    # ── Step 1: Download ──────────────────────────────────────────────────────
    DL_JOB=$(sbatch --parsable \
        --job-name="dl_${ACCESSION}" \
        --output="${LAUNCH_DIR}/logs/${ACCESSION}_1_download_%j.out" \
        --error="${LAUNCH_DIR}/logs/${ACCESSION}_1_download_%j.err" \
        --cpus-per-task=4 \
        --mem=16G \
        --time=12:00:00 \
        "$DOWNLOAD_SCRIPT" "$ACCESSION" "$DATASET" "$LAUNCH_DIR")

    # ── Step 2: Trim Galore (held until download exits 0) ─────────────────────
    TRIM_JOB=$(sbatch --parsable \
        --job-name="trim_${ACCESSION}" \
        --output="${LAUNCH_DIR}/logs/${ACCESSION}_2_trim_%j.out" \
        --error="${LAUNCH_DIR}/logs/${ACCESSION}_2_trim_%j.err" \
        --cpus-per-task=8 \
        --mem=16G \
        --time=06:00:00 \
        --dependency=afterok:${DL_JOB} \
        "$TRIM_SCRIPT" "$ACCESSION" "$R1" "$R2" "$LAUNCH_DIR" "$DATASET")

    # ── Step 3: Kraken2 (held until trim exits 0) ─────────────────────────────
    KRAKEN_JOB=$(sbatch --parsable \
        --job-name="kraken_${ACCESSION}" \
        --output="${LAUNCH_DIR}/logs/${ACCESSION}_3_kraken2_%j.out" \
        --error="${LAUNCH_DIR}/logs/${ACCESSION}_3_kraken2_%j.err" \
        --cpus-per-task=16 \
        --mem=64G \
        --time=06:00:00 \
        --dependency=afterok:${TRIM_JOB} \
        "$KRAKEN_SCRIPT" "$ACCESSION" "$TRIM_R1" "$TRIM_R2" "$LAUNCH_DIR")

    echo "  $ACCESSION  ->  dl=$DL_JOB -> trim=$TRIM_JOB -> kraken2=$KRAKEN_JOB"
    (( SUBMITTED++ )) || true

done < "$INPUT_FILE"

echo "----------------------------------------"
echo "Submitted : $SUBMITTED chains  ($(( SUBMITTED * 3 )) total jobs)"
echo "Logs in   : ${LAUNCH_DIR}/logs/"
echo "========================================"
