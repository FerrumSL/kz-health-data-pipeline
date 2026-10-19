# Each parser gets a saved real response (fixtures/, retrieved 2026-10-19).
# Unchanged, it must return data; with one field renamed, it must signal
# schema_changed instead of returning a silently wrong table.
# Run from the repository root: Rscript -e 'testthat::test_dir("tests/testthat")'

root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in c("utils.R", "fetch_gho.R", "fetch_worldbank.R", "fetch_bns.R", "report.R")) source(file.path(root, "R", f))

sources <- read.csv(file.path(root, "sources.csv"), stringsAsFactors = FALSE, encoding = "UTF-8")
row <- function(id) sources[sources$source_id == id, ]
fixture <- function(name) testthat::test_path("fixtures", name)

# Rewrite a fixture with every occurrence of the JSON key `from` renamed to `to`.
renamed <- function(name, from, to) {
  txt <- readLines(fixture(name), warn = FALSE)
  path <- tempfile(fileext = ".json")
  writeLines(gsub(sprintf('"%s":', from), sprintf('"%s":', to), txt, fixed = TRUE), path)
  path
}

test_that("GHO parser reads the real response", {
  df <- parse_gho(fixture("gho_le.json"), row("gho_le"))
  expect_setequal(unique(df$country), c("KAZ", "EGY"))
  expect_false(anyDuplicated(df[c("country", "year")]) > 0)
  expect_true(all(df$value > 40 & df$value < 100))
})

test_that("GHO parser flags renamed fields", {
  for (field in c("SpatialDim", "TimeDim", "NumericValue", "Dim1", "value")) {
    expect_error(parse_gho(renamed("gho_le.json", field, paste0(field, "_x")), row("gho_le")),
                 class = "schema_changed", info = field)
  }
})

test_that("GHO parser flags a dropped sex filter value", {
  # If WHO renamed SEX_BTSX, the both-sexes filter would match nothing.
  path <- tempfile(fileext = ".json")
  writeLines(gsub("SEX_BTSX", "SEX_TOTAL", readLines(fixture("gho_le.json"), warn = FALSE), fixed = TRUE), path)
  expect_error(parse_gho(path, row("gho_le")), class = "schema_changed")
})

test_that("World Bank parser reads the real response", {
  df <- parse_worldbank(fixture("wb_le.json"), row("wb_le"))
  expect_setequal(unique(df$country), c("KAZ", "EGY"))
  expect_false(anyDuplicated(df[c("country", "year")]) > 0)
  expect_true(all(df$value > 40 & df$value < 100))
})

test_that("World Bank parser flags renamed fields", {
  for (field in c("countryiso3code", "date", "value", "pages", "total")) {
    expect_error(parse_worldbank(renamed("wb_le.json", field, paste0(field, "_x")), row("wb_le")),
                 class = "schema_changed", info = field)
  }
})

test_that("World Bank parser flags an API error message", {
  path <- tempfile(fileext = ".json")
  writeLines('[{"message":[{"id":"120","key":"Invalid value","value":"The provided parameter value is not valid"}]}]', path)
  expect_error(parse_worldbank(path, row("wb_le")), class = "schema_changed")
})

test_that("BNS parser reads the real response (national total only)", {
  df <- parse_bns(fixture("bns_le.json"), row("bns_le"))
  expect_equal(unique(df$country), "KAZ")
  expect_false(anyDuplicated(df$year) > 0)
  # Taldau publishes life expectancy in months; the parser must not convert units.
  expect_true(all(df$value > 600 & df$value < 1000))
})

test_that("BNS parser flags renamed fields", {
  for (field in c("termNames", "periods", "date", "value")) {
    expect_error(parse_bns(renamed("bns_le.json", field, paste0(field, "_x")), row("bns_le")),
                 class = "schema_changed", info = field)
  }
})

