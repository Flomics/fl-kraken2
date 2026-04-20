#!/usr/bin/env bash
# =============================================================================
# download_sample.sh  —  Nextflow-adapted download worker
#
# Runs inside a Nextflow work directory.  Auxiliary mapping/credentials files
# are passed as absolute paths (staged or referenced directly).
#
# Usage:
#   download_sample.sh <ACCESSION> <DATASET> \
#       <SRA_RUN_TABLE> <ISOLATE_TO_RUNS> \
#       <ENA_PRJEB90290_TSV> <EGA_FILES_CSV> <EGA_CREDENTIALS>
#
# Output (always in current working directory):
#   ${ACCESSION}_1.fastq.gz
#   ${ACCESSION}_2.fastq.gz
#
# Supported accession patterns and required aux files:
#   SRR<d>               → fastq-dl
#   SRRISOLATE_<d>       → fastq-dl + SraRunTable.csv
#   X<d>                 → fastq-dl + isolate_to_runs.txt
#   SAMP<d>*             → ena_prjeb90290.tsv (wget)
#   RNA<d>_S<d>          → ega_files.csv + credentials.json (pyega3)
# =============================================================================

set -euo pipefail

ACCESSION="${1:?Missing accession}"
DATASET="${2:?Missing dataset}"
SRA_RUN_TABLE="${3:-}"
ISOLATE_TO_RUNS="${4:-}"
ENA_PRJEB90290_TSV="${5:-}"
EGA_FILES_CSV="${6:-}"
EGA_CREDENTIALS="${7:-}"

