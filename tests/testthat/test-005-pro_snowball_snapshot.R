# Offline snowball: pro_snowball(snapshot = ...).
#
# No network and no VCR cassettes -- the whole point is that this path never
# touches the API.

test_that("snapshot mode produces the same construct as the API path", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir()
  unlink(out, recursive = TRUE)

  res <- pro_snowball(identifier = f$ids[c(1, 4)], snapshot = f$root,
                      output = out, verbose = FALSE)

  expect_equal(res, normalizePath(out))
  # nodes/, edges/ and the provenance sidecar; all intermediates cleaned up
  expect_setequal(list.files(res),
                  c("nodes", "edges", "snowball_meta.parquet"))

  expect_setequal(
    list.files(file.path(res, "nodes")),
    c("relation=keypaper", "relation=citing", "relation=cited")
  )
  expect_true(all(list.files(file.path(res, "edges")) %in%
                    c("edge_type=core", "edge_type=extended", "edge_type=outside")))
})

test_that("read_snowball() reads the offline construct unmodified", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  res <- pro_snowball(identifier = f$ids[c(1, 4)], snapshot = f$root,
                      output = out, verbose = FALSE)

  sb <- read_snowball(res, return_data = TRUE, shorten_ids = TRUE)
  expect_named(sb, c("nodes", "edges"))
  expect_equal(sort(names(sb$edges)), c("edge_type", "from", "to"))
  expect_gt(nrow(sb$nodes), 0L)

  # oa_input is BOOLEAN after assembly, TRUE for exactly the keypapers
  expect_type(sb$nodes$oa_input, "logical")
  expect_setequal(sb$nodes$id[sb$nodes$oa_input], f$ids[c(1, 4)])

  # every edge_type filter combination works
  for (et in list("core", "extended", "outside", c("core", "extended"))) {
    expect_no_error(read_snowball(res, return_data = TRUE, edge_type = et))
  }
})

test_that("the three edge_type classes are mutually exclusive", {
  # The implementation in inst/extract_edges.sql makes them exclusive, while
  # ?read_snowball describes extended as a superset of core. This test pins the
  # actual behaviour so a future fix to either fails loudly rather than
  # changing semantics silently.
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  res <- pro_snowball(identifier = f$ids[c(1, 4)], snapshot = f$root,
                      output = out, verbose = FALSE)

  n <- function(et) nrow(read_snowball(res, return_data = TRUE,
                                       edge_type = et)$edges)
  expect_equal(n("core") + n("extended"), n(c("core", "extended")))
  expect_equal(n("core") + n("extended") + n("outside"),
               n(c("core", "extended", "outside")))
})

test_that("edges orient as A cites B and come only from referenced_works", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  res <- pro_snowball(identifier = f$ids[1], snapshot = f$root,
                      output = out, verbose = FALSE)

  sb <- read_snowball(res, return_data = TRUE, shorten_ids = TRUE)
  # `from` is always a node in the dataset; `to` may be outside it
  expect_true(all(sb$edges$from %in% sb$nodes$id))
  expect_true(any(!sb$edges$to %in% sb$nodes$id))   # the dangling refs
})

test_that("snapshot nodes use the snapshot-native schema", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  res <- pro_snowball(identifier = f$ids[1], snapshot = f$root,
                      output = out, verbose = FALSE)

  sb <- read_snowball(res, return_data = TRUE)
  # `page` is an API pagination artefact with no snapshot analogue; it is
  # deliberately absent rather than faked. Documented in ?pro_snowball.
  expect_false("page" %in% names(sb$nodes))
  expect_true(all(c("id", "oa_input", "relation", "referenced_works") %in%
                    names(sb$nodes)))
})

test_that("keypapers may be given as DOIs, with or without a resolver", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)

  # The second is a real SICI DOI containing [ ], supplied with a resolver:
  # it exercises DOI normalisation end to end through the whole snowball.
  res <- pro_snowball(
    doi = c("10.1234/test.1",
            "https://doi.org/10.1577/1548-8659(1973)35[142:amosss]2.0.co;2"),
    snapshot = f$root, output = out, verbose = FALSE)
  sb <- read_snowball(res, return_data = TRUE, shorten_ids = TRUE)
  expect_setequal(sb$nodes$id[sb$nodes$oa_input], f$ids[c(1, 4)])
})

test_that("a keypaper absent from the snapshot warns rather than vanishing", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)

  expect_warning(
    pro_snowball(identifier = c(f$ids[1], "W999999999"), snapshot = f$root,
                 output = out, verbose = FALSE),
    "not present in the snapshot"
  )
})

test_that("no resolvable keypaper is an error, not an empty snowball", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)

  expect_error(
    pro_snowball(identifier = "W999999999", snapshot = f$root, output = out,
                 verbose = FALSE),
    "None of the keypapers"
  )
})

test_that("snapshot may be given as a root_dir or as the parquet dir", {
  f <- make_snapshot_fixture()
  root_dir <- dirname(f$root)

  o1 <- withr::local_tempdir(); unlink(o1, recursive = TRUE)
  o2 <- withr::local_tempdir(); unlink(o2, recursive = TRUE)
  a <- pro_snowball(identifier = f$ids[1], snapshot = f$root, output = o1,
                    verbose = FALSE)
  b <- pro_snowball(identifier = f$ids[1], snapshot = root_dir, output = o2,
                    verbose = FALSE)

  na <- read_snowball(a, return_data = TRUE)$nodes
  nb <- read_snowball(b, return_data = TRUE)$nodes
  expect_equal(sort(na$id), sort(nb$id))
})

