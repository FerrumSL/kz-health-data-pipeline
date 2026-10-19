# Bureau of National Statistics of Kazakhstan (BNS). Two access methods:
#
# api_json: Taldau portal JSON export
#   (https://taldau.stat.gov.kz/ru/Api/GetIndexData/<index id>?period=7&dics=<dictionary ids>).
#   period=7 is annual. The dictionary ids are the indicator's breakdowns (region,
#   urban/rural, sex, ...) and come from the portal's segment list for that indicator.
#   The response is an array of series, one per combination of breakdown terms:
#     [{"terms": [...], "termNames": [...], "periods": [{"name", "date", "value"}]}]
#
# xlsx_download: XLSX files from stat.gov.kz ("open data" and "dynamic tables"),
#   https://stat.gov.kz/api/iblock/element/<element id>/file/ru/ (redirects to the file).
#   Layout varies by file: a header row of years, then labelled rows. The
#   `selector` column of sources.csv names the sheet and the row label to read,
#   as "<sheet>|<row label>".

BNS_NATIONAL <- "РЕСПУБЛИКА КАЗАХСТАН"
BNS_TOTAL <- "Всего"
# Cell symbols BNS uses instead of a number (see each file's "Условные обозначения"
# sheet): "-" none occurred, "..." / "…" no data, "x" / "х" confidential.
BNS_MISSING <- c("", "-", "...", "…", "x", "х")

fetch_bns <- function(row) {
  ext <- c(api_json = ".json", xlsx_download = ".xlsx")[[row$access_method]]
  download_to_temp(httr2::request(fill_template(row)), ext)
}

# Raw Taldau JSON -> data frame (country, year, value) for the national total:
# the one series whose breakdown terms are the whole country and "total" for
# every other breakdown. Signals schema_changed if that series is missing or
# ambiguous, or if periods or values are not in the documented format.
parse_bns <- function(path, row) {
  id <- row$source_id
  json <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(json) || length(json) == 0) schema_error(id, "empty or non-array response")
  for (s in json) require_fields(s, c("termNames", "periods"), id)
  is_total <- vapply(json, function(s) {
    terms <- unlist(s$termNames)
    length(terms) >= 1 && terms[1] == BNS_NATIONAL && all(terms[-1] == BNS_TOTAL)
  }, logical(1))
  if (sum(is_total) != 1) {
    schema_error(id, sprintf("%d national-total series (expected 1)", sum(is_total)))
  }
  periods <- json[[which(is_total)]]$periods
  for (p in periods) {
    require_fields(p, c("date", "value"), id)
    if (!is.character(p$date) || !is.character(p$value)) schema_error(id, "period date or value is not a string")
  }
  date <- vapply(periods, function(p) p$date, "")
  value <- vapply(periods, function(p) p$value, "")
  # Annual observations are dated 31 December of the year.
  if (!all(grepl("^31\\.12\\.[0-9]{4}$", date))) schema_error(id, "non-annual period dates")
  bns_frame(id, as.integer(substr(date, 7, 10)), value)
}

# Raw stat.gov.kz XLSX -> data frame (country, year, value). Reads the sheet and
# row named by row$selector. Signals schema_changed if the sheet, the year header
# row, the labelled row or the published unit cannot be found exactly.
parse_bns_xlsx <- function(path, row) {
  id <- row$source_id
  sel <- strsplit(row$selector, "|", fixed = TRUE)[[1]]
  if (length(sel) != 2) stop("[", id, "] selector must be '<sheet>|<row label>'")
  sheets <- readxl::excel_sheets(path)
  if (!sel[1] %in% sheets) schema_error(id, sprintf("no sheet '%s'", sel[1]))
  x <- suppressMessages(readxl::read_excel(path, sheet = sel[1], col_names = FALSE,
                                           col_types = "text", .name_repair = "minimal"))
  x <- as.matrix(x)
  clean <- function(s) trimws(gsub("\\s+", " ", s))
  # The published unit must appear in the sheet, so a silent unit change fails.
  if (!any(clean(x) == row$source_unit, na.rm = TRUE)) {
    schema_error(id, sprintf("unit '%s' not found in sheet", row$source_unit))
  }
  # Header row: the first row with at least three cells that are years.
  is_year <- matrix(grepl("^(19|20)[0-9]{2}(\\.0)?$", x), nrow(x))
  header <- which(rowSums(is_year) >= 3)[1]
  if (is.na(header)) schema_error(id, "no row of years")
  if (header == nrow(x)) schema_error(id, "no rows below the year header")
  year_cols <- which(is_year[header, ])
  label_cols <- seq_len(min(year_cols) - 1)
  # Data row: the first row below the header with the selector label in a label column.
  below <- seq(header + 1, nrow(x))
  hit <- below[apply(x[below, label_cols, drop = FALSE], 1, function(r) any(clean(r) == clean(sel[2]), na.rm = TRUE))]
  if (length(hit) == 0) schema_error(id, sprintf("no row labelled '%s'", sel[2]))
  years <- as.integer(substr(x[header, year_cols], 1, 4))
  bns_frame(id, years, x[hit[1], year_cols])
}

# Shared value checks for both BNS formats. Missing-data symbols become NA and
# are dropped; anything else that is not a plain number fails, rather than being
# coerced to NA.
bns_frame <- function(id, year, value) {
  value <- trimws(value)
  value[is.na(value) | value %in% BNS_MISSING] <- NA
  ok <- is.na(value) | grepl("^-?[0-9]+(\\.[0-9]+)?([eE]-?[0-9]+)?$", value)
  if (!all(ok)) schema_error(id, paste("non-numeric values:", paste(unique(value[!ok]), collapse = ", ")))
  out <- data.frame(country = "KAZ", year = year, value = as.numeric(value))
  out <- out[!is.na(out$value), ]
  if (nrow(out) == 0) schema_error(id, "no numeric values")
  require_unique(out, id)
  out[order(out$year), ]
}
