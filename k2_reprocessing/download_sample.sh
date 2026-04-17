#!/bin/bash
# =============================================================================
# download_sample.sh
# Worker script — called by submit_downloads.sh via sbatch.
# Detects the accession type and runs the appropriate download/merge strategy.
#
# Arguments:
#   $1  ACCESSION   — e.g. SRR8526905 | SAMP6082_EXP243_56 | SRRISOLATE_2552
#                         | X13031 | RNA020109_S115
#   $2  DATASET     — label from the input TSV (informational / used for EGA)
#   $3  LAUNCH_DIR  — working directory with all helper files
# =============================================================================

set -euo pipefail

ACCESSION="${1:?Missing accession argument}"
DATASET="${2:?Missing dataset argument}"
LAUNCH_DIR="${3:?Missing launch_dir argument}"

cd "$LAUNCH_DIR"

echo "============================================"
echo " Sample   : $ACCESSION"
echo " Dataset  : $DATASET"
echo " WorkDir  : $LAUNCH_DIR"
echo " Started  : $(date)"
echo "============================================"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: download via ena-file-downloader.jar
# ─────────────────────────────────────────────────────────────────────────────
download_ena_jar() {
    local accession="$1"
    echo "[ENA-JAR] Downloading $accession ..."
    java -jar "${LAUNCH_DIR}/ena-file-downloader.jar" \
        --accessions="${accession}" \
        --format=READS_FASTQ \
        --location="${LAUNCH_DIR}" \
        --protocol=FTP \
        --asperaLocation=null
    echo "[ENA-JAR] Done: $accession"
}

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 1 — Plain SRR accession  (e.g. SRR8526905)
#   Pattern: SRR followed immediately by digits only
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$ACCESSION" =~ ^SRR[0-9]+$ ]]; then
    echo "[STRATEGY 1] Plain SRR accession detected."
    download_ena_jar "$ACCESSION"

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 2 — SRRISOLATE merge  (e.g. SRRISOLATE_2552)
#   Pattern: SRRISOLATE_ followed by digits
#   Steps  : individual SRR runs are fetched from SraRunTable.csv then merged
#            via merge_fastqs.py
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^SRRISOLATE_[0-9]+$ ]]; then
    echo "[STRATEGY 2] SRRISOLATE merge accession detected."

    ISOLATE_ID="${ACCESSION#SRRISOLATE_}"   # e.g. 2552
    SRARUN_CSV="${LAUNCH_DIR}/SraRunTable.csv"
    MERGE_PY="${LAUNCH_DIR}/merge_fastqs.py"

    if [[ ! -f "$SRARUN_CSV" ]]; then
        echo "ERROR: SraRunTable.csv not found in $LAUNCH_DIR" >&2
        exit 1
    fi
    if [[ ! -f "$MERGE_PY" ]]; then
        echo "ERROR: merge_fastqs.py not found in $LAUNCH_DIR" >&2
        exit 1
    fi

    # Extract the SRR runs that belong to this isolate
    echo "[STRATEGY 2] Extracting SRR runs for isolate $ISOLATE_ID from $SRARUN_CSV ..."
    RUN_COL=$(head -1 "$SRARUN_CSV" | tr ',' '\n' | grep -n '^Run$'      | cut -d: -f1)
    ISO_COL=$(head -1 "$SRARUN_CSV" | tr ',' '\n' | grep -n '^isolate$'  | cut -d: -f1)

    if [[ -z "$RUN_COL" || -z "$ISO_COL" ]]; then
        echo "ERROR: Could not find 'Run' or 'isolate' columns in SraRunTable.csv" >&2
        exit 1
    fi

    RUNS=$(awk -F',' -v run_col="$RUN_COL" -v iso_col="$ISO_COL" \
               -v target="$ISOLATE_ID" \
               'NR>1 && $iso_col == target {print $run_col}' \
               "$SRARUN_CSV")

    if [[ -z "$RUNS" ]]; then
        echo "ERROR: No runs found for isolate $ISOLATE_ID in SraRunTable.csv" >&2
        exit 1
    fi

    echo "[STRATEGY 2] Found runs: $(echo $RUNS | tr '\n' ' ')"

    # Download each constituent SRR run
    for RUN in $RUNS; do
        echo "[STRATEGY 2] Downloading constituent run: $RUN"
        download_ena_jar "$RUN"
    done

    # Merge using merge_fastqs.py (it reads SraRunTable.csv itself and merges
    # all isolates; output lands in merged_fastqs/SRRISOLATE_<isolate>_[12].fastq.gz)
    echo "[STRATEGY 2] Merging runs for isolate $ISOLATE_ID ..."
    python3 "$MERGE_PY"

    # Verify output
    OUT_R1="${LAUNCH_DIR}/merged_fastqs/${ACCESSION}_1.fastq.gz"
    OUT_R2="${LAUNCH_DIR}/merged_fastqs/${ACCESSION}_2.fastq.gz"
    if [[ -f "$OUT_R1" && -f "$OUT_R2" ]]; then
        echo "[STRATEGY 2] Merge complete: $OUT_R1  $OUT_R2"
    else
        echo "WARNING: Expected merged files not found after merge_fastqs.py." >&2
        echo "         Check merged_fastqs/ directory manually." >&2
    fi

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 3 — BioSample / X-series merge  (e.g. X13031)
#   Pattern: X followed by digits
#   Steps  : individual runs fetched from runs_to_biosamples.csv then merged
#            via merge_fastqs.sh
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^X[0-9]+$ ]]; then
    echo "[STRATEGY 3] X-series BioSample accession detected."

    MAPPING_CSV="${LAUNCH_DIR}/runs_to_biosamples.csv"
    MERGE_SH="${LAUNCH_DIR}/merge_fastqs.sh"

    if [[ ! -f "$MAPPING_CSV" ]]; then
        echo "ERROR: runs_to_biosamples.csv not found in $LAUNCH_DIR" >&2
        exit 1
    fi
    if [[ ! -f "$MERGE_SH" ]]; then
        echo "ERROR: merge_fastqs.sh not found in $LAUNCH_DIR" >&2
        exit 1
    fi

    # Find the column indices for Run and BioSample
    RUN_COL=$(head -1 "$MAPPING_CSV" | tr ',' '\n' | grep -n '^Run$'       | cut -d: -f1)
    BS_COL=$(head  -1 "$MAPPING_CSV" | tr ',' '\n' | grep -n '^BioSample$' | cut -d: -f1)

    if [[ -z "$RUN_COL" || -z "$BS_COL" ]]; then
        echo "ERROR: Could not find 'Run' or 'BioSample' columns in runs_to_biosamples.csv" >&2
        exit 1
    fi

    # Get all SRR runs for this BioSample
    RUNS=$(awk -F',' -v run_col="$RUN_COL" -v bs_col="$BS_COL" \
               -v target="$ACCESSION" \
               'NR>1 && $bs_col == target {print $run_col}' \
               "$MAPPING_CSV")

    if [[ -z "$RUNS" ]]; then
        echo "ERROR: No runs found for BioSample $ACCESSION in runs_to_biosamples.csv" >&2
        exit 1
    fi

    echo "[STRATEGY 3] Found runs: $(echo $RUNS | tr '\n' ' ')"

    # Download each constituent SRR run
    for RUN in $RUNS; do
        echo "[STRATEGY 3] Downloading constituent run: $RUN"
        download_ena_jar "$RUN"
    done

    # Merge using merge_fastqs.sh (it handles all BioSamples in the CSV;
    # output lands in merged_fastqs/<BIOSAMPLE>_[12].fastq.gz)
    echo "[STRATEGY 3] Merging runs for BioSample $ACCESSION ..."
    bash "$MERGE_SH"

    # Verify output
    OUT_R1="${LAUNCH_DIR}/merged_fastqs/${ACCESSION}_1.fastq.gz"
    OUT_R2="${LAUNCH_DIR}/merged_fastqs/${ACCESSION}_2.fastq.gz"
    if [[ -f "$OUT_R1" && -f "$OUT_R2" ]]; then
        echo "[STRATEGY 3] Merge complete: $OUT_R1  $OUT_R2"
    else
        echo "WARNING: Expected merged files not found after merge_fastqs.sh." >&2
        echo "         Check merged_fastqs/ directory manually." >&2
    fi

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 4 — PRJEB90290 library  (e.g. SAMP6082_EXP243_56)
#   Pattern: SAMP followed by digits, underscore, EXP, digits, underscore, digits
#   Requires: ena_prjeb90290.tsv — the ENA correspondence table for PRJEB90290
#
#   Lookup: input ID matches the library_name column -> get fastq_ftp URLs
#   -> download directly via wget.
#   Multiple rows with the same library_name (multiple runs) are all downloaded
#   and merged with cat into a single R1/R2 pair.
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^SAMP[0-9]+_EXP[0-9]+_[0-9]+$ ]]; then
    echo "[STRATEGY 4] PRJEB90290 library accession detected."

    ENA_TABLE="${LAUNCH_DIR}/ena_prjeb90290.tsv"

    if [[ ! -f "$ENA_TABLE" ]]; then
        echo "ERROR: ena_prjeb90290.tsv not found in $LAUNCH_DIR" >&2
        echo "       Expected columns include: run_accession, library_name, fastq_ftp" >&2
        exit 1
    fi

    # Find the column indices for library_name and fastq_ftp
    HEADER=$(head -1 "$ENA_TABLE")
    LIB_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n '^library_name$'  | cut -d: -f1)
    FTP_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n '^fastq_ftp$'     | cut -d: -f1)
    RUN_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n '^run_accession$' | cut -d: -f1)

    if [[ -z "$LIB_COL" || -z "$FTP_COL" || -z "$RUN_COL" ]]; then
        echo "ERROR: Could not find required columns (run_accession, library_name, fastq_ftp)" >&2
        echo "       in ena_prjeb90290.tsv" >&2
        exit 1
    fi

    # The input ID (e.g. SAMP5674_EXP228_53) contains more info than what is
    # stored in library_name (e.g. SAMP5674). Extract the SAMP stem for lookup.
    LIB_STEM=$(echo "$ACCESSION" | grep -oP '^SAMP[0-9]+')
    echo "[STRATEGY 4] Extracted library stem: $LIB_STEM (from $ACCESSION)"

    # Collect all FTP URL pairs for this library_name stem (may be multiple runs).
    # fastq_ftp contains semicolon-separated R1;R2 URLs per row.
    mapfile -t FTP_ENTRIES < <(awk -F'\t' \
        -v lib_col="$LIB_COL" -v ftp_col="$FTP_COL" -v target="$LIB_STEM" \
        'NR>1 && $lib_col == target {print $ftp_col}' "$ENA_TABLE")

    if [[ ${#FTP_ENTRIES[@]} -eq 0 ]]; then
        echo "ERROR: No rows found for library_name '$LIB_STEM' in ena_prjeb90290.tsv" >&2
        echo "       (derived from input accession: $ACCESSION)" >&2
        exit 1
    fi

    echo "[STRATEGY 4] Found ${#FTP_ENTRIES[@]} run(s) for library $LIB_STEM"

    # Download all runs into a staging directory
    STAGE_DIR="${LAUNCH_DIR}/.stage_${ACCESSION}"
    mkdir -p "$STAGE_DIR"

    ALL_R1_FILES=()
    ALL_R2_FILES=()

    for FTP_PAIR in "${FTP_ENTRIES[@]}"; do
        R1_URL=$(echo "$FTP_PAIR" | cut -d';' -f1)
        R2_URL=$(echo "$FTP_PAIR" | cut -d';' -f2)

        R1_FILENAME=$(basename "$R1_URL")
        R2_FILENAME=$(basename "$R2_URL")

        echo "[STRATEGY 4] Downloading $R1_FILENAME ..."
        wget --quiet --show-progress -O "${STAGE_DIR}/${R1_FILENAME}" "ftp://${R1_URL}"

        echo "[STRATEGY 4] Downloading $R2_FILENAME ..."
        wget --quiet --show-progress -O "${STAGE_DIR}/${R2_FILENAME}" "ftp://${R2_URL}"

        ALL_R1_FILES+=("${STAGE_DIR}/${R1_FILENAME}")
        ALL_R2_FILES+=("${STAGE_DIR}/${R2_FILENAME}")
    done

    # Single run: rename directly. Multiple runs: merge with cat.
    OUT_R1="${LAUNCH_DIR}/${ACCESSION}_1.fastq.gz"
    OUT_R2="${LAUNCH_DIR}/${ACCESSION}_2.fastq.gz"

    if [[ ${#ALL_R1_FILES[@]} -eq 1 ]]; then
        echo "[STRATEGY 4] Single run — renaming to final output."
        mv "${ALL_R1_FILES[0]}" "$OUT_R1"
        mv "${ALL_R2_FILES[0]}" "$OUT_R2"
    else
        echo "[STRATEGY 4] Multiple runs — merging ${#ALL_R1_FILES[@]} pairs ..."
        cat "${ALL_R1_FILES[@]}" > "$OUT_R1"
        cat "${ALL_R2_FILES[@]}" > "$OUT_R2"
        echo "[STRATEGY 4] Merge complete."
    fi

    rm -rf "$STAGE_DIR"

    echo "[STRATEGY 4] Done: $OUT_R1"
    echo "             Done: $OUT_R2"

# ─────────────────────────────────────────────────────────────────────────────
# STRATEGY 5 — EGA download  (e.g. RNA020109_S115)
#   Pattern: RNA followed by digits, underscore, S, digits
#   Requires: ega_files.tsv  — the EGA correspondence table with columns:
#               sample_accession_id  sample_alias  file_name  file_accession_id
#             credentials.json
#
#   Lookup logic: ACCESSION (e.g. RNA020109_S115) matches the stem of
#   file_name before _R1_001 / _R2_001, so both EGAF IDs are resolved
#   automatically — no manual curation needed.
# ─────────────────────────────────────────────────────────────────────────────
elif [[ "$ACCESSION" =~ ^RNA[0-9]+_S[0-9]+$ ]]; then
    echo "[STRATEGY 5] EGA accession detected."

    EGA_TABLE="${LAUNCH_DIR}/ega_files.tsv"
    EGA_CREDS="${LAUNCH_DIR}/credentials.json"
    EGA_OUTDIR="${LAUNCH_DIR}/ega_downloads"

    if [[ ! -f "$EGA_TABLE" ]]; then
        echo "ERROR: ega_files.tsv not found in $LAUNCH_DIR" >&2
        echo "       Expected columns: sample_accession_id  sample_alias  file_name  file_accession_id" >&2
        exit 1
    fi

    if [[ ! -f "$EGA_CREDS" ]]; then
        echo "ERROR: credentials.json not found in $LAUNCH_DIR" >&2
        exit 1
    fi

    # Resolve R1 and R2 EGAF IDs by matching the file_name column.
    # file_name looks like: RNA020109_S115_R1_001.fastq.gz
    #                       RNA020109_S115_R2_001.fastq.gz
    # We match on the accession stem so this is robust to varying S-numbers.
    EGAF_R1=$(awk -F'\t' -v acc="$ACCESSION" \
        '$3 ~ acc"_R1_" {print $4}' "$EGA_TABLE")
    EGAF_R2=$(awk -F'\t' -v acc="$ACCESSION" \
        '$3 ~ acc"_R2_" {print $4}' "$EGA_TABLE")

    if [[ -z "$EGAF_R1" ]]; then
        echo "ERROR: No R1 EGAF ID found for $ACCESSION in ega_files.tsv" >&2
        echo "       Expected a row with file_name matching: ${ACCESSION}_R1_*" >&2
        exit 1
    fi
    if [[ -z "$EGAF_R2" ]]; then
        echo "ERROR: No R2 EGAF ID found for $ACCESSION in ega_files.tsv" >&2
        echo "       Expected a row with file_name matching: ${ACCESSION}_R2_*" >&2
        exit 1
    fi

    echo "[STRATEGY 5] Resolved $ACCESSION:"
    echo "             R1 → $EGAF_R1"
    echo "             R2 → $EGAF_R2"
    mkdir -p "$EGA_OUTDIR"

    # Download R1 and R2 separately — pyega3 fetches one file per call.
    # The output file retains its original name from EGA (e.g. RNA020109_S115_R1_001.fastq.gz).
    for EGAF in "$EGAF_R1" "$EGAF_R2"; do
        echo "[STRATEGY 5] Fetching $EGAF ..."
        mamba run -n pyega3 \
            pyega3 \
                -cf "$EGA_CREDS" \
                fetch "$EGAF" \
                --output-dir "$EGA_OUTDIR"
    done

    # EGA filenames use _R1_001 / _R2_001 convention but the rest of the
    # pipeline expects <ACCESSION>_1.fastq.gz / <ACCESSION>_2.fastq.gz.
    # Rename to the standard convention used by trim_sample.sh.
    EGA_R1_ORIG=$(awk -F'\t' -v acc="$ACCESSION" \
        '$3 ~ acc"_R1_" {print $3}' "$EGA_TABLE")
    EGA_R2_ORIG=$(awk -F'\t' -v acc="$ACCESSION" \
        '$3 ~ acc"_R2_" {print $3}' "$EGA_TABLE")

    mv "${EGA_OUTDIR}/${EGA_R1_ORIG}" "${EGA_OUTDIR}/${ACCESSION}_1.fastq.gz"
    mv "${EGA_OUTDIR}/${EGA_R2_ORIG}" "${EGA_OUTDIR}/${ACCESSION}_2.fastq.gz"

    echo "[STRATEGY 5] Done."
    echo "             ${EGA_OUTDIR}/${ACCESSION}_1.fastq.gz"
    echo "             ${EGA_OUTDIR}/${ACCESSION}_2.fastq.gz"

# ─────────────────────────────────────────────────────────────────────────────
# UNKNOWN pattern
# ─────────────────────────────────────────────────────────────────────────────
else
    echo "ERROR: Accession '$ACCESSION' does not match any known pattern." >&2
    echo "  Known patterns:" >&2
    echo "    SRR<digits>              → plain ENA/SRA download" >&2
    echo "    SRRISOLATE_<digits>      → SRR multi-run merge (merge_fastqs.py)" >&2
    echo "    X<digits>                → BioSample merge (merge_fastqs.sh)" >&2
    echo "    SAMP<d>_EXP<d>_<d>      → ENA PRJEB90290 sample download" >&2
    echo "    RNA<digits>_S<digits>    → EGA download (pyega3)" >&2
    exit 1
fi

echo "============================================"
echo " Finished  : $ACCESSION"
echo " Completed : $(date)"
echo "============================================"