test_that("BNS parser flags a renamed national-total term", {
  # If BNS renamed "Всего" (total), no series would match the national total.
  path <- tempfile(fileext = ".json")
  writeLines(gsub('"Всего"', '"Итого"', readLines(fixture("bns_le.json"), warn = FALSE, encoding = "UTF-8"),
                  fixed = TRUE), path, useBytes = TRUE)
  expect_error(parse_bns(path, row("bns_le")), class = "schema_changed")
})

test_that("BNS parser flags a null value", {
  path <- tempfile(fileext = ".json")
  writeLines('[{"terms":[741880],"termNames":["РЕСПУБЛИКА КАЗАХСТАН"],"periods":[{"name":"2020 год","date":"31.12.2020","value":null}]}]',
             path, useBytes = TRUE)
  expect_error(parse_bns(path, row("bns_le")), class = "schema_changed")
})

test_that("BNS parser flags non-numeric values", {
  path <- tempfile(fileext = ".json")
  writeLines('[{"terms":[741880],"termNames":["РЕСПУБЛИКА КАЗАХСТАН"],"periods":[{"name":"2020 год","date":"31.12.2020","value":"12,5"}]}]',
             path, useBytes = TRUE)
  expect_error(parse_bns(path, row("bns_le")), class = "schema_changed")
})

# XLSX files cannot be edited as text, so layout changes are simulated by
# pointing the parser at a sheet, row label or unit that the file no longer has.
xlsx_row <- function(...) modifyList(as.list(row("bns_tb")), list(...))

test_that("BNS XLSX parser reads the real file (national total row)", {
  df <- parse_bns_xlsx(fixture("bns_tb.xlsx"), row("bns_tb"))
  expect_equal(unique(df$country), "KAZ")
  # Values checked by hand against the file on 2026-10-19.
  expect_equal(df$value[df$year %in% c(2010, 2024)], c(95.3, 33.4))
})

test_that("BNS XLSX parser flags a renamed sheet, row or unit", {
  expect_error(parse_bns_xlsx(fixture("bns_tb.xlsx"), xlsx_row(selector = "3.3.3|3.3.2 Заболеваемость туберкулезом на 100 000 человек")),
               class = "schema_changed")
  expect_error(parse_bns_xlsx(fixture("bns_tb.xlsx"), xlsx_row(selector = "3.3.2|Заболеваемость туберкулезом")),
               class = "schema_changed")
  expect_error(parse_bns_xlsx(fixture("bns_tb.xlsx"), xlsx_row(source_unit = "на 1000 человек")),
               class = "schema_changed")
})

test_that("BNS missing-data symbols are dropped, other text fails", {
  df <- bns_frame("t", 2020:2023, c("1.5", "-", "…", "x"))
  expect_equal(df$year, 2020)
  expect_error(bns_frame("t", 2020:2021, c("1.5", "12,5")), class = "schema_changed")
})

test_that("a requested country with no rows is reported as 'no data', not a failure", {
  # Saved real response (2026-10-19): GHO has AMR data for Egypt but none for Kazakhstan.
  r <- row("gho_amr_mrsa")
  df <- parse_gho(fixture("gho_amr_mrsa.json"), r)
  expect_equal(unique(df$country), "EGY")
  panel <- data.frame(df, indicator = r$indicator, source_id = r$source_id)
  log <- data.frame(run_at = "2026-10-19 09:00:00", source_id = r$source_id, status = "updated")
  status <- source_status(r, log, panel, "2026-10-19 09:00:00")
  expect_equal(status$status, "updated")
  expect_match(status$latest_year, "no data KAZ", fixed = TRUE)
  expect_match(status$latest_year, "2023 EGY", fixed = TRUE)
})

test_that("lag_years follows the country the source is furthest behind on", {
  r <- row("gho_beds")
  panel <- data.frame(country = c("KAZ", "EGY"), year = c(2020, 2021), source_id = r$source_id)
  log <- data.frame(run_at = "2026-10-19 09:00:00", source_id = r$source_id, status = "unchanged")
  expect_equal(source_status(r, log, panel, "2026-10-19 09:00:00")$lag_years, 6)
})
