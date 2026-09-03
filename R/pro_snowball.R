#' A function to perform a snowball search and convert the result to a
#' tibble/data frame.
#' @param identifier Character vector of openalex identifiers.
#' @param doi Character vector of dois.
#' @param snapshot Path to a local OpenAlex snapshot (either a root directory
#'   containing `parquet/`, or the `parquet/` directory itself). When supplied,
#'   the whole snowball is built **offline** from the snapshot instead of the
#'   OpenAlex API; when `NULL` (the default) behaviour is unchanged.
#'
#'   Snapshot mode requires the indexes built by
#'   `openalexSnapshot::build_corpus_index()` and
#'   `openalexSnapshot::build_citation_index()`, plus
#'   `openalexSnapshot::build_doi_index()` if keypapers are given as DOIs.
#'
#'   The output construct is identical -- `nodes/` and `edges/` partitioned the
#'   same way, readable by [read_snowball()] -- but the **node columns differ**,
#'   because snapshot records are not API records. Snapshot nodes carry
#'   whatever the works corpus holds plus `oa_input` and `relation`; there is no
#'   `page` column, which is an API pagination artefact. Results are also frozen
#'   at the snapshot's vintage rather than live.
#' @param max_results Snapshot mode only: refuse to expand a keypaper with more
#'   citing works than this. A heavily cited work can have hundreds of thousands
#'   of citers, and extracting records for all of them would read most of the
#'   corpus.
#' @param workers Number of parallel workers. Default `1`, which is sequential
#'   and reproduces the previous behaviour exactly.
#'
#'   Both paths gain from raising it, but in different places. **API mode**
#'   parallelises across the chunked query URLs -- `pro_query()` chunks
#'   `cites`/`cited_by` at 50 ids, so a snowball over many keypapers becomes
#'   many URLs that were previously fetched one at a time -- and across the
#'   JSON-to-parquet conversion. **Snapshot mode** parallelises reading the
#'   corpus files that the node set is scattered over, which is the dominant
#'   cost once the result set is large.
#'
#'   Raising it buys little for a snowball over a handful of keypapers, where
#'   fixed costs dominate; it matters at hundreds or thousands. Be aware that
#'   in API mode more workers means more concurrent requests, so keep it
#'   within the OpenAlex rate limit for your key.
#' @param chunk_limit API mode only: how many keypaper ids go into one filter
#'   URL. `NULL` (the default) derives a value from `workers`.
#'
#'   `openalexPro::pro_query()` splits `cites`/`cited_by` filters into URLs of
#'   `chunk_limit` ids, and `pro_request()` fetches those URLs in parallel --
#'   but `pro_query()` has no knowledge of `workers`, so the fixed 50-id
#'   default can leave workers idle: 100 keypapers over 6 workers is two chunks
#'   and four idle processes. The derived value targets roughly twice as many
#'   chunks as workers, giving the scheduler slack to balance with, since
#'   chunks are split by id count while cost follows result volume.
#'
#'   At `workers = 1` the derived value is 50, so behaviour is unchanged.
#' @param select Snapshot mode only: which node columns to keep. `NULL` (the
#'   default) keeps every column the corpus holds, matching the API path.
#'
#'   This is the single biggest cost in snapshot mode. Works records carry ~51
#'   columns of deeply nested structs, and extracting all of them dominates the
#'   run: measured over 427 nodes, **177.8 s for all columns against 16.7 s for
#'   three** -- a 10.6x difference, or 20.3x combined with `workers = 6`. If you
#'   only need the citation graph and a little metadata, name those columns.
#'
#'   `id` and `referenced_works` are always retained regardless: the first
#'   identifies nodes, the second is what the edge extraction unnests.
#' @param output parquet dataset; default: temporary directory.
#' @param verbose Logical indicating whether to show a verbose information.
#'   Defaults to `FALSE`
#'
#' @return The folder of the results containing multiple subfolders.
#'
#' @export
#'
#' @importFrom duckdb duckdb duckdb_register_arrow
#' @importFrom DBI dbConnect dbDisconnect dbExecute
#' @importFrom arrow write_parquet
#'
#' @md
#'
pro_snowball <- function(
  identifier = NULL,
  doi = NULL,
  snapshot = NULL,
  max_results = 100000L,
  workers = 1L,
  chunk_limit = NULL,
  select = NULL,
  output = tempfile(fileext = ".snowball"),
  verbose = FALSE
) {
  workers <- .check_workers(workers)
  if (!xor(is.null(identifier), is.null(doi))) {
    stop("Either `identifier` or `doi` needs to be specified!")
  }

  output <- normalizePath(output, mustWork = FALSE)

  if (dir.exists(output)) {
    if (verbose) {
      message(
        "Deleting and recreating `",
        output,
        "` to avoid inconsistencies."
      )
    }
    unlink(output, recursive = TRUE)
    dir.create(output, recursive = TRUE)
  }

  nodes <- pro_snowball_get_nodes(
    identifier = identifier,
    doi = doi,
    snapshot = snapshot,
    max_results = max_results,
    workers = workers,
    chunk_limit = chunk_limit,
    select = select,
    output = output,
    verbose = verbose
  )
  edges <- pro_snowball_extract_edges(
    nodes = nodes,
    output = output,
    verbose = verbose
  )

  unlink(
    c(
      file.path(output, "keypaper_json"),
      file.path(output, "keypaper_jsonl")
    ),
    recursive = TRUE
  )

  # Return path to snowball ------------------------------------------------

  return(normalizePath(output))
}
