import pandas as pd
from pathlib import Path
import os

# Setup
metadata_file = Path("SraRunTable.csv")
output_dir = Path("merged_fastqs/")
log_file = Path("merged_fastqs_manifest.tsv")
output_dir.mkdir(exist_ok=True)

# Load metadata
df = pd.read_csv(metadata_file)
assert "Run" in df.columns and "isolate" in df.columns

# Open manifest log
with open(log_file, "w") as log:
    log.write("isolate\tmerged_file\toriginal_files\n")

    for isolate, group in df.groupby("isolate"):
        r1_files = []
        r2_files = []
        for run in group["Run"]:
            r1 = Path(f"{run}_1.fastq.gz")
            r2 = Path(f"{run}_2.fastq.gz")
            if r1.exists() and r2.exists():
                r1_files.append(str(r1))
                r2_files.append(str(r2))
            else:
                print(f"Skipping {run}, missing R1 or R2")

        if not r1_files or not r2_files:
            continue

        out_r1 = output_dir / f"SRRISOLATE_{isolate}_1.fastq.gz"
        out_r2 = output_dir / f"SRRISOLATE_{isolate}_2.fastq.gz"

        os.system(f"cat {' '.join(r1_files)} > {out_r1}")
        os.system(f"cat {' '.join(r2_files)} > {out_r2}")

        # Log which files were merged
        log.write(f"{isolate}\t{out_r1.name}\t{'|'.join(r1_files)}\n")
        log.write(f"{isolate}\t{out_r2.name}\t{'|'.join(r2_files)}\n")