echo "=== download_sample.sh ==="
echo "ACCESSION : $ACCESSION"
echo "DATASET   : $DATASET"
echo "Started   : $(date)"
echo "WorkDir   : $(pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: download via fastq-dl, which exits non-zero on failure.
# fastq-dl writes files directly to --outdir with naming:
#   PE → <accession>_1.fastq.gz  <accession>_2.fastq.gz
#   SE → <accession>.fastq.gz
# ─────────────────────────────────────────────────────────────────────────────
download_ena() {
    local accession="$1"
    echo "[ENA] Downloading $accession ..."
    local provider_flag=''
    [[ "${DATASET,,}" =~ ^giraldez ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^zhu ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^tao ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^roskams ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^block ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^ibarra ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^ngo ]] && provider_flag='--provider sra --only-provider'
    [[ "${DATASET,,}" =~ ^reggiardo ]] && provider_flag='--provider sra --only-provider'

    fastq-dl --accession "${accession}" --outdir . ${provider_flag}

    # SE: fastq-dl produces <accession>.fastq.gz (no _1 suffix); rename for consistency
    if [[ ! -f "${accession}_1.fastq.gz" && -f "${accession}.fastq.gz" ]]; then
        mv "${accession}.fastq.gz" "${accession}_1.fastq.gz"
    fi

    # Always produce a _2 file so Nextflow output declarations stay consistent.
    # For single-end samples this will be an empty gzip; TrimGalore ignores it
    # when meta.single_end == true.
    if [[ ! -f "${accession}_2.fastq.gz" ]]; then
        gzip -c /dev/null > "${accession}_2.fastq.gz"
    fi

    echo "[ENA] Done: $accession"
}

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 1 — Plain SRR accession  (e.g. SRR8526905)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$ACCESSION" =~ ^SRR[0-9]+$ ]]; then
    echo "[STRATEGY 1] Plain SRR."
    download_ena "$ACCESSION"

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 2 — SRRISOLATE merge  (e.g. SRRISOLATE_2552)
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^SRRISOLATE_[0-9]+$ ]]; then
    echo "[STRATEGY 2] SRRISOLATE merge."
    [[ -z "$SRA_RUN_TABLE"  || ! -f "$SRA_RUN_TABLE"  ]] && { echo "ERROR: sra_run_table not found"        >&2; exit 1; }

    ISOLATE_ID="${ACCESSION#SRRISOLATE_}"

    # Use Python's csv.DictReader to handle quoted fields with internal commas
    RUNS=$(python3 -c "
import csv, sys
with open(sys.argv[1]) as f:
    for row in csv.DictReader(f):
        if row.get('isolate') == sys.argv[2]:
            print(row['Run'])
" "$SRA_RUN_TABLE" "$ISOLATE_ID")

    [[ -z "$RUNS" ]] && { echo "ERROR: No runs for isolate $ISOLATE_ID in SraRunTable.csv" >&2; exit 1; }
    echo "[STRATEGY 2] Constituent runs: $(echo "$RUNS" | tr '\n' ' ')"

    for RUN in $RUNS; do
        download_ena "$RUN"
    done

    R1_FILES=(); R2_FILES=()
    for RUN in $RUNS; do
        [[ -f "${RUN}_1.fastq.gz" ]] && R1_FILES+=("${RUN}_1.fastq.gz") || echo "WARNING: ${RUN}_1.fastq.gz missing"
        [[ -f "${RUN}_2.fastq.gz" ]] && R2_FILES+=("${RUN}_2.fastq.gz") || echo "WARNING: ${RUN}_2.fastq.gz missing"
    done

    [[ ${#R1_FILES[@]} -eq 0 ]] && { echo "ERROR: No R1 files to merge for $ACCESSION" >&2; exit 1; }
    echo "[STRATEGY 2] Merging ${#R1_FILES[@]} run(s) → ${ACCESSION}_1.fastq.gz"
    cat "${R1_FILES[@]}" > "${ACCESSION}_1.fastq.gz"
    cat "${R2_FILES[@]}" > "${ACCESSION}_2.fastq.gz"

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 3 — X-series isolate merge  (e.g. X13031)
#   Strips the X prefix and looks up the integer isolate ID in isolate_to_runs.txt
#   Format: two whitespace-separated columns — isolate_id  SRR_accession
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^X[0-9]+$ ]]; then
    echo "[STRATEGY 3] X-series isolate merge."
    [[ -z "$ISOLATE_TO_RUNS" || ! -f "$ISOLATE_TO_RUNS" ]] && { echo "ERROR: isolate_to_runs not found" >&2; exit 1; }

    ISOLATE_NUM="${ACCESSION#X}"
    RUNS=$(awk -v id="$ISOLATE_NUM" '$1 == id {print $2}' "$ISOLATE_TO_RUNS")

    [[ -z "$RUNS" ]] && { echo "ERROR: No runs for isolate $ISOLATE_NUM in isolate_to_runs.txt" >&2; exit 1; }
    echo "[STRATEGY 3] Constituent runs: $(echo "$RUNS" | tr '\n' ' ')"

    for RUN in $RUNS; do
        download_ena "$RUN"
    done

    R1_FILES=(); R2_FILES=()
    for RUN in $RUNS; do
        [[ -f "${RUN}_1.fastq.gz" ]] && R1_FILES+=("${RUN}_1.fastq.gz") || echo "WARNING: ${RUN}_1.fastq.gz missing"
        [[ -f "${RUN}_2.fastq.gz" ]] && R2_FILES+=("${RUN}_2.fastq.gz") || echo "WARNING: ${RUN}_2.fastq.gz missing"
    done

    [[ ${#R1_FILES[@]} -eq 0 ]] && { echo "ERROR: No R1 files to merge for $ACCESSION" >&2; exit 1; }
    echo "[STRATEGY 3] Merging ${#R1_FILES[@]} run(s) → ${ACCESSION}_1.fastq.gz"
    cat "${R1_FILES[@]}" > "${ACCESSION}_1.fastq.gz"
    cat "${R2_FILES[@]}" > "${ACCESSION}_2.fastq.gz"

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 4 — PRJEB90290 / ENA FTP library  (any accession starting with SAMP)
#   Looks up the SAMP<d> stem in the library_name column, downloads via wget,
#   and merges multiple runs if present.
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^SAMP[0-9]+ ]]; then
    echo "[STRATEGY 4] PRJEB90290 ENA FTP library."
    [[ -z "$ENA_PRJEB90290_TSV" || ! -f "$ENA_PRJEB90290_TSV" ]] && {
        echo "ERROR: ena_prjeb90290_tsv not found" >&2; exit 1; }

    # Extract just the SAMP<digits> prefix for the library_name lookup
    LIB_STEM=$(echo "$ACCESSION" | grep -oP '^SAMP[0-9]+')
    echo "[STRATEGY 4] Library stem: $LIB_STEM (from accession: $ACCESSION)"

    HEADER=$(head -1 "$ENA_PRJEB90290_TSV")
    LIB_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n '^library_name$' | cut -d: -f1)
    FTP_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n '^fastq_ftp$'    | cut -d: -f1)

    mapfile -t FTP_ENTRIES < <(awk -F'\t' \
        -v lc="$LIB_COL" -v fc="$FTP_COL" -v t="$LIB_STEM" \
        'NR>1 && $lc == t {print $fc}' "$ENA_PRJEB90290_TSV")

    [[ ${#FTP_ENTRIES[@]} -eq 0 ]] && {
        echo "ERROR: No FTP entries for library_name='$LIB_STEM' in ena_prjeb90290.tsv" >&2; exit 1; }
    echo "[STRATEGY 4] Found ${#FTP_ENTRIES[@]} run(s)."

    ALL_R1=(); ALL_R2=()
    for PAIR in "${FTP_ENTRIES[@]}"; do
        R1_URL=$(echo "$PAIR" | cut -d';' -f1)
        R2_URL=$(echo "$PAIR" | cut -d';' -f2)
        R1_NAME=$(basename "$R1_URL")
        R2_NAME=$(basename "$R2_URL")
        echo "[STRATEGY 4] Downloading $R1_NAME ..."
        wget --quiet -O "$R1_NAME" "ftp://${R1_URL}"
        echo "[STRATEGY 4] Downloading $R2_NAME ..."
        wget --quiet -O "$R2_NAME" "ftp://${R2_URL}"
        ALL_R1+=("$R1_NAME"); ALL_R2+=("$R2_NAME")
    done

    if [[ ${#ALL_R1[@]} -eq 1 ]]; then
        mv "${ALL_R1[0]}" "${ACCESSION}_1.fastq.gz"
        mv "${ALL_R2[0]}" "${ACCESSION}_2.fastq.gz"
    else
        echo "[STRATEGY 4] Merging ${#ALL_R1[@]} runs..."
        cat "${ALL_R1[@]}" > "${ACCESSION}_1.fastq.gz"
        cat "${ALL_R2[@]}" > "${ACCESSION}_2.fastq.gz"
    fi

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 5 — EGA download  (e.g. RNA020109_S115)
#   ega_files.csv is comma-separated:
#     sample_accession_id, sample_alias, file_name, file_accession_id
#   Matches accession against file_name column (pattern: ACCESSION_R1_ / _R2_)
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^RNA[0-9]+_S[0-9]+$ ]]; then
    echo "[STRATEGY 5] EGA (pyega3)."
    [[ -z "$EGA_FILES_CSV"   || ! -f "$EGA_FILES_CSV"   ]] && { echo "ERROR: ega_files_csv not found"   >&2; exit 1; }
    [[ -z "$EGA_CREDENTIALS" || ! -f "$EGA_CREDENTIALS" ]] && { echo "ERROR: ega_credentials not found" >&2; exit 1; }

    # ega_files.csv is comma-separated (col3=file_name, col4=file_accession_id)
    EGAF_R1=$(awk -F',' -v acc="$ACCESSION" '$3 ~ acc"_R1_" {print $4}' "$EGA_FILES_CSV")
    EGAF_R2=$(awk -F',' -v acc="$ACCESSION" '$3 ~ acc"_R2_" {print $4}' "$EGA_FILES_CSV")

    [[ -z "$EGAF_R1" ]] && { echo "ERROR: No R1 EGAF ID for $ACCESSION in ega_files.csv" >&2; exit 1; }
    [[ -z "$EGAF_R2" ]] && { echo "ERROR: No R2 EGAF ID for $ACCESSION in ega_files.csv" >&2; exit 1; }
    echo "[STRATEGY 5] R1 → $EGAF_R1 | R2 → $EGAF_R2"

    mkdir -p ega_downloads
    for EGAF in "$EGAF_R1" "$EGAF_R2"; do
        pyega3 -cf "$EGA_CREDENTIALS" fetch "$EGAF" --output-dir ega_downloads
    done

    EGA_R1_ORIG=$(awk -F',' -v acc="$ACCESSION" '$3 ~ acc"_R1_" {print $3}' "$EGA_FILES_CSV")
    EGA_R2_ORIG=$(awk -F',' -v acc="$ACCESSION" '$3 ~ acc"_R2_" {print $3}' "$EGA_FILES_CSV")

    # pyega3 saves files under ega_downloads/<EGAF_ID>/<filename>
    mv "ega_downloads/${EGAF_R1}/${EGA_R1_ORIG}" "${ACCESSION}_1.fastq.gz"
    mv "ega_downloads/${EGAF_R2}/${EGA_R2_ORIG}" "${ACCESSION}_2.fastq.gz"

else
    echo "ERROR: Accession '$ACCESSION' does not match any known pattern." >&2
    echo "  Supported: SRR<d>  SRRISOLATE_<d>  X<d>  SAMP<d>*  RNA<d>_S<d>" >&2
    exit 1
fi

echo "=== Done: $ACCESSION  $(date) ==="
echo "Output: ${ACCESSION}_1.fastq.gz  ${ACCESSION}_2.fastq.gz"
