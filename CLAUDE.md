# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package Overview

`openalexSnowball` is an R package for performing snowball citation searches on the [OpenAlex](https://openalex.org/) academic graph. Starting from seed papers ("keypapers"), it retrieves all citing and cited works, then extracts the citation network as nodes and edges stored in Parquet format. It is built on top of `openalexPro` (≥0.4.0) and processes large corpora without memory constraints by using disk-based storage.

## Common Commands

Run in an R session or via `Rscript -e`:

```r
# Document (regenerate NAMESPACE and Rd files)
roxygen2::roxygenise()

# Run all tests
devtools::test()

# Run a single test file
testthat::test_file("tests/testthat/test-004-pro_snowball.R")

# Check coverage
covr::package_coverage()

# Full package check
devtools::check()

# Build documentation site
pkgdown::build_site()
```

## Architecture

### Data Pipeline

```
Seed papers (OpenAlex ID or DOI)
  → pro_snowball()
      → pro_snowball_get_nodes()   # fetches papers via openalexPro
      → pro_snowball_extract_edges()  # SQL-based edge classification
  → Parquet dataset (output/nodes/ + output/edges/)
      → read_snowball()            # load as Arrow Dataset or tibble
```

### Core Files

| File | Role |
|------|------|
| `R/pro_snowball.R` | Main entry point; orchestrates the pipeline |
| `R/pro_snowball_get_nodes.R` | Retrieves keypapers + citing/cited works via openalexPro; writes nodes Parquet |
| `R/pro_snowball_extract_edges.R` | Reads nodes, runs DuckDB SQL to classify edges |
| `R/read_snowball.R` | Reads output Parquet as Arrow Dataset or collected tibble |
| `inst/extract_edges.sql` | DuckDB SQL that creates `keypaper`, `edges_basic`, and `edges` views; classifies edges as `core`, `extended`, or `outside` |

### Technology Stack

- **openalexPro**: Drives the `pro_query → pro_request → pro_request_jsonl` pipeline that fetches and converts OpenAlex API responses to Parquet
- **DuckDB**: In-process SQL engine used for aggregation in `pro_snowball_get_nodes` and for edge classification in `inst/extract_edges.sql`
- **Apache Arrow**: Parquet I/O and lazy columnar evaluation via `arrow::open_dataset()`
- **dplyr**: Tidy manipulation interface over Arrow/DuckDB

### Edge Types

Edges are classified by the SQL script into three types:
- **core**: edges directly from/to keypapers
- **extended**: all edges between collected papers (superset of core)
- **outside**: edges pointing to papers not in the nodes collection

### Testing

Tests use **testthat** (edition 3) with **VCR** for HTTP cassette replay. The main test file (`tests/testthat/test-004-pro_snowball.R`) validates output against `openalexR::oa_snowball()` as a reference implementation. VCR cassettes live in `tests/fixtures/`. The helper `tests/testthat/helper_vcr.R` configures VCR for the test suite.

## CI/CD

Four GitHub Actions workflows:
- **R-CMD-check.yaml**: matrix check across macOS/Windows/Ubuntu and R release/devel/oldrel-1
- **test-coverage.yaml**: coverage via `covr`, uploads to Codecov
- **pkgdown.yaml**: builds and deploys the documentation site to GitHub Pages
- **rhub.yaml**: additional R-hub platform checks
