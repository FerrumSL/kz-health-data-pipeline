# Shared helpers: schema errors, HTTP download, dated raw snapshots, run log.

RAW_DIR <- "data/raw"
RUN_LOG <- "data/run_log.csv"

# Signal a schema change as its own condition class, so callers can tell it
# apart from network or other failures.
schema_error <- function(source_id, msg) {
  stop(structure(
    class = c("schema_changed", "error", "condition"),
    list(message = sprintf("[%s] schema changed: %s", source_id, msg), call = NULL)
  ))
}

require_fields <- function(x, fields, source_id) {
  missing <- setdiff(fields, names(x))
  if (length(missing) > 0) {
    schema_error(source_id, paste("missing field(s):", paste(missing, collapse = ", ")))
  }
}

# Fail if the parsed panel has more than one value per country and year.
require_unique <- function(df, source_id) {
  dup <- duplicated(df[c("country", "year")])
  if (any(dup)) {
    schema_error(source_id, sprintf("%d duplicate country-year rows", sum(dup)))
  }
}

# Unit conversion factors in sources.csv are a number or an exact ratio such
# as "1/12" (months to years), so no rounded constant is ever typed by hand.
parse_multiplier <- function(x) {
  ok <- grepl("^[0-9.]+(/[0-9.]+)?$", x)
  if (!all(ok)) stop("bad multiplier in sources.csv: ", paste(x[!ok], collapse = ", "))
  vapply(strsplit(x, "/", fixed = TRUE), function(p) {
    n <- as.numeric(p)
    if (length(n) == 2) n[1] / n[2] else n
  }, numeric(1))
}

# Parser for a sources.csv row: parse_<publisher>, or parse_<publisher>_xlsx for
# spreadsheet downloads.
parser_for <- function(row) {
  match.fun(paste0("parse_", row$publisher, if (row$access_method == "xlsx_download") "_xlsx" else ""))
}

split_countries <- function(countries) strsplit(countries, ";", fixed = TRUE)[[1]]

fill_template <- function(row) {
  url <- gsub("{code}", row$source_code, row$url_template, fixed = TRUE)
  gsub("{countries}", row$countries, url, fixed = TRUE)
}

# Download a request to a temporary file and return its path.
download_to_temp <- function(req, ext) {
  path <- tempfile(fileext = ext)
  req |>
    httr2::req_user_agent("kz-health-data-pipeline (https://github.com/FerrumSL/kz-health-data-pipeline)") |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform(path = path)
  path
}

file_hash <- function(path) digest::digest(file = path, algo = "sha256")

# Most recent snapshot file for a source, or NA if none exists yet.
# Snapshot folders are ISO dates, so lexical order is chronological order.
latest_snapshot <- function(source_id) {
  dirs <- sort(list.dirs(file.path(RAW_DIR, source_id), recursive = FALSE))
  if (length(dirs) == 0) return(NA_character_)
  files <- list.files(dirs[length(dirs)], full.names = TRUE)
  if (length(files) != 1) stop("expected exactly one file in ", dirs[length(dirs)])
  files
}

snapshot_date <- function(path) basename(dirname(path))

# Save the temp file as today's snapshot unless it is identical to the latest one.
# Returns list(status = "updated" | "unchanged", hash, path).
save_if_changed <- function(tmp, source_id, ext, today = Sys.Date()) {
  hash <- file_hash(tmp)
  prev <- latest_snapshot(source_id)
  if (!is.na(prev) && file_hash(prev) == hash) {
    return(list(status = "unchanged", hash = hash, path = prev))
  }
  dir <- file.path(RAW_DIR, source_id, format(today, "%Y-%m-%d"))
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dir, paste0(source_id, ext))
  if (!file.copy(tmp, dest, overwrite = TRUE)) stop("could not write ", dest)
  list(status = "updated", hash = hash, path = dest)
}

append_run_log <- function(entry) {
  readr::write_csv(entry, RUN_LOG, append = file.exists(RUN_LOG), na = "")
}
