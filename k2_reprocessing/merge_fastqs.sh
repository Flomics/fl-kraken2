#!/bin/bash

# Path to your mapping CSV file
MAPPING_FILE="runs_to_biosamples.csv"

# Output directory for merged files
OUTPUT_DIR="./merged_fastqs"
mkdir -p "$OUTPUT_DIR"

# Temporary file to track samples and their runs
TMP_FILE="sample_to_runs.txt"
rm -f "$TMP_FILE"

# Extract 'Run' and 'BioSample' columns
# Find the column numbers for Run and BioSample
RUN_COL=$(head -1 "$MAPPING_FILE" | tr ',' '\n' | grep -n '^Run$' | cut -d':' -f1)
BIOSAMPLE_COL=$(head -1 "$MAPPING_FILE" | tr ',' '\n' | grep -n '^BioSample$' | cut -d':' -f1)

# Check if we found the correct columns
if [[ -z "$RUN_COL" || -z "$BIOSAMPLE_COL" ]]; then
    echo "❌ Could not find 'Run' or 'BioSample' column in the header!"
    exit 1
fi

# Parse the file and prepare the mapping
tail -n +2 "$MAPPING_FILE" | awk -v run_col="$RUN_COL" -v biosample_col="$BIOSAMPLE_COL" -F',' '{
    print $run_col, $biosample_col
}' >> "$TMP_FILE"

# Merge files per sample
for SAMPLE in $(cut -d' ' -f2 "$TMP_FILE" | sort | uniq); do
    echo "Merging files for BioSample: $SAMPLE..."

    # Get all runs corresponding to this sample
    RUNS=$(awk -v sample="$SAMPLE" '$2 == sample {print $1}' "$TMP_FILE")

    FILES_1=""
    FILES_2=""

    for RUN in $RUNS; do
        FILE_1="${RUN}_1.fastq.gz"
        FILE_2="${RUN}_2.fastq.gz"

        # Check if the symlink/file exists before adding
        if [[ -e "$FILE_1" && -e "$FILE_2" ]]; then
            FILES_1="$FILES_1 $FILE_1"
            FILES_2="$FILES_2 $FILE_2"
        else
            echo "⚠️ Warning: Missing one or both files for $RUN, skipping this run..."
        fi
    done

    # Only merge if there are files
    if [[ -n "$FILES_1" && -n "$FILES_2" ]]; then
        cat $FILES_1 > "$OUTPUT_DIR/${SAMPLE}_1.fastq.gz"
        cat $FILES_2 > "$OUTPUT_DIR/${SAMPLE}_2.fastq.gz"
        echo "✅ Finished merging $SAMPLE."
    else
        echo "⚠️ No valid files found for $SAMPLE, skipping merging."
    fi
done

# Cleanup
rm -f "$TMP_FILE"

echo "🎉 All merging finished successfully!"
