# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**openalexSnowball** is an R package implementing citation network "snowball searches" on the OpenAlex academic graph. Starting from seed papers (keypapers), it follows citation links outward to retrieve papers that cite or are cited by the seeds, building a network graph stored as Apache Parquet files for memory-efficient on-disk processing.

## Common Commands

```r
# Load package for interactive development
devtools::load_all()

# Run full R CMD check
devtools::check()

# Run all tests
devtools::test()

# Run a single test file
devtools::test(filter = "pro_snowball")

# Test coverage
covr::package_coverage()

# Rebuild documentation (Roxygen2)
devtools::document()
```

## Architecture

### Core Pipeline (4 functions)

1. **`pro_snowball()`** — Top-level orchestrator. Accepts `identifier` (OpenAlex IDs) or `doi` (mutually exclusive). Returns path to the output directory.

2. **`pro_snowball_get_nodes()`** — Phase 1: Retrieves keypapers + their citing/cited papers from the OpenAlex API via `openalexPro::pro_query()`. Writes partitioned parquet at `output/nodes/` with a `relation` column (`keypaper`, `citing`, `cited`). Each retrieval stage goes through: API → JSON files → JSONL → Parquet.

3. **`pro_snowball_extract_edges()`** — Phase 2: Loads the nodes parquet into DuckDB, executes `inst/extract_edges.sql`, and writes partitioned parquet at `output/edges/` with an `edge_type` column.

4. **`read_snowball()`** — Reads a completed snowball result directory; returns a list with `nodes` and `edges` as either Arrow Datasets (default, on-disk) or tibbles (`return_data = TRUE`). Supports filtering by `edge_type`.

### Edge Classification (in `inst/extract_edges.sql`)

Three mutually-useful edge types:
- `core` — at least one endpoint is a keypaper AND both endpoints are in the dataset
- `extended` — both endpoints are in the dataset (superset of core)
- `outside` — at least one endpoint is external to the dataset

### Key Design Patterns

- **On-disk processing**: Arrow + DuckDB throughout; data is never fully loaded into R memory during the pipeline.
- **Dependency on openalexPro**: `openalexPro` (>= 0.4.0) handles all API communication and JSON→Parquet conversion. openalexSnowball orchestrates calls to it.
- **NSE**: Uses `rlang` `.data` and `.env` pronouns in dplyr chains.

## Testing

Tests live in `tests/testthat/` and use VCR cassettes (`tests/fixtures/vcr/`) to mock all OpenAlex API calls — no live network requests needed during testing.

- `helper_vcr.R` configures cassette paths and filters sensitive headers (`api_key`, `Authorization`).
- Tests compare output against the reference implementation `openalexR::oa_snowball()`.
- Snapshot files are in `tests/testthat/_snaps/`.

When adding or updating tests that involve API calls, record new VCR cassettes rather than making live requests.

## CI/CD

| Workflow | Trigger | Purpose |
|---|---|---|
| `R-CMD-check.yaml` | push to main/dev, PRs | Matrix check across macOS, Windows, Ubuntu × R versions |
| `test-coverage.yaml` | push to main/master, PRs | Codecov coverage reporting |
| `pkgdown.yaml` | — | Builds documentation site |
| `rhub.yaml` | — | R-hub comprehensive environment checks |

## Notes

- Vignettes use Quarto (`.qmd`) with `execute: eval: false` to avoid live API calls during package builds.
- The `.vscode/settings.json` configures a DuckDB SQLTools connection for interactive SQL development against the in-memory DuckDB engine.
- Code and documentation in this repository have been generated with LLM assistance and reviewed by humans.
