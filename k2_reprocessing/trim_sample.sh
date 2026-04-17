#!/bin/bash
#SBATCH --job-name=trim
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=06:00:00
# Note: --output/--error/--dependency are set dynamically by submit_downloads.sh
# =============================================================================
# trim_sample.sh
# Runs Trim Galore (paired-end) on a single sample, with optional UMI
# extraction via umi_tools for datasets that require it.
# Trim Galore parameters are selected based on the dataset batch label.
#
# Arguments:
#   $1  ACCESSION  — sample ID (used for output naming)
#   $2  R1         — path to raw R1 FASTQ (.fastq.gz)
#   $3  R2         — path to raw R2 FASTQ (.fastq.gz)
#   $4  LAUNCH_DIR — working directory
#   $5  DATASET    — dataset batch label from input TSV (e.g. giraldez_standard)
# =============================================================================

set -euo pipefail

ACCESSION="${1:?Missing accession}"
R1="${2:?Missing R1 path}"
R2="${3:?Missing R2 path}"
LAUNCH_DIR="${4:?Missing launch_dir}"
DATASET="${5:?Missing dataset}"

TRIM_DIR="${LAUNCH_DIR}/trimmed"

echo "============================================"
echo " Trim Galore  : $ACCESSION"
echo " Dataset      : $DATASET"
echo " R1           : $R1"
echo " R2           : $R2"
echo " Output dir   : $TRIM_DIR"
echo " Started      : $(date)"
echo "============================================"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [[ ! -f "$R1" ]]; then echo "ERROR: R1 not found: $R1" >&2; exit 1; fi
if [[ ! -f "$R2" ]]; then echo "ERROR: R2 not found: $R2" >&2; exit 1; fi

mkdir -p "$TRIM_DIR"

# ── Dataset → Trim Galore parameters lookup ───────────────────────────────────
# Normalize dataset label: lowercase, spaces/hyphens/parens/commas → underscore,
# collapse multiple underscores, strip leading/trailing underscores.
DATASET_NORM=$(echo "$DATASET" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ()-,áéíóú' '_________' \
    | tr -s '_' \
    | sed 's/^_//;s/_$//')

# Adapter args shared by all datasets that need explicit adapter trimming
ADAPTER_ARGS="--fastqc -a AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC -a2 AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT --stringency 20 --length 20"

# UMI extraction settings (for datasets with with_umi=TRUE)
UMI_PATTERN='^(?P<umi_1>.{8})(?P<discard_1>.{6}).*'

WITH_UMI=false
TRIM_ARGS=""

case "$DATASET_NORM" in

    # ── Datasets with explicit adapter trimming, no UMI ──────────────────────
    block*|chen|moufarrej*|ngo|roskams_hieter*|sun|tao|zhu|encode)
        TRIM_ARGS="$ADAPTER_ARGS"
        ;;

    # ── Datasets with UMI extraction + adapter trimming ───────────────────────
    decruyenaere|flomics_1|flomics_2|flomics1|flomics2)
        TRIM_ARGS="$ADAPTER_ARGS"
        WITH_UMI=true
        ;;

    # ── Datasets with simple FastQC only ─────────────────────────────────────
    chalasani|giraldez*|ibarra*|reggiardo*|toden|wang|wei)
        TRIM_ARGS="--fastqc"
        ;;

    # ── Unknown dataset — fail loudly rather than silently using wrong params ─
    *)
        echo "ERROR: Unknown dataset '$DATASET' (normalized: '$DATASET_NORM')" >&2
        echo "       Add it to the case statement in trim_sample.sh" >&2
        exit 1
        ;;
esac

echo "Trim args  : $TRIM_ARGS"
echo "UMI step   : $WITH_UMI"

# ── Step 1 (optional): UMI extraction ─────────────────────────────────────────
# umi_tools extract reads the UMI from R1 (per the bc_pattern) and appends it
# to the read name of both R1 and R2, then discards the UMI+discard bases.
# The adapter trimming in step 2 then works on the already-extracted reads.

TRIM_INPUT_R1="$R1"
TRIM_INPUT_R2="$R2"

if [[ "$WITH_UMI" == true ]]; then
    echo "--- UMI extraction ---"
    UMI_DIR="${LAUNCH_DIR}/umi_extracted"
    mkdir -p "$UMI_DIR"

    UMI_R1="${UMI_DIR}/${ACCESSION}_umi_1.fastq.gz"
    UMI_R2="${UMI_DIR}/${ACCESSION}_umi_2.fastq.gz"
    UMI_LOG="${UMI_DIR}/${ACCESSION}_umi_extract.log"

    umi_tools extract \
        --extract-method=regex \
        --bc-pattern="$UMI_PATTERN" \
        --stdin="$R1" \
        --read2-in="$R2" \
        --stdout="$UMI_R1" \
        --read2-out="$UMI_R2" \
        --log="$UMI_LOG"

    echo "UMI extraction done. Log: $UMI_LOG"

    # Feed UMI-extracted files into Trim Galore
    TRIM_INPUT_R1="$UMI_R1"
    TRIM_INPUT_R2="$UMI_R2"
fi

# ── Step 2: Trim Galore ────────────────────────────────────────────────────────
# --paired          : paired-end mode → produces _val_1 / _val_2 outputs
# --cores           : matches --cpus-per-task
# --basename        : forces output prefix to ACCESSION so downstream scripts
#                     can predict filenames regardless of input naming
# $TRIM_ARGS        : dataset-specific adapter/quality/length flags (see above)

echo "--- Trim Galore ---"
# shellcheck disable=SC2086  # TRIM_ARGS is intentionally word-split here
trim_galore \
    --paired \
    --cores 8 \
    --basename "${ACCESSION}" \
    --output_dir "$TRIM_DIR" \
    $TRIM_ARGS \
    "$TRIM_INPUT_R1" "$TRIM_INPUT_R2"

# ── Verify outputs ────────────────────────────────────────────────────────────
TRIM_R1="${TRIM_DIR}/${ACCESSION}_1_val_1.fq.gz"
TRIM_R2="${TRIM_DIR}/${ACCESSION}_2_val_2.fq.gz"

for f in "$TRIM_R1" "$TRIM_R2"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Expected trimmed output not found: $f" >&2
        exit 1
    fi
done

echo "Trimmed outputs:"
echo "  $TRIM_R1  ($(du -sh "$TRIM_R1" | cut -f1))"
echo "  $TRIM_R2  ($(du -sh "$TRIM_R2" | cut -f1))"
echo "============================================"
echo " Finished : $ACCESSION"
echo " Completed: $(date)"
echo "============================================"