test_that("a missing citation index names the builder that creates it", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  openalexSnapshot::build_corpus_index(corpus_dir = corpus, backend = "r",
                                       verbose = FALSE)
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)

  expect_error(
    pro_snowball(identifier = tiny_ids()[1], snapshot = file.path(tmp, "parquet"),
                 output = out, verbose = FALSE),
    "build_citation_index"
  )
})


test_that("provenance records the mode and the snapshot vintage", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  res <- pro_snowball(identifier = f$ids[1], snapshot = f$root, output = out,
                      verbose = FALSE)

  # opt-in: the default shape is unchanged
  expect_named(read_snowball(res, return_data = TRUE), c("nodes", "edges"))

  sb <- read_snowball(res, return_data = TRUE, meta = TRUE)
  expect_true("meta" %in% names(sb))
  expect_equal(sb$meta$mode, "snapshot")
  expect_equal(sb$meta$snapshot_root, f$root)
  # the vintage of the index the results are frozen at
  expect_false(is.na(sb$meta$snapshot_built_at))
  expect_match(sb$meta$keypapers, f$ids[1])

  # $nodes and $edges keep their positions
  expect_equal(names(sb)[1:2], c("nodes", "edges"))
})


test_that("chunk_limit adapts to the worker count, and is inert at workers = 1", {
  cl <- openalexSnowball:::.chunk_limit_for

  # unchanged default when sequential: pro_query()'s own default is 50
  expect_equal(cl(1000, workers = 1L), 50L)
  expect_equal(cl(10, workers = NULL), 50L)

  # ~2x as many chunks as workers, so the scheduler has slack to balance with
  expect_equal(cl(1200, workers = 6L), 50L)   # capped: 100 -> 50
  expect_equal(cl(240,  workers = 6L), 20L)   # 240/(2*6) = 20 -> 12 chunks
  expect_equal(cl(120,  workers = 6L), 10L)   # 120/(2*6) = 10 -> 12 chunks

  # floored at 10: every chunk pays its own request and cursor setup
  expect_equal(cl(12, workers = 6L), 10L)
  expect_gte(cl(1, workers = 64L), 10L)

  # explicit override always wins
  expect_equal(cl(1000, workers = 6L, override = 25), 25L)
})


test_that("select= projects node columns and always keeps the structural ones", {
  f <- make_snapshot_fixture()
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)

  res <- pro_snowball(identifier = f$ids[c(1, 4)], snapshot = f$root,
                      select = "title", output = out, verbose = FALSE)
  sb <- read_snowball(res, return_data = TRUE)

  # id and referenced_works are retained regardless: the first identifies
  # nodes, the second is what the edge extraction unnests.
  expect_true(all(c("id", "referenced_works", "title") %in% names(sb$nodes)))
  expect_false("publication_year" %in% names(sb$nodes))

  # and the construct is still complete
  expect_gt(nrow(sb$edges), 0L)
  expect_setequal(sb$nodes$id[sb$nodes$oa_input],
                  paste0("https://openalex.org/", f$ids[c(1, 4)]))
})


test_that(".snapshot_index() knows which indexes are files and which are directories", {
  # Regression: this helper kept building "<name>_id_idx.parquet" after the ID
  # index became a hive directory. Every offline snowball against a real
  # snapshot failed with "No id index at ...works_id_idx.parquet", while the
  # whole suite stayed green -- the fixtures build their indexes fresh in
  # tempdir() and never exercise the helper.
  si <- openalexSnowball:::.snapshot_index

  # the ID index is a DIRECTORY; the DOI index is still a single file
  expect_equal(basename(si("/snap/parquet", "id")),  "works_id_idx")
  expect_equal(basename(si("/snap/parquet", "doi")), "works_doi_idx.parquet")
  expect_false(grepl("\\.parquet$", si("/snap/parquet", "id")))

  # accepts the parquet dir itself, or a root containing one
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "parquet"), recursive = TRUE)
  expect_equal(si(tmp, "id"), file.path(tmp, "parquet", "works_id_idx"))
  expect_equal(si(file.path(tmp, "parquet"), "id"),
               file.path(tmp, "parquet", "works_id_idx"))

  expect_error(si("/snap/parquet", "nonsense"))
})

test_that("worker arguments are validated and mapped to each callee's convention", {
  # pro_request() takes workers = 1 for sequential; pro_request_parquet() and
  # openalexSnapshot's functions take NULL. .par_workers() holds that mapping in
  # one place so call sites cannot drift apart.
  pw <- openalexSnowball:::.par_workers
  expect_null(pw(1L));  expect_null(pw(1));  expect_null(pw(NULL))
  expect_equal(pw(6L), 6L)
  expect_type(pw(6), "integer")

  cw <- openalexSnowball:::.check_workers
  expect_equal(cw(1), 1L)
  expect_equal(cw(8L), 8L)
  for (bad in list(0, -1, 2.5, NA, "6", c(1, 2), integer(0))) {
    expect_error(cw(bad), "single positive whole number")
  }
})

test_that("pro_snowball() rejects a bad workers value before doing any work", {
  out <- withr::local_tempdir(); unlink(out, recursive = TRUE)
  expect_error(pro_snowball(identifier = "W1", workers = 0, output = out),
               "single positive whole number")
  expect_false(dir.exists(out))   # failed before creating anything
})
