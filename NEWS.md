# openalexSnowball (development)

## Breaking Changes

* Minimum `openalexPro` version bumped from `>= 0.4.0` to `>= 0.4.2`.

## Bug Fixes

* `pro_snowball_get_nodes()`: fixed `pro_query()` call to use `id =` instead
  of the removed `openalex =` argument (renamed in openalexPro 0.4.1).
* `pro_snowball_extract_edges()`: replaced removed `openalexPro::load_sql_file()`
  with `readLines()` + `paste()` fed to `DBI::dbExecute()` directly
  (function removed in openalexPro 0.4.2; DuckDB handles multi-statement SQL
  natively).
* Test helper: replaced removed `oap_apikey()` / `oap_mail()` with
  `Sys.getenv/setenv("openalexPro.apikey")`.

# openalexSnowball 0.1.0

* Split snowball functions from openalexPro (<0.4)
