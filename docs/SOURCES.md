# Source documentation

One section per source. Machine-readable definitions live in [`sources.csv`](../sources.csv);
this file is the human-readable part. The latest fetch status and data year for every source
are in [`reports/source_status.md`](../reports/source_status.md). Everything below was checked
against live responses and the publishers' own pages on 2026-10-19 unless stated otherwise.

## Bureau of National Statistics of Kazakhstan (BNS)

The national source. Unlike the WHO and World Bank series, BNS figures are computed from
national registers and administrative records, not modelled.

- **Publisher and URL:** Bureau of National Statistics, Agency for Strategic Planning and
  Reforms of the Republic of Kazakhstan, <https://stat.gov.kz/>.
- **Access methods (two):**
  1. **Taldau JSON export** (`access_method = api_json`), no key:
     `https://taldau.stat.gov.kz/ru/Api/GetIndexData/<INDEX_ID>?period=7&dics=<DICTIONARY_IDS>`.
     `period=7` is annual. `dics` lists the indicator's breakdown dictionaries (region,
     urban/rural, sex, ...); the export returns an empty array unless **all** of them are given.
     They were read from the portal's segment list,
     `https://taldau.stat.gov.kz/ru/NewIndex/GetSegmentList?indexId=<INDEX_ID>&periodId=7`.
     Indicator metadata ("passport"): `https://taldau.stat.gov.kz/ru/Api/GetIndexAttributes?indexId=<INDEX_ID>`.
     The parser keeps the single series whose terms are `РЕСПУБЛИКА КАЗАХСТАН` and `Всего`
     (total) for every other breakdown, and fails with `schema_changed` if there is not exactly one.
  2. **XLSX download** (`access_method = xlsx_download`) from the stat.gov.kz "open data" and
     "dynamic tables" pages: `https://stat.gov.kz/api/iblock/element/<ELEMENT_ID>/file/ru/`
     (redirects to the file). Layouts differ between files, so each row of `sources.csv` names
     the sheet and row label to read in its `selector` column (`<sheet>|<row label>`). The parser
     finds the header row of years, takes the first row below it with that label, and fails with
     `schema_changed` if the sheet, the label or the published unit text is missing. Cells holding
     BNS's own symbols (`-` none, `...`/`…` no data, `x` confidential) are dropped; any other
     text fails the run. Downloading the same file twice gives the same SHA-256 hash, so unchanged
     files are not re-stored.
- **Indicators:**

  | source_id | Access | BNS id | Indicator | Published unit | Data source (BNS metadata) |
  |---|---|---|---|---|---|
  | `bns_le` | Taldau | 703906 | life expectancy at birth | **months** | Ministry of Health register of attached population |
  | `bns_imr` | Taldau | 703850 | infant mortality rate | per 1,000 live births | civil registration |
  | `bns_beds` | Taldau | 704311 | hospital beds | per 10,000 population | Ministry of Health (since 2014) |
  | `bns_docs` | Taldau | 704316 | doctors of all specialities, end of year | per 10,000 population | Ministry of Health (since 2014) |
  | `bns_u5mr` | XLSX | 451769 | under-five mortality rate | per 1,000 live births | civil registration (Ministry of Justice) and MoH register |
  | `bns_nmr` | XLSX | 451770 | neonatal mortality rate | per 1,000 live births | civil registration |
  | `bns_dtp3` | XLSX | 474267, sheet `3.b.1`, row "Охват АКДС (3 дозы)" | DTP3 coverage, administrative | percent | MoH Committee of Sanitary and Epidemiological Control |
  | `bns_tb` | XLSX | 474268, sheet `3.3.2` | TB incidence (SDG 3.3.2), national | per 100,000 | Ministry of Health |

- **Update frequency (BNS metadata):** life expectancy annually by 30 April; infant mortality
  annually (12 March 2026) plus quarterly; under-five mortality annually (last 2026-04-30, next
  2027-04-30); DTP3 and TB annually (last 2025-12-31, next 2026-12-31); beds and doctors annually.
