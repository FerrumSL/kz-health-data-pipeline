# Cross-source consistency: for every indicator and country published by more
# than one source, compare the latest year both sources report.
#
# Relative difference = |a - b| / mean(a, b). A pair is flagged when it exceeds
# THRESHOLD. The check only makes disagreement visible; it does not decide
# which source is right.

THRESHOLD <- 0.05

check_consistency <- function(panel, threshold = THRESHOLD) {
  rows <- list()
  for (key in split(panel, list(panel$indicator, panel$country), drop = TRUE)) {
    ids <- sort(unique(key$source_id))
    if (length(ids) < 2) next
    for (pair in utils::combn(ids, 2, simplify = FALSE)) {
      a <- key[key$source_id == pair[1], ]
      b <- key[key$source_id == pair[2], ]
      common <- intersect(a$year, b$year)
      if (length(common) == 0) next
      yr <- max(common)
      va <- a$value[a$year == yr]
      vb <- b$value[b$year == yr]
      rel <- if (va + vb == 0) 0 else abs(va - vb) / ((va + vb) / 2)
      rows[[length(rows) + 1]] <- data.frame(
        indicator = key$indicator[1], country = key$country[1], year = yr,
        source_a = pair[1], value_a = va, source_b = pair[2], value_b = vb,
        rel_diff = rel, flagged = rel > threshold
      )
    }
  }
  if (length(rows) == 0) return(NULL)
  do.call(rbind, rows)
}

if (sys.nframe() == 0) {
  # Self-check: 100 vs 110 differs by 2/21 (9.5%) and is flagged; 100 vs 102 is not;
  # 0 vs 0 is no difference rather than NaN.
  p <- data.frame(
    indicator = "x", country = c("A", "A", "B", "B", "C", "C"), year = 2020,
    value = c(100, 110, 100, 102, 0, 0), source_id = c("s1", "s2", "s1", "s2", "s1", "s2")
  )
  r <- check_consistency(p)
  stopifnot(nrow(r) == 3, isTRUE(all.equal(r$rel_diff[r$country == "A"], 10 / 105)),
            identical(r$flagged, c(TRUE, FALSE, FALSE)))
  cat("check_consistency self-check passed\n")
}
