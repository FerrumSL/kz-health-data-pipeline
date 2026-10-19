# Latest raw snapshot of every source -> data/processed/indicators.csv.
# Raw files are never edited; all cleaning and unit conversion happens here.

PROCESSED <- "data/processed/indicators.csv"

tidy_all <- function(sources) {
  parts <- lapply(seq_len(nrow(sources)), function(i) {
    row <- sources[i, ]
    path <- latest_snapshot(row$source_id)
    if (is.na(path)) return(NULL)
    # A stored snapshot can stop parsing after sources.csv is edited; skip it so
    # the report is still written.
    df <- tryCatch(parser_for(row)(path, row), error = function(e) {
      warning("tidy: skipped ", row$source_id, ": ", conditionMessage(e), call. = FALSE)
      NULL
    })
    if (is.null(df)) return(NULL)
    data.frame(
      country = df$country,
      indicator = row$indicator,
      year = df$year,
      value = df$value * row$multiplier,
      unit = row$unit,
      source_id = row$source_id,
      publisher = row$publisher,
      snapshot_date = snapshot_date(path)
    )
  })
  out <- do.call(rbind, parts)
  out <- out[order(out$country, out$indicator, out$publisher, out$year), ]
  dir.create(dirname(PROCESSED), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(out, PROCESSED, na = "")
  out
}
