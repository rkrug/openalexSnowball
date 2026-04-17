# Snowball Searches

## 1 Overview

`openalexSnowball` provides snowball search utilities that build on the
`openalexPro` pipeline. A snowball search starts from a set of key
papers and follows citation links to collect cited and citing works.
Results are stored on disk as parquet datasets and can be loaded back
into R using
[`read_snowball()`](https://rkrug.github.io/openalexSnowball/reference/read_snowball.md).

## 2 Basic workflow

### 2.1 1. Define keypapers

Keypapers can be identified by OpenAlex IDs or DOIs.

### 2.2 2. Run a snowball search

``` r
snowball_dir <- "./snowball_ids"
pro_snowball(
  identifier = c("W2741809807", "W2755950973"),
  output = snowball_dir,
  verbose = TRUE
)
```

``` r
snowball_dir_dois <- "./snowball_dois"
pro_snowball(
  doi = c("10.1016/j.joi.2017.08.007", "10.7717/peerj.4375"),
  output = snowball_dir_dois,
  verbose = TRUE
)
```

## 3 Reading results

Use
[`read_snowball()`](https://rkrug.github.io/openalexSnowball/reference/read_snowball.md)
to load nodes and edges. The output can be an Arrow Dataset (default) or
collected into memory as tibbles.

``` r
snowball <- read_snowball(
  snowball = snowball_dir,
  edge_type = c("core", "extended"),
  return_data = TRUE,
  shorten_ids = TRUE
)

snowball$nodes
snowball$edges
```

## 4 Output layout

A snowball search writes a folder structure similar to the following:

    snowball/
    ├── cited_json/
    ├── cited_jsonl/
    ├── citing_json/
    ├── citing_jsonl/
    ├── edges/
    ├── keypaper_json/
    ├── keypaper_jsonl/
    ├── keypaper_parquet/
    └── nodes/

## 5 Tips

- Use `return_data = FALSE` to keep large datasets on disk.
- Use `edge_type = "core"` when you only need edges involving keypapers.