- **Coverage:** Kazakhstan, national level (the raw files also contain regions, which the
  pipeline does not use). Years available on 2026-10-19: life expectancy 2009-2025, infant
  mortality 2001-2025, under-five and neonatal mortality 2010-2025, DTP3 2010-2025,
  TB 2010-2025, hospital beds and doctors 2014-2023.
- **Licence / terms of use:** official statistical information may be used "for any purpose",
  free of charge, without time or territorial limits, including copying, publishing,
  distributing **with a reference to the source**, modifying and combining with other data
  (<https://stat.gov.kz/ru/description/>, the licence linked from every open-data page).
- **Known issues:**
  - **Life expectancy is published in months** (e.g. 905.28 for 2024), converted to years with
    the exact factor `1/12` in `sources.csv`. Checked: 905.28 / 12 = 75.44 years.
  - **Taldau unit metadata is unreliable.** `measureName` says "Месяц" (month) for life
    expectancy, which is right, but "Тенге казахский" (tenge, a currency) for disease incidence
    rates. Units in `sources.csv` were checked against the values, not taken from this field.
  - **TB incidence is not called "registered" anywhere.** Searched on 2026-10-19 for
    "туберкулез" (RU and KK) and "tuberculosis"/"TB" (EN): no match in the Taldau catalogue
    (1,781 nodes, all three languages), the BNS health dynamic tables, or the health
    publications list (2021-2026). TB appears only in the SDG open-data file 474268
    (indicator 3.3.2, Kazakh title "Туберкулезбен ауыру"). Its metadata copies the global SDG definition ("estimated" by a
    WHO process), but the data source is the Ministry of Health's administrative data and the
    values do **not** match the WHO estimate (2024: BNS 33.4 vs WHO 45 per 100,000). It is
    therefore stored as its own indicator, `tb_incidence_national`, and is **not** compared with
    WHO's `tb_incidence_estimated`. What exactly it counts (notified cases only, or new and
    relapse) is not stated; confirm with BNS (contact in the file's metadata sheet) before
    citing it as "registered incidence".
  - **TB file data quality:** in the same file, the 2019 sex-by-region rows contain impossible
    values (e.g. Mangystau 1411.1, Akmola -7.7 per 100,000), and the 2019 male (105.2) and female
    (73.0) national rates cannot average to the 2019 total (45.6). The pipeline reads only the
    national total row.
  - **Taldau incomplete series:** the Taldau under-five mortality index (703852) stops in 2012,
    and the incidence indices 704341/704342 have no published data at all, so under-five
    mortality comes from the XLSX table instead.
  - **Neonatal mortality metadata is stale:** the file says "last updated 2025-04-30, next
    2026-05-30" but already contains 2025 data.
  - **Infant and neonatal mortality: registered vs modelled.** BNS computes rates from
    registered births and deaths; WHO and the World Bank publish UN IGME modelled estimates.
    They diverge in recent years (see the consistency table). Both are legitimate; they measure
    different things.
  - **Hospital beds:** BNS is 1-3% above WHO/World Bank in every overlapping year (2014-2020),
    with the same shape, including the 2020 jump. Not a year offset.
  - The infant mortality JSON is about 1.8 MB because it includes every region and breakdown and
    cannot be requested without them. A new copy is stored only when it changes.
  - Reachable from outside Kazakhstan (tested from an Italian IP). If BNS ever blocks automated
    access, files will be downloaded by hand into `data/raw/bns_*/<date>/` and their URL and
    download date recorded here.

## WHO Global Health Observatory (GHO)

- **Publisher and URL:** World Health Organization, <https://www.who.int/data/gho>
- **Access method:** OData API, no key. One request per indicator:
  `https://ghoapi.azureedge.net/api/<INDICATOR>?$filter=SpatialDim in ('KAZ','EGY')`.
  Documentation: <https://www.who.int/data/gho/info/gho-odata-api>.
  Fields used: `SpatialDim` (ISO3 country), `TimeDim` (year), `Dim1` (sex), `Dim2`, `Dim3`,
  `NumericValue`. The parser keeps both-sexes rows (`SEX_BTSX`) and, where another dimension
  has several values (e.g. wealth quintiles for under-five mortality), the `_TOTL` value; it
  fails if any dimension is still mixed.
- **Indicators:** `WHOSIS_000001` life expectancy at birth (years); `MDG_0000000001` infant
  mortality; `MDG_0000000007` under-five mortality; `WHOSIS_000003` neonatal mortality (all per
  1,000 live births); `MDG_0000000020` estimated TB incidence (per 100,000); `WHS4_100` DTP3
  coverage among 1-year-olds (%, WHO/UNICEF WUENIC); `GHED_CHEGDP_SHA2011` current health
  expenditure (% of GDP); `WHS6_102` hospital beds and `HWF_0001` medical doctors (per 10,000).
- **Update frequency:** no single schedule; each indicator follows its underlying programme
  (e.g. WUENIC immunisation estimates annually in July, the Global TB Report annually).
  Observed lag per indicator: see the status report.
- **Coverage:** Kazakhstan and Egypt, national level.
- **Licence / terms of use:** WHO's "Terms and conditions of use for WHO data compilations,
  aggregations, evaluations and analyses"
  (<https://www.who.int/about/policies/publishing/data-policy/terms-and-conditions>): a
  royalty-free, non-exclusive right to use, reproduce and distribute the datasets for public
  health purposes; the data may not be sold or used to promote a commercial enterprise;
  attribution to WHO is required ("WHO, title of dataset, year, date of access").
- **Known issues:**
  - WHO's legacy-GHO page announced that the current OData API would be deprecated around the
    end of 2025. As of 2026-10-19 it still works. If it is retired, every `gho_*` source logs
    `failed` or `schema_changed`.
  - Values are model-based estimates, not national registration figures.
  - The parser fails with `schema_changed` if an `@odata.nextLink` (paging) appears, rather than
    silently dropping rows.
  - **Doctors, Kazakhstan:** GHO `HWF_0001` drops from 37.54 (2023) to 30.59 (2024) per 10,000.
    BNS has no 2024 value yet to compare.

## WHO GHO: antimicrobial resistance (GLASS, SDG 3.d.2)

Two GHO indicators, fetched by the same GHO fetcher as above (rows `gho_amr_mrsa` and
`gho_amr_ecoli` in `sources.csv`; no extra code).

**Host-country context, outside the Kazakhstan comparison.** These indicators have no
Kazakhstan data and a single source, so the consistency check does not use them. They are kept
to show the source-list design across countries: two rows with `KAZ;EGY`, no new code, and
Kazakhstan's gap reported as "no data" rather than a failure.

- **Publisher and URL:** World Health Organization, Global Antimicrobial Resistance and Use
  Surveillance System (GLASS), republished in the GHO, <https://www.who.int/data/gho>.
- **Access method:** GHO OData API, no key:
  `https://ghoapi.azureedge.net/api/AMR_INFECT_MRSA?$filter=SpatialDim in ('KAZ','EGY')` and the
  same for `AMR_INFECT_ECOLI`. No sex, age or other breakdown dimension.
- **Indicators:**
  - `AMR_INFECT_MRSA` (`amr_mrsa_bsi`): proportion of bloodstream infections due to
    methicillin-resistant *Staphylococcus aureus* (%).
  - `AMR_INFECT_ECOLI` (`amr_ecoli_3gc_bsi`): proportion of bloodstream infections due to
    *Escherichia coli* resistant to third-generation cephalosporins (%).
- **Update frequency:** annual, following GLASS data calls. Observed lag: see the status report.
- **Coverage:** Egypt only, MRSA 2018-2023 and *E. coli* 2018-2020 and 2022-2023 (no 2021 value).
  GHO's comment on each Egypt value names the reporting body as the "AMR Surveillance National
  Coordinating Center". **Kazakhstan: no rows** for either indicator; the status report shows this
  as "no data KAZ", not as a failure.
- **Licence / terms of use:** as for all GHO data, WHO's terms for data compilations (see the
  GHO section above).
- **Known issues:**
  - **No Kazakhstan data in GHO.** Kazakhstan reports AMR surveillance data to WHO Europe's
    CAESAR network (Central Asian and European Surveillance of Antimicrobial Resistance): the
    ECDC/WHO Regional Office for Europe executive summary on 2023 data says "One country
    (Kazakhstan) reported isolate data for only *Escherichia coli*, *Klebsiella pneumoniae*,
    *Acinetobacter* spp. and *Staphylococcus aureus*" among the 15 countries that reported to
    CAESAR
    (<https://www.ecdc.europa.eu/sites/default/files/documents/antimicrobial-resistance-ECDC-WHO-executive-summary-2023-data.pdf>).
    Whether Kazakhstan is enrolled in or reports to GLASS itself is **not confirmed**: the GHO
    GLASS enrolment indicators (`AMR_GI_001` to `AMR_GI_003`) returned no rows for Kazakhstan or
    Egypt on 2026-10-19. CAESAR data would be the route to Kazakhstan figures; it is not in this
    pipeline.
  - **Small denominators.** Egypt's MRSA value is exactly 100% in 2020, which suggests very few
    tested isolates that year. Year-to-year changes should not be read as trends without the
    isolate counts, which these GHO indicators do not publish.
  - **Not population resistance rates.** These are proportions among tested bloodstream isolates
    from the surveillance sites that report to GLASS, which may not represent the whole country.
- **Last verified:** 2026-10-19 (both codes and all Egypt values checked against live responses).

## World Bank World Development Indicators (WDI)

- **Publisher and URL:** World Bank, <https://data.worldbank.org/>
- **Access method:** Indicators API v2, no key:
  `https://api.worldbank.org/v2/country/KAZ;EGY/indicator/<CODE>?format=json&per_page=1000`.
  The response is a two-element JSON array: paging metadata, then records. Fields used:
  `countryiso3code`, `date` (year), `value`. The parser fails if the response spans more than
  one page or if the record count differs from the metadata `total`.
- **Indicators:** `SP.DYN.LE00.IN` life expectancy; `SP.DYN.IMRT.IN` infant, `SH.DYN.MORT`
  under-five and `SH.DYN.NMRT` neonatal mortality; `SH.TBS.INCD` TB incidence; `SH.IMM.IDPT`
  DPT immunisation; `SH.XPD.CHEX.GD.ZS` current health expenditure (% of GDP);
  `SH.MED.BEDS.ZS` hospital beds and `SH.MED.PHYS.ZS` physicians (both **per 1,000**, converted
  to per 10,000 via the `multiplier` column of `sources.csv`).
- **Update frequency:** the API reports the database's `lastupdated` date in each response
  (2026-10-08 at last check).
- **Coverage:** Kazakhstan and Egypt, 1960 onward where available.
- **Licence / terms of use:** Creative Commons Attribution 4.0 (CC BY 4.0), as listed for
  World Development Indicators in the World Bank Data Catalog
  (<https://datacatalog.worldbank.org/search/dataset/0037712/World-Development-Indicators>).
- **Known issues:**
  - **Most of these WDI series republish WHO or UN estimates**, per the World Bank's own
    indicator metadata: TB incidence (WHO Global TB Report), DPT (WHO/UNICEF), health
    expenditure (WHO Global Health Expenditure Database), hospital beds (WHO, supplemented by
    country data), physicians (WHO Global Health Workforce Statistics, OECD, country data),
    infant, under-five and neonatal mortality (UN IGME). Agreement between GHO and WDI on these
    is expected and is **not independent confirmation**. Life expectancy is the exception: WDI
    uses UN World Population Prospects, national statistics offices and Eurostat.
  - **DTP3 coverage, Kazakhstan.** For 2024: GHO (WUENIC) 54%, WDI 98%, BNS administrative 98.0%.
    WDI matches the national administrative figure. BNS also published the **MICS 2024 household
    survey** (open-data element 517935, table TC.1.2), which found that **56.3%** of children
    aged 24-35 months had received DTP3 (АбКДС3), close to the WHO/UNICEF value. This is
    consistent with WUENIC giving weight to the survey over administrative reports, but WHO's
    own country notes for Kazakhstan have not been checked to confirm it. Definitions also
    differ (GHO: 1-year-olds; WDI: children 12-23 months; MICS: 24-35 months).
  - The most recent year is often present with `value = null`; such rows are dropped.
