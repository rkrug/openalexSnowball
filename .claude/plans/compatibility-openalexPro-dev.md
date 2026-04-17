# Plan: Fix openalexSnowball compatibility with openalexPro dev (v0.8.0)

## Context

openalexPro's dev branch (v0.8.0) removed two functions that openalexSnowball calls directly:
`load_sql_file()` and `oap_apikey()`/`oap_mail()`. These are hard runtime errors.
The `pro_query()` API also changed — old named params (`openalex`, `doi`, `cites`, `cited_by`)
are no longer explicit parameters but still work via `...` as filter arguments, so no change
is needed there. All other used functions (`pro_request`, `pro_request_jsonl`,
`pro_request_jsonl_parquet`, `read_corpus`) are fully compatible.

---

## Issues and Fixes

### 1. `openalexPro::load_sql_file()` removed — CRITICAL
**File**: `R/pro_snowball_extract_edges.R`, lines 79–81

**Current**:
```r
system.file("extract_edges.sql", package = "openalexSnowball") |>
  openalexPro::load_sql_file() |>
  DBI::dbExecute(conn = con)
```

**Fix** — replace with base R (reads file, collapses to single string):
```r
sql <- system.file("extract_edges.sql", package = "openalexSnowball") |>
  readLines() |>
  paste(collapse = "\n")
DBI::dbExecute(conn = con, sql)
```

No new imports needed — `readLines` and `paste` are base R.

---

### 2. `openalexPro::oap_apikey()` and `openalexPro::oap_mail()` removed — breaks test setup
**File**: `tests/testthat/helper_vcr.R`, lines 20–25

**Current**:
```r
if (is.null(openalexPro::oap_apikey())) {
  options(openalexR.apikey = "<api-key>")
}
if (is.null(openalexPro::oap_mail())) {
  options(openalexR.mailto = "rainer@krugs.de")
}
```

**Fix** — check the R options directly (no openalexPro dependency):
```r
if (is.null(getOption("openalexR.apikey"))) {
  options(openalexR.apikey = "<api-key>")
}
if (is.null(getOption("openalexR.mailto"))) {
  options(openalexR.mailto = "rainer@krugs.de")
}
```

---

### 3. `DESCRIPTION` version constraint — update to reflect minimum compatible version
**File**: `DESCRIPTION`, line 15

**Current**: `openalexPro (>= 0.4.0)`
**Fix**: `openalexPro (>= 0.8.0)`

The API surface changed significantly between 0.4.x and 0.8.0; the old constraint would
allow installing a version that is now incompatible.

---

### 4. `NEWS.md` — record the compatibility update

Add an entry describing the minimum openalexPro version bump and the removed-function adaptations.

---

## Files to modify

| File | Lines | Change |
|---|---|---|
| `R/pro_snowball_extract_edges.R` | 79–81 | Replace `load_sql_file()` with `readLines` + `paste` |
| `tests/testthat/helper_vcr.R` | 20–25 | Replace `oap_apikey()`/`oap_mail()` with `getOption()` |
| `DESCRIPTION` | 15 | Bump `openalexPro (>= 0.4.0)` → `(>= 0.8.0)` |
| `NEWS.md` | top | Add changelog entry |

---

## Out of scope

- `pro_query()` calls in `pro_snowball_get_nodes.R`: the four calls still work unchanged
  because the old parameter names (`openalex`, `doi`, `cites`, `cited_by`) pass through
  `...` as filter arguments in the new API.
- Pre-existing `ifelse()` misuse in `pro_snowball_get_nodes.R` (lines 73–83): separate bug,
  not caused by the openalexPro upgrade.
- VCR cassettes: the recorded URLs use `filter=openalex:W...` which the new `pro_query()`
  still generates, so no re-recording is needed.

---

## Verification

```r
# 1. Load and check for errors
devtools::load_all()

# 2. Run the test suite (uses VCR cassettes — no live network needed)
devtools::test()

# 3. Full package check
devtools::check()
```

Expected: all tests pass, no errors referencing `load_sql_file`, `oap_apikey`, or `oap_mail`.
