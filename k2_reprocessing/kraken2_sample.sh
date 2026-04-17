#!/bin/bash
#SBATCH --job-name=kraken2
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=06:00:00
# Note: --output/--error/--dependency are set dynamically by submit_downloads.sh
# =============================================================================
# kraken2_sample.sh
# Runs Kraken2 on the Trim Galore output for a single sample.
#
# Arguments:
#   $1  ACCESSION  — sample ID (used for output naming)
#   $2  TRIM_R1    — path to trimmed R1 (.fq.gz from trim_sample.sh)
#   $3  TRIM_R2    — path to trimmed R2 (.fq.gz from trim_sample.sh)
#   $4  LAUNCH_DIR — working directory; kraken2/ subdir will be created here
# =============================================================================

set -euo pipefail

ACCESSION="${1:?Missing accession}"
TRIM_R1="${2:?Missing trimmed R1 path}"
TRIM_R2="${3:?Missing trimmed R2 path}"
LAUNCH_DIR="${4:?Missing launch_dir}"

# ── Kraken2 database path — adjust to your cluster ────────────────────────────
KRAKEN2_DB="/data/db/kraken2/standard"

KRAKEN_DIR="${LAUNCH_DIR}/kraken2"
OUT_FILE="${KRAKEN_DIR}/${ACCESSION}.kraken2"
REPORT_FILE="${KRAKEN_DIR}/${ACCESSION}.kraken2.report"
UNCLASSIFIED_R1="${KRAKEN_DIR}/${ACCESSION}_unclassified_1.fq.gz"
UNCLASSIFIED_R2="${KRAKEN_DIR}/${ACCESSION}_unclassified_2.fq.gz"

echo "============================================"
echo " Kraken2      : $ACCESSION"
echo " DB           : $KRAKEN2_DB"
echo " Trimmed R1   : $TRIM_R1"
echo " Trimmed R2   : $TRIM_R2"
echo " Output dir   : $KRAKEN_DIR"
echo " Started      : $(date)"
echo "============================================"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [[ ! -d "$KRAKEN2_DB" ]]; then
    echo "ERROR: Kraken2 database not found: $KRAKEN2_DB" >&2
    echo "       Update KRAKEN2_DB in kraken2_sample.sh" >&2
    exit 1
fi
if [[ ! -f "$TRIM_R1" ]]; then echo "ERROR: Trimmed R1 not found: $TRIM_R1" >&2; exit 1; fi
if [[ ! -f "$TRIM_R2" ]]; then echo "ERROR: Trimmed R2 not found: $TRIM_R2" >&2; exit 1; fi

mkdir -p "$KRAKEN_DIR"

# ── Kraken2 ───────────────────────────────────────────────────────────────────
# --paired                 : paired-end input
# --threads                : matches --cpus-per-task above
# --gzip-compressed        : input files are .fq.gz
# --output                 : per-read classification output
# --report                 : summary report (use this for downstream analysis)
# --report-minimizer-data  : adds minimizer stats to the report
# --unclassified-out       : save unclassified reads for follow-up if needed
#                            Kraken2 uses '#' as placeholder for _1/_2 suffix

kraken2 \
    --db "$KRAKEN2_DB" \
    --paired \
    --threads 16 \
    --gzip-compressed \
    --output "$OUT_FILE" \
    --report "$REPORT_FILE" \
    --report-minimizer-data \
    --unclassified-out "${KRAKEN_DIR}/${ACCESSION}_unclassified#.fq" \
    "$TRIM_R1" "$TRIM_R2"

# ── Compress unclassified reads to save space ─────────────────────────────────
for unc in "${KRAKEN_DIR}/${ACCESSION}_unclassified_1.fq" \
           "${KRAKEN_DIR}/${ACCESSION}_unclassified_2.fq"; do
    if [[ -f "$unc" ]]; then
        gzip "$unc"
    fi
done

# ── Verify outputs ────────────────────────────────────────────────────────────
for f in "$OUT_FILE" "$REPORT_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Expected Kraken2 output not found: $f" >&2
        exit 1
    fi
done

# Print a quick classification summary from the report
echo ""
echo "--- Classification summary ---"
echo "  Unclassified : $(awk 'NR==1{printf "%.2f%%", $1}' "$REPORT_FILE")"
echo "  Classified   : $(awk 'NR==2{printf "%.2f%%", $1}' "$REPORT_FILE")"
echo "  Report       : $REPORT_FILE"
echo "------------------------------"

echo "============================================"
echo " Finished : $ACCESSION"
echo " Completed: $(date)"
echo "============================================"
