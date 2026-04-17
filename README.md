# fl-kraken2

**Flomics/fl-kraken2** is a Nextflow pipeline that downloads public/private sequencing data, trims reads, and performs taxonomic classification with Kraken2.

## Pipeline overview

```
Input TSV
   │
   ▼
DOWNLOAD_SAMPLE        — fetches FASTQs from ENA, SRA, or EGA
   │
   ▼
UMITOOLS_EXTRACT       — UMI extraction (UMI datasets only)
   │
   ▼
TRIMGALORE             — adapter trimming + FastQC
   │
   ▼
KRAKEN2                — taxonomic classification
```

## Input

A two-column, tab-separated file (no header):

```
SRR15618988       roskams_pilot
SRRISOLATE_2552   decru
X13031            ibarra_2022
SAMP12345678      prjeb90290_dataset
RNA020109_S115    ega_dataset
```

| Column | Description |
|--------|-------------|
| 1 | Accession ID (see supported types below) |
| 2 | Dataset label — controls download provider, trimming args, and UMI extraction |

### Supported accession types

| Pattern | Source | Notes |
|---------|--------|-------|
| `SRR<d>` | ENA / SRA | Plain SRA run accession |
| `SRRISOLATE_<d>` | SRA | Merges all runs for an isolate ID using `SraRunTable.csv` |
| `X<d>` | SRA | Merges runs via `isolate_to_runs.txt` |
| `SAMP<d>*` | ENA FTP | Downloads via wget using `ena_prjeb90290.tsv` |
| `RNA<d>_S<d>` | EGA | Downloads via pyega3 using `ega_files.tsv` + `credentials.json` |

## Usage

```bash
nextflow run Flomics/fl-kraken2 \
    --input  samples.tsv \
    --outdir results \
    --kraken2_db /path/to/kraken2_db \
    -profile singularity
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--input` | required | Path to input TSV |
| `--outdir` | `./results` | Output directory |
| `--kraken2_db` | S3 path (Flomics default) | Kraken2 database — directory or `.tar.gz` |
| `--phylo_kraken_full_report` | `true` | Also emit a per-read filtered report (read ID, NCBI tax ID, LCA hit list) |
| `--sra_run_table` | `k2_reprocessing/SraRunTable.csv` | Used by `SRRISOLATE_` strategy |
| `--isolate_to_runs` | `k2_reprocessing/isolate_to_runs.txt` | Used by `X`-series strategy |
| `--ena_prjeb90290_tsv` | `k2_reprocessing/ena_prjeb90290.tsv` | Used by `SAMP` strategy |
| `--ega_files_csv` | `k2_reprocessing/ega_files.tsv` | Used by `RNA` strategy |
| `--ega_credentials` | `k2_reprocessing/credentials.json` | Used by `RNA` strategy |

## Profiles

| Profile | Description |
|---------|-------------|
| `singularity` | Run with Singularity containers |
| `docker` | Run with Docker containers |
| `conda` | Run with Conda environments |

## Outputs

All outputs are written to `--outdir`:

```
results/
├── trimming/
│   └── <accession>/
│       ├── *.html                        # FastQC reports
│       ├── *.zip
│       └── *_trimming_report.txt
└── Flomics_Phylo/
    ├── *.kraken2.report.txt              # Standard Kraken2 report
    └── *.kraken2.filtered_report.tsv.gz  # Per-read: read_id, NCBI_tax_id, LCA_hitlist
```

## Dataset-specific behaviour

### Download provider

Datasets below use SRA as the download provider (bypassing ENA):

- `giraldez*`, `zhu`, `tao`, `roskams*`, `block*`, `ibarra*`, `ngo`

### UMI extraction

Datasets that require UMI extraction before trimming (8 nt UMI + 6 nt discard at 5' of R1):

- `decruyenaere`, `flomics_1`, `flomics_2`

### Two-colour chemistry (polyG trimming)

`--nextseq 20` is applied automatically for NextSeq/NovaSeq datasets:

- `block*`, `chalasani`, `decruyenaere`, `flomics_2`, `giraldez*`, `ibarra*`, `moufarrej*`, `ngo`, `reggiardo*`, `toden`, `wang`

## Requirements

- Nextflow >= 22.10.0
- Singularity, Docker, or Conda
- Kraken2 database (k2_pluspf or equivalent)
