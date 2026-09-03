#' A function to get the nodes for a snowball search
#' @param identifier Character vector of openalex identifiers.
#' @param doi Character vector of dois.
#' @param limit If `citedOnly` only works cited by the keypaper are retrieved,
#'   `citingOnly` retrieves only works citing the keypaper. Default: `NULL`
#'   where all will be retrieved. 'none' is equal to `NULL`
#' @param snapshot Path to a local OpenAlex snapshot (either a root directory
#'   containing `parquet/`, or the `parquet/` directory itself). When supplied,
#'   nodes are gathered offline from the snapshot instead of the OpenAlex API.
#'   Requires the indexes built by `openalexSnapshot::build_corpus_index()` and
#'   `build_citation_index()`. Default `NULL` (use the API).
#' @param max_results Snapshot mode only: refuse to expand a keypaper with more
#'   citing works than this. See `openalexSnapshot::get_citing()`.
#' @param workers Number of parallel workers. Default `1` (sequential).
#' @param chunk_limit API mode only: ids per filter URL. `NULL` (default)
#'   derives one from `workers`; see `pro_snowball()`.
#' @param select Snapshot mode only: node columns to keep. See `pro_snowball()`.
#' @param output parquet dataset; default: temporary directory.
#' @param verbose Logical indicating whether to show a verbose information.
#'   Defaults to `FALSE`
#'
#' @return Path to the nodes parquet dataset
#'
#' @export
#'
#' @importFrom duckdb duckdb
#' @importFrom DBI dbConnect dbDisconnect dbExecute dbGetQuery
#'
#' @md
#'
pro_snowball_get_nodes <- function(
  identifier = NULL,
  doi = NULL,
  limit = NULL,
  snapshot = NULL,
  max_results = 100000L,
  workers = 1L,
  chunk_limit = NULL,
  select = NULL,
  output = tempfile(fileext = ".snowball"),
  verbose = FALSE
) {
  workers <- .check_workers(workers)
  if (is.null(limit)) {
    limit <- "none"
  }

  if (!(limit %in% c("onlyCiting", "onlyCited", "none"))) {
    stop("`limit` has to be `NULL`, 'onlyCited' or 'onlyCiting'!")
  }

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
  }
  dir.create(output, recursive = TRUE)

  # Create and setup in memory DuckDB --------------------------------------

  con <- DBI::dbConnect(duckdb::duckdb())

  on.exit(
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE),
    add = TRUE
  )

  # Gather nodes: from the snapshot when one is given, else from the API ----

  if (is.null(snapshot)) {
    if (verbose) message("Collecting keypapers...")

    qu <- if (!is.null(identifier)) {
      openalexPro::pro_query(id = identifier, entity = "works")
    } else {
      openalexPro::pro_query(doi = doi, entity = "works")
    }
    openalexPro::pro_request(
      query_url = qu,
      output = file.path(output, "keypaper_json"),
      verbose = verbose,
      progress = verbose
    ) |>
      openalexPro::pro_request_parquet(
        output = file.path(output, "keypaper_parquet"),
        add_columns = list(oa_input = "TRUE", relation = "keypaper"),
        verbose = verbose
      )

    # A keypaper present locally may no longer resolve through the API -- works
    # get merged or withdrawn, and the API returns nothing for the old id.
    # Without this check the next statement fails with a bare DuckDB glob
    # error naming a temp path, which says nothing about the cause.
    kp_dir <- file.path(output, "keypaper_parquet")
    if (!dir.exists(kp_dir) ||
        length(list.files(kp_dir, pattern = "\\.parquet$", recursive = TRUE)) == 0L) {
      stop("The OpenAlex API returned no records for the requested keypaper(s): ",
           paste(utils::head(if (!is.null(identifier)) identifier else doi, 5L),
                 collapse = ", "),
           ".\nThey may have been merged or withdrawn since. Check them at ",
           "https://api.openalex.org/works?filter=openalex:<id>",
           call. = FALSE)
    }

    keypaper_ids <- sprintf(
      "
      SELECT
        id
      FROM
        read_parquet( '%s/**/*.parquet' )
      ",
      kp_dir
    ) |>
      DBI::dbGetQuery(conn = con) |>
      unlist() |>
      as.vector()

    .nodes_from_api(keypaper_ids, output, limit, verbose, workers = workers,
                    chunk_limit = chunk_limit)
  } else {
    if (verbose) message("Resolving keypapers against the snapshot ...")
    keypaper_ids <- .keypaper_ids_snapshot(identifier, doi, snapshot, verbose)
    if (length(keypaper_ids) == 0L) {
      stop("No keypapers could be resolved against the snapshot.", call. = FALSE)
    }
    .nodes_from_snapshot(keypaper_ids, snapshot, output, limit, verbose,
                         max_results = max_results, workers = workers,
                         select = select)
  }

  .write_snowball_meta(
    output,
    mode      = if (is.null(snapshot)) "api" else "snapshot",
    snapshot  = snapshot,
    keypapers = keypaper_ids,
    limit     = limit
  )

  # Combine individual parquet files to nodes parquet ----------------------

  .assemble_nodes(output, con = con, verbose = verbose)

  # Cleanup intermediate directories --------------------------------------

  unlink(file.path(output, "keypaper_json"), recursive = TRUE)
  unlink(file.path(output, "keypaper_parquet"), recursive = TRUE)
  unlink(file.path(output, "citing_json"), recursive = TRUE)
  unlink(file.path(output, "citing_parquet"), recursive = TRUE)
  unlink(file.path(output, "cited_json"), recursive = TRUE)
  unlink(file.path(output, "cited_parquet"), recursive = TRUE)

  # Return path to nodes ------------------------------------------------

  return(normalizePath(file.path(output, "nodes")))
}
