# World Bank Indicators API v2 (https://api.worldbank.org/v2/).
# The response is a two-element JSON array: [paging metadata, records].

WB_FIELDS <- c("countryiso3code", "date", "value")

fetch_worldbank <- function(row) {
  download_to_temp(httr2::request(fill_template(row)), ".json")
}

# Raw World Bank JSON -> data frame (country, year, value). Signals
# schema_changed if the response no longer looks like [metadata, records].
parse_worldbank <- function(path, row) {
  id <- row$source_id
  json <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  # Errors (e.g. an unknown indicator code) come back as a one-element array.
  if (!is.list(json) || length(json) != 2) schema_error(id, "expected [metadata, records]")
  meta <- json[[1]]
  require_fields(meta, c("pages", "total"), id)
  if (meta$pages != 1) schema_error(id, sprintf("%s pages; raise per_page", meta$pages))
  v <- json[[2]]
  if (!is.data.frame(v) || nrow(v) == 0) schema_error(id, "empty records array")
  require_fields(v, WB_FIELDS, id)
  if (nrow(v) != meta$total) schema_error(id, "record count does not match metadata total")
  if (!all(grepl("^[0-9]{4}$", v$date))) schema_error(id, "non-annual 'date' values")
  if (!identical(unique(v$indicator$id), row$source_code)) schema_error(id, "unexpected indicator id")
  out <- data.frame(
    country = v$countryiso3code,
    year = as.integer(v$date),
    value = as.numeric(v$value)
  )
  out <- out[!is.na(out$value), ]
  if (nrow(out) == 0) schema_error(id, "no numeric values")
  extra <- setdiff(out$country, split_countries(row$countries))
  if (length(extra) > 0) schema_error(id, paste("unrequested countries:", paste(extra, collapse = ", ")))
  require_unique(out, id)
  out
}
