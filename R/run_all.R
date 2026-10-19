# Entry point: Rscript R/run_all.R (from the repository root).
# Reads sources.csv, fetches every source, saves changed snapshots, logs each
# result, rebuilds the panel, runs the consistency check and writes the report.
# Exits non-zero if any source failed or changed schema, after writing the report.

for (f in c("utils.R", "fetch_gho.R", "fetch_worldbank.R", "fetch_bns.R", "tidy.R", "check_consistency.R", "report.R")) {
  source(file.path("R", f))
}

EXT <- c(api_json = ".json", xlsx_download = ".xlsx")

sources <- readr::read_csv("sources.csv", col_types = readr::cols(.default = "c"))
sources$multiplier <- parse_multiplier(sources$multiplier)
stopifnot(!anyNA(sources[setdiff(names(sources), "selector")]),
          all(!is.na(sources$selector) | sources$access_method != "xlsx_download"),
          !anyDuplicated(sources$source_id), all(sources$access_method %in% names(EXT)))
run_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")

run_one <- function(row) {
  ext <- EXT[[row$access_method]]
  tryCatch({
    tmp <- match.fun(paste0("fetch_", row$publisher))(row)
    on.exit(unlink(tmp))
    # Parse before saving: a file that fails the schema check is never stored.
    parsed <- parser_for(row)(tmp, row)
    saved <- save_if_changed(tmp, row$source_id, ext, as.Date(run_at))
    list(status = saved$status, rows = nrow(parsed), hash = saved$hash, message = "")
  },
  schema_changed = function(e) list(status = "schema_changed", rows = NA, hash = "", message = conditionMessage(e)),
  error = function(e) list(status = "failed", rows = NA, hash = "", message = conditionMessage(e)))
}

for (i in seq_len(nrow(sources))) {
  row <- sources[i, ]
  r <- run_one(row)
  message(sprintf("%-10s %-15s %s", row$source_id, r$status, r$message))
  append_run_log(data.frame(run_at = run_at, source_id = row$source_id, status = r$status,
                            rows = r$rows, hash = r$hash, message = gsub("[\r\n]+", " ", r$message)))
}

panel <- tidy_all(sources)
consistency <- check_consistency(panel)
log <- readr::read_csv(RUN_LOG, col_types = readr::cols(.default = "c"))
write_report(sources, log, panel, consistency, run_at)

bad <- log$status[log$run_at == run_at] %in% c("failed", "schema_changed")
if (any(bad)) {
  message(sum(bad), " source(s) failed or changed schema; see ", STATUS_MD)
  quit(status = 1)
}
