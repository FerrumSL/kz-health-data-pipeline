# WHO Global Health Observatory, OData API (https://ghoapi.azureedge.net/api/).
# One request per indicator, filtered to the countries in sources.csv.

GHO_FIELDS <- c("SpatialDimType", "SpatialDim", "TimeDimType", "TimeDim", "Dim1", "NumericValue")

fetch_gho <- function(row) {
  countries <- split_countries(row$countries)
  filter <- sprintf("SpatialDim in (%s)", paste0("'", countries, "'", collapse = ","))
  req <- httr2::request(fill_template(row)) |>
    httr2::req_url_query(`$filter` = filter)
  download_to_temp(req, ".json")
}

# Raw GHO JSON -> data frame (country, year, value). Signals schema_changed
# if the response no longer looks like the documented OData shape.
parse_gho <- function(path, row) {
  id <- row$source_id
  json <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  if (!is.list(json) || !"value" %in% names(json)) schema_error(id, "no 'value' array")
  # The OData API pages with @odata.nextLink; one page would silently drop rows.
  if (!is.null(json[["@odata.nextLink"]])) schema_error(id, "response is paged")
  v <- json$value
  if (!is.data.frame(v) || nrow(v) == 0) schema_error(id, "empty 'value' array")
  require_fields(v, GHO_FIELDS, id)
  if (any(v$SpatialDimType != "COUNTRY") || any(v$TimeDimType != "YEAR")) {
    schema_error(id, "unexpected SpatialDimType or TimeDimType")
  }
  # Keep both-sexes rows; indicators without a sex breakdown have Dim1 = NA.
  v <- v[is.na(v$Dim1) | v$Dim1 == "SEX_BTSX", ]
  if (nrow(v) == 0) schema_error(id, "no both-sexes (SEX_BTSX) rows")
  # Some indicators also carry an age group (Dim2) or wealth quintile (Dim3).
  # Where a dimension has several values, keep its total (e.g. WEALTHQUINTILE_TOTL);
  # after that each dimension must have one value, or the series would be mixed.
  for (dim in intersect(c("Dim2", "Dim3"), names(v))) {
    if (length(unique(v[[dim]])) > 1) v <- v[grepl("_TOTL$", v[[dim]]), ]
    if (nrow(v) == 0 || length(unique(v[[dim]])) != 1) {
      schema_error(id, sprintf("%s has no single total value", dim))
    }
  }
  out <- data.frame(
    country = v$SpatialDim,
    year = as.integer(v$TimeDim),
    value = as.numeric(v$NumericValue)
  )
  out <- out[!is.na(out$value), ]
  if (nrow(out) == 0) schema_error(id, "no numeric values")
  extra <- setdiff(out$country, split_countries(row$countries))
  if (length(extra) > 0) schema_error(id, paste("unrequested countries:", paste(extra, collapse = ", ")))
  require_unique(out, id)
  out
}
