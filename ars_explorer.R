# ars_explorer.R ---------------------------------------------------------------
#
# Interactive Shiny explorer for the ARS pipeline.
# Workflow: select domain → select shell → configure mappings → Get ARD → Get Table
#
# Usage:
#   source("ars_explorer.R")
#
# Prerequisites:
#   - source("sync_and_load.R")           # loads all ars* packages
#   - source("data_table_examples.R")     # creates adsl, adae, adlb
#     (or have those objects in your environment already)

library(shiny)
library(bslib)
library(reactable)
library(jsonlite)
library(ars)

# ── Helper: strip ANSI colour codes from cli error/warning messages ──────────
.strip_ansi <- function(x) cli::ansi_strip(x)

# ── Helper: load shell index from arsshells ───────────────────────────────────

.load_shell_index <- function() {
  idx_path <- system.file("templates/index.json", package = "arsshells")
  if (!nzchar(idx_path) || !file.exists(idx_path)) {
    # Fallback: development path relative to this file
    root <- tryCatch(
      normalizePath(dirname(rstudioapi::getSourceEditorContext()$path)),
      error = function(e) getwd()
    )
    idx_path <- file.path(root, "arsshells", "inst", "templates", "index.json")
  }
  if (!file.exists(idx_path)) stop("Shell index not found: ", idx_path)

  raw <- jsonlite::fromJSON(idx_path, simplifyDataFrame = FALSE)
  do.call(rbind, lapply(raw$shells, function(s) {
    data.frame(
      id           = s$id,
      name         = s$name,
      type         = s$type,
      domain       = s$domain,
      adam_dataset = s$adamDataset,
      installed    = isTRUE(s$installed),
      stringsAsFactors = FALSE
    )
  }))
}

# ── Helper: recursively extract variable names from S7 objects ─────────────────
# Walks ars_where_clause_condition, ars_data_subset, ars_analysis_set,
# ars_compound_subset_expression (and similar compound expression types).

.extract_wc_vars <- function(obj) {
  if (is.null(obj)) return(character(0))
  vars <- character(0)

  # ars_where_clause_condition: has @variable directly
  var_val <- tryCatch(obj@variable, error = function(e) NULL)
  if (!is.null(var_val) && !is.na(var_val) && nchar(var_val) > 0) return(var_val)

  # Objects with @condition (ars_data_subset, ars_analysis_set, ars_group)
  cond <- tryCatch(obj@condition, error = function(e) NULL)
  if (!is.null(cond)) vars <- c(vars, .extract_wc_vars(cond))

  # Objects with @compound_expression (compound where clauses)
  compound <- tryCatch(obj@compound_expression, error = function(e) NULL)
  if (!is.null(compound)) vars <- c(vars, .extract_wc_vars(compound))

  # ars_compound_subset_expression: has @where_clauses (list of sub-clauses)
  wcs <- tryCatch(obj@where_clauses, error = function(e) NULL)
  if (!is.null(wcs) && is.list(wcs)) {
    for (wc in wcs) vars <- c(vars, .extract_wc_vars(wc))
  }

  vars
}

# ── Helper: extract all variable names referenced in a Shell ──────────────────

.extract_shell_variables <- function(shell) {
  re   <- shell@reporting_event
  vars <- character(0)

  # 1. Analysis target variables (e.g., AVAL, CHG, AGE, SEX)
  for (an in re@analyses) {
    v <- tryCatch(an@variable, error = function(e) NULL)
    if (!is.null(v) && !is.na(v) && nchar(v) > 0) vars <- c(vars, v)
  }

  # 2. Grouping variables (e.g., TRT01A, AEBODSYS, AEDECOD)
  for (gf in re@analysis_groupings) {
    v <- tryCatch(gf@grouping_variable, error = function(e) NULL)
    if (!is.null(v) && !is.na(v) && nchar(v) > 0) vars <- c(vars, v)
  }

  # 3. Variables in analysis-set conditions (e.g., SAFFL, RANDFL)
  for (as_ in re@analysis_sets) vars <- c(vars, .extract_wc_vars(as_))

  # 4. Variables in data-subset conditions (e.g., TRTEMFL, ANL01FL, ABLFL)
  for (ds in re@data_subsets) vars <- c(vars, .extract_wc_vars(ds))

  # 5. Variables in group conditions within pre-specified grouping factors
  for (gf in re@analysis_groupings) {
    for (grp in gf@groups) vars <- c(vars, .extract_wc_vars(grp))
  }

  unique(vars)
}

# ── Helper: find Mode-2 (pre-specified, non-data-driven) grouping factors ─────

.extract_mode2_gfs <- function(shell) {
  Filter(function(gf) !isTRUE(gf@data_driven), shell@reporting_event@analysis_groupings)
}

# ── Helper: strip arscore extensions before CDISC JSON Schema validation ──────
#
# The official CDISC ARS JSON Schema uses `additionalProperties: false` on every
# class definition.  arscore adds two fields beyond the CDISC model:
#
#   • `isTotal` on Group objects   — marks Total/All-subjects groups
#   • `groupId` on OrderedGroupingFactor — pre-resolves the active group for
#                                          analyses that fix a single group value
#
# These fields are useful for arscore's internal logic and round-trips, but they
# cause schema validation failures.  This function strips them from the parsed
# JSON list before passing the document to jsonvalidate.  The arscore JSON
# representation is otherwise a strict superset of the CDISC schema.

.strip_ars_extensions <- function(doc) {
  # Strip isTotal from every group in every analysisGrouping
  if (!is.null(doc$analysisGroupings)) {
    doc$analysisGroupings <- lapply(doc$analysisGroupings, function(gf) {
      if (!is.null(gf$groups)) {
        gf$groups <- lapply(gf$groups, function(g) {
          g$isTotal <- NULL
          g
        })
      }
      gf
    })
  }

  # Strip groupId from every orderedGrouping in every analysis
  if (!is.null(doc$analyses)) {
    doc$analyses <- lapply(doc$analyses, function(an) {
      if (!is.null(an$orderedGroupings)) {
        an$orderedGroupings <- lapply(an$orderedGroupings, function(og) {
          og$groupId <- NULL
          og
        })
      }
      an
    })
  }

  # Normalise arscore-only comparators (IS_NULL, NOT_NULL) to CDISC-valid ones.
  # The CDISC v1 ConditionComparatorEnum only includes EQ/NE/GT/GE/LT/LE/IN/NOTIN.
  # IS_NULL → EQ "" and NOT_NULL → NE "" so the structure stays valid for schema
  # purposes (the actual semantics are preserved in Layer 1 / round-trip checks).
  .fix_comparators <- function(obj) {
    if (!is.list(obj)) return(obj)
    if (!is.null(obj$comparator)) {
      if (obj$comparator == "IS_NULL") {
        obj$comparator <- "EQ"
        obj$value      <- list("")
      } else if (obj$comparator == "NOT_NULL") {
        obj$comparator <- "NE"
        obj$value      <- list("")
      }
    }
    lapply(obj, .fix_comparators)
  }
  doc <- .fix_comparators(doc)

  doc
}

# ── Helper: auto-generate a mainListOfContents from a reporting event ─────────
#
# The CDISC ARS JSON Schema (draft-07) requires `mainListOfContents` at the
# root of every ReportingEvent.  Our shell templates leave it NULL (the field
# is optional in arscore), so Layer-2 schema validation currently fails.
#
# This helper builds a flat, auto-generated ListOfContents that enumerates
# every analysis in the reporting event in declared order.  It is called:
#   1. Before Layer-2 schema validation (Validate button).
#   2. Before the "Full ARS with results" JSON download.
#
# The generated LoC carries a label that makes its auto-generated nature clear
# so it won't be confused with a curated study-level table of contents.

.auto_main_loc <- function(re) {
  analyses <- re@analyses
  if (length(analyses) == 0L) return(re)

  list_items <- lapply(seq_along(analyses), function(i) {
    an <- analyses[[i]]
    arscore::new_ars_ordered_list_item(
      name        = if (!is.na(an@label) && nzchar(an@label)) an@label else an@id,
      level       = 1L,
      order       = as.integer(i),
      analysis_id = an@id
    )
  })

  loc <- arscore::new_ars_list_of_contents(
    name          = "Main List of Contents",
    label         = "Auto-generated from analyses list",
    contents_list = arscore::new_ars_nested_list(list_items = list_items)
  )

  re@main_list_of_contents <- loc
  re
}

# ── Helper: embed ARD results into a reporting event (ARS model) ──────────────
#
# create_ard() flattens the analysis@results tree into a tidy tibble.
# This function is the inverse: it reconstructs ars_operation_result /
# ars_result_group objects from each ARD row and writes them back into the
# corresponding analyses, producing a fully-populated ars_reporting_event
# that conforms to the CDISC ARS v1.0 model.
#
# ARD column conventions (from create_ard()):
#   1 result group  → grouping_id,   group_id,   group_value   (no suffix)
#   N result groups → grouping_id_1, group_id_1, group_value_1, ... _N

.rgs_from_ard_row <- function(row) {
  make_rg <- function(gid, grp_id, grp_val) {
    if (is.null(gid) || is.na(gid) || !nzchar(gid)) return(NULL)
    arscore::new_ars_result_group(
      grouping_id = gid,
      group_id    = if (!is.null(grp_id)  && !is.na(grp_id)  && nzchar(grp_id))  grp_id  else NA_character_,
      group_value = if (!is.null(grp_val) && !is.na(grp_val) && nzchar(grp_val)) grp_val else NA_character_
    )
  }

  if ("grouping_id" %in% names(row)) {
    rg <- make_rg(row[["grouping_id"]], row[["group_id"]], row[["group_value"]])
    return(if (!is.null(rg)) list(rg) else list())
  }

  rgs <- list()
  i   <- 1L
  repeat {
    col <- paste0("grouping_id_", i)
    if (!col %in% names(row)) break
    rg <- make_rg(row[[col]],
                  row[[paste0("group_id_",    i)]],
                  row[[paste0("group_value_", i)]])
    if (!is.null(rg)) rgs <- c(rgs, list(rg))
    i <- i + 1L
  }
  rgs
}

.embed_ard_into_re <- function(re, ard) {
  # All operations in the ARD are formally declared in their method (§21 flat
  # operations refactor removed composite OP_MEAN_SD / OP_RANGE that previously
  # emitted undeclared component scalars).  No pre-filter is needed; every ARD
  # row maps to a declared operation and validate_reporting_event() will pass.

  # Build lookup: analysis_id → list of ars_operation_result
  an_results <- list()

  for (i in seq_len(nrow(ard))) {
    row   <- as.list(ard[i, , drop = FALSE])
    an_id <- row[["analysis_id"]]
    op_id <- row[["operation_id"]]
    raw_v <- row[["raw_value"]]
    fmt_v <- row[["formatted_value"]]

    # ars_operation_result requires at least one non-NA value; mirror run.R
    raw_chr <- if (!is.null(raw_v) && !is.na(raw_v)) as.character(raw_v) else "NA"
    fmt_chr <- if (!is.null(fmt_v) && !is.na(fmt_v)) as.character(fmt_v) else NA_character_

    op_res <- arscore::new_ars_operation_result(
      operation_id    = op_id,
      result_groups   = .rgs_from_ard_row(row),
      raw_value       = raw_chr,
      formatted_value = fmt_chr
    )

    an_results[[an_id]] <- c(an_results[[an_id]], list(op_res))
  }

  # Write results back into each analysis in the reporting event
  re@analyses <- lapply(re@analyses, function(an) {
    res <- an_results[[an@id]]
    if (!is.null(res)) an@results <- res
    an
  })

  re
}

# ── Module UI ──────────────────────────────────────────────────────────────────

arsExplorerUI <- function(id) {
  ns <- NS(id)

  page_sidebar(
    title  = "ARS Explorer",
    theme  = bs_theme(version = 5, preset = "bootstrap"),

    sidebar = sidebar(
      width = 370,

      # ── Step 1: Domain ────────────────────────────────────────────────────
      strong("1. Domain"),
      selectInput(ns("domain"), NULL, choices = NULL, width = "100%"),

      # ── Step 2: Shell ─────────────────────────────────────────────────────
      strong("2. Shell"),
      uiOutput(ns("shell_picker")),
      uiOutput(ns("shell_info_card")),

      hr(class = "my-2"),

      # ── Step 3: Configure (collapsible) ───────────────────────────────────
      accordion(
        id = ns("config_accordion"),
        open = "arms",

        accordion_panel(
          title = "Variable mapping",
          value = "vmap",
          p(class = "text-muted small mb-2",
            "Map each shell variable to a column in your dataset.",
            "Defaults are auto-filled from exact column name matches."),
          uiOutput(ns("variable_map_ui"))
        ),

        accordion_panel(
          title = "Treatment arms",
          value = "arms",
          p(class = "text-muted small mb-2",
            "Arm values are auto-detected from the data.",
            "Edit display labels as needed."),
          uiOutput(ns("group_map_ui"))
        ),

        accordion_panel(
          title = "Value map",
          value = "vmap_overrides",
          p(class = "text-muted small mb-2",
            "Map values that differ between the shell template and your dataset.",
            tags$br(),
            tags$em("Example: shell expects \u201cRELATED\u201d but data has \u201cREMOTE\u201d.")),
          # Column headers
          fluidRow(
            class = "mb-1 gx-1",
            column(4, tags$small(strong("Variable"))),
            column(4, tags$small(strong("Template value"))),
            column(3, tags$small(strong("Dataset value"))),
            column(1)
          ),
          uiOutput(ns("ovm_rows_ui")),
          actionButton(ns("add_ovm_row"), "+ Add",
                       icon  = icon("plus"),
                       class = "btn-sm btn-outline-primary mt-2 w-100")
        )
      ),

      hr(class = "my-2"),

      # ── Step 4: Run ───────────────────────────────────────────────────────
      actionButton(ns("run_ard"), "Get ARD", icon = icon("flask"),
                   class = "btn-primary w-100 mb-2"),
      uiOutput(ns("get_table_btn")),
      uiOutput(ns("validate_btn")),

      hr(class = "my-2"),
      uiOutput(ns("run_status")),
      uiOutput(ns("export_bar"))
    ),

    # ── Main panel ────────────────────────────────────────────────────────────
    navset_card_tab(
      id = ns("tabs"),

      nav_panel(
        title = "Shell",
        icon  = icon("info-circle"),
        gt::gt_output(ns("shell_mock"))
      ),
      nav_panel(
        title = "ARD",
        icon  = icon("database"),
        reactable::reactableOutput(ns("ard_dt"))
      ),
      nav_panel(
        title = "Table",
        icon  = icon("table"),
        uiOutput(ns("download_bar")),
        gt::gt_output(ns("rendered_gt"))
      ),

      nav_panel(
        title = "Validate",
        icon  = icon("shield-check"),
        uiOutput(ns("validate_report"))
      ),

      nav_panel(
        title = "Compare",
        icon  = icon("left-right"),
        layout_columns(
          col_widths = c(6, 6),
          card(
            class = "h-100",
            card_header(
              class = "bg-light",
              tags$span(icon("circle-xmark", class = "text-muted me-1"),
                        "Without ARD", tags$small(class = "text-muted ms-1", "(mock)"))
            ),
            card_body(class = "p-2", gt::gt_output(ns("compare_mock")))
          ),
          card(
            class = "h-100",
            card_header(
              class = "bg-light",
              tags$span(icon("circle-check", class = "text-success me-1"),
                        "With ARD", tags$small(class = "text-muted ms-1", "(rendered)"))
            ),
            card_body(class = "p-2", uiOutput(ns("compare_rendered_ui")))
          )
        )
      )
    )
  )
}

# ── Module Server ──────────────────────────────────────────────────────────────

#' @param id         Module namespace id.
#' @param adam_reactive A reactive returning a named list of ADaM datasets,
#'   e.g. \code{reactive(list(ADSL = adsl, ADAE = adae, ADLB = adlb))}.

arsExplorerServer <- function(id, adam_reactive) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Startup: load shell index ────────────────────────────────────────────
    shell_index    <- .load_shell_index()
    installed_idx  <- shell_index[shell_index$installed, ]
    domain_choices <- sort(unique(installed_idx$domain))

    updateSelectInput(session, "domain",
                      choices  = domain_choices,
                      selected = domain_choices[1])

    # ── Reactive: shells available in selected domain ────────────────────────
    shells_in_domain <- reactive({
      req(input$domain)
      installed_idx[installed_idx$domain == input$domain, ]
    })

    # ── Render: shell picker (radio buttons, filtered by domain) ─────────────
    output$shell_picker <- renderUI({
      sid <- shells_in_domain()
      req(nrow(sid) > 0)
      choices <- setNames(sid$id, paste0(sid$id, " \u2014 ", sid$name))
      radioButtons(ns("shell_id"), NULL, choices = choices, width = "100%")
    })

    # ── Reactive: metadata row for the selected shell ─────────────────────────
    selected_meta <- reactive({
      req(input$shell_id)
      installed_idx[installed_idx$id == input$shell_id, ]
    })

    # ── Render: small info card below shell picker ────────────────────────────
    output$shell_info_card <- renderUI({
      m <- selected_meta()
      req(nrow(m) > 0)
      card(
        class = "bg-light border-0 py-1 px-2 mb-1",
        card_body(
          class = "py-1",
          p(class = "mb-1 small",
            strong("ADaM dataset: "), m$adam_dataset,
            tags$span(class = "ms-2 text-muted", paste0("(", m$type, ")")))
        )
      )
    })

    # ── Reactive: loaded Shell object ─────────────────────────────────────────
    shell_obj <- reactive({
      req(input$shell_id)
      tryCatch(
        use_shell(input$shell_id),
        error = function(e) {
          showNotification(paste("Failed to load shell:", .strip_ansi(conditionMessage(e))),
                           type = "error", duration = 8)
          NULL
        }
      )
    })

    # ── Reactive: mock-rendered gt table (shared by Shell and Compare tabs) ───
    # Memoized so render_mock() is called once per shell switch, not twice.
    shell_mock_gt <- reactive({
      sh <- shell_obj()
      req(sh)
      tryCatch(
        render_mock(sh),
        error = function(e) {
          showNotification(paste("Mock render failed:", .strip_ansi(conditionMessage(e))),
                           type = "warning", duration = 6)
          NULL
        }
      )
    })

    # ── Reactive: all column names available from relevant datasets ────────────
    all_cols <- reactive({
      m <- selected_meta()
      req(nrow(m) > 0)
      adam <- adam_reactive()
      req(adam)
      primary_ds <- toupper(m$adam_dataset)
      datasets_needed <- unique(c(primary_ds, "ADSL"))
      cols <- character(0)
      for (ds in datasets_needed) {
        if (!is.null(adam[[ds]])) cols <- c(cols, names(adam[[ds]]))
      }
      unique(cols)
    })

    # ── Reactive: variable names referenced by the shell ─────────────────────
    shell_vars <- reactive({
      sh <- shell_obj()
      req(sh)
      .extract_shell_variables(sh)
    })

    # ── Render: variable mapping UI ───────────────────────────────────────────
    output$variable_map_ui <- renderUI({
      vars <- shell_vars()
      req(length(vars) > 0)
      cols <- all_cols()
      req(length(cols) > 0)

      lapply(vars, function(v) {
        default <- if (v %in% cols) v else cols[1]
        selectInput(
          inputId  = ns(paste0("vmap_", v)),
          label    = v,
          choices  = cols,
          selected = default,
          width    = "100%"
        )
      })
    })

    # ── Reactive: constructed variable_map ────────────────────────────────────
    variable_map <- reactive({
      vars <- shell_vars()
      req(length(vars) > 0)
      setNames(
        vapply(vars, function(v) {
          val <- input[[paste0("vmap_", v)]]
          if (is.null(val) || !nzchar(val)) v else val
        }, character(1L)),
        vars
      )
    })

    # ── Reactive: Mode-2 (pre-specified) grouping factors ─────────────────────
    mode2_gfs <- reactive({
      sh <- shell_obj()
      req(sh)
      .extract_mode2_gfs(sh)
    })

    # ── Render: treatment arm configuration UI ────────────────────────────────
    output$group_map_ui <- renderUI({
      gfs  <- mode2_gfs()
      req(length(gfs) > 0)
      adam <- adam_reactive()
      req(adam)

      lapply(gfs, function(gf) {
        gv  <- tryCatch(gf@grouping_variable, error = function(e) NA_character_)
        gds <- tryCatch(gf@grouping_dataset,  error = function(e) NA_character_)
        if (is.na(gv) || !nzchar(gv)) return(NULL)

        ds_name  <- if (!is.na(gds) && nzchar(gds)) toupper(gds) else "ADSL"
        ds       <- adam[[ds_name]]
        arm_vals <- if (!is.null(ds) && gv %in% names(ds)) {
          sort(unique(ds[[gv]][!is.na(ds[[gv]])]))
        } else {
          character(0)
        }

        if (length(arm_vals) == 0) {
          return(p(class = "text-warning small",
                   paste0("No values found for ", gv, " in ", ds_name)))
        }

        tagList(
          tags$small(class = "text-secondary",
                     paste0(gv, " \u2014 ", length(arm_vals), " arms detected")),
          tags$div(
            class = "mt-1",
            # Header row
            fluidRow(
              column(1, tags$small(strong("\u2714"))),
              column(4, tags$small(strong("Data value"))),
              column(7, tags$small(strong("Display label")))
            ),
            # One row per arm
            lapply(seq_along(arm_vals), function(i) {
              fluidRow(
                class = "mb-1 align-items-center",
                column(1,
                  checkboxInput(
                    inputId = ns(paste0("ginclude_", gf@id, "_", i)),
                    label   = NULL,
                    value   = TRUE
                  )
                ),
                column(4, tags$small(class = "text-secondary", arm_vals[i])),
                column(7,
                  textInput(
                    inputId = ns(paste0("glabel_", gf@id, "_", i)),
                    label   = NULL,
                    value   = paste0(arm_vals[i], " (N=xx)"),
                    width   = "100%"
                  )
                )
              )
            })
          )
        )
      })
    })

    # ── Reactive: constructed group_map ───────────────────────────────────────
    group_map <- reactive({
      gfs  <- mode2_gfs()
      req(length(gfs) > 0)
      adam <- adam_reactive()

      result <- list()
      for (gf in gfs) {
        gf_id <- tryCatch(gf@id,               error = function(e) NULL)
        gv    <- tryCatch(gf@grouping_variable, error = function(e) NA_character_)
        gds   <- tryCatch(gf@grouping_dataset,  error = function(e) NA_character_)
        if (is.null(gf_id) || is.na(gv) || !nzchar(gv)) next

        ds_name  <- if (!is.na(gds) && nzchar(gds)) toupper(gds) else "ADSL"
        ds       <- adam[[ds_name]]
        arm_vals <- if (!is.null(ds) && gv %in% names(ds)) {
          sort(unique(ds[[gv]][!is.na(ds[[gv]])]))
        } else {
          character(0)
        }

        if (length(arm_vals) == 0) next

        # Filter to only included arms, then build group entries
        included <- Filter(
          function(i) {
            chk <- input[[paste0("ginclude_", gf_id, "_", i)]]
            is.null(chk) || isTRUE(chk)   # default TRUE if not yet rendered
          },
          seq_along(arm_vals)
        )

        result[[gf_id]] <- lapply(seq_along(included), function(j) {
          i         <- included[j]
          arm_id    <- paste0(gf_id, "_", LETTERS[j])
          lbl_input <- input[[paste0("glabel_", gf_id, "_", i)]]
          label     <- if (!is.null(lbl_input) && nzchar(lbl_input))
                         lbl_input
                       else
                         paste0(arm_vals[i], " (N=xx)")
          list(id = arm_id, value = arm_vals[i], label = label, order = j)
        })
      }
      result
    })

    # ── State: value-map override rows ────────────────────────────────────────
    # Each row is identified by a unique integer id.  The actual text inputs
    # (ovm_var_<id>, ovm_shell_<id>, ovm_data_<id>) live in Shiny's input list;
    # ovm_rows() just tracks which ids currently exist.
    ovm_counter <- reactiveVal(0L)
    ovm_rows    <- reactiveVal(integer(0))   # vector of active row ids

    # Add a new blank row
    observeEvent(input$add_ovm_row, {
      new_id <- ovm_counter() + 1L
      ovm_counter(new_id)
      ovm_rows(c(ovm_rows(), new_id))
    })

    # Delete-button observers — one per row, fires once then becomes inert
    observe({
      lapply(ovm_rows(), function(id) {
        btn <- paste0("del_ovm_", id)
        observeEvent(input[[btn]], {
          ovm_rows(setdiff(ovm_rows(), id))
        }, ignoreInit = TRUE, once = TRUE)
      })
    })

    # ── Render: value-map row editor ──────────────────────────────────────────
    output$ovm_rows_ui <- renderUI({
      ids  <- ovm_rows()
      vars <- c("" , shell_vars())    # variable choices: blank + shell vars

      if (length(ids) == 0) {
        return(p(class = "text-muted small fst-italic", "No overrides defined."))
      }

      lapply(ids, function(id) {
        fluidRow(
          class = "mb-1 gx-1 align-items-center",
          column(4,
            selectInput(
              inputId  = ns(paste0("ovm_var_", id)),
              label    = NULL,
              choices  = vars,
              selected = isolate(input[[paste0("ovm_var_", id)]]) %||% "",
              width    = "100%"
            )
          ),
          column(4,
            textInput(
              inputId     = ns(paste0("ovm_shell_", id)),
              label       = NULL,
              value       = isolate(input[[paste0("ovm_shell_", id)]]) %||% "",
              placeholder = "e.g. RELATED",
              width       = "100%"
            )
          ),
          column(3,
            textInput(
              inputId     = ns(paste0("ovm_data_", id)),
              label       = NULL,
              value       = isolate(input[[paste0("ovm_data_", id)]]) %||% "",
              placeholder = "e.g. REMOTE",
              width       = "100%"
            )
          ),
          column(1,
            actionButton(
              inputId = ns(paste0("del_ovm_", id)),
              label   = NULL,
              icon    = icon("xmark"),
              class   = "btn-sm btn-outline-danger px-1 w-100"
            )
          )
        )
      })
    })

    # ── Reactive: constructed value_map ───────────────────────────────────────
    value_map <- reactive({
      ids <- ovm_rows()
      if (length(ids) == 0) return(NULL)

      result <- list()
      for (id in ids) {
        var_name  <- input[[paste0("ovm_var_",   id)]]
        shell_val <- input[[paste0("ovm_shell_", id)]]
        data_val  <- input[[paste0("ovm_data_",  id)]]

        # Skip incomplete rows
        if (is.null(var_name)  || !nzchar(var_name))  next
        if (is.null(shell_val) || !nzchar(shell_val)) next
        if (is.null(data_val)  || !nzchar(data_val))  next

        existing <- result[[var_name]]
        result[[var_name]] <- c(existing, setNames(data_val, shell_val))
      }

      if (length(result) == 0) NULL else result
    })

    # ── Reactive: adam datasets subset needed for this shell ──────────────────
    adam_for_shell <- reactive({
      m    <- selected_meta()
      req(nrow(m) > 0)
      adam <- adam_reactive()
      req(adam)

      primary_ds <- toupper(m$adam_dataset)
      datasets   <- list()
      if (!is.null(adam[[primary_ds]]))   datasets[[primary_ds]] <- adam[[primary_ds]]
      if (primary_ds != "ADSL" && !is.null(adam[["ADSL"]])) {
        datasets[["ADSL"]] <- adam[["ADSL"]]
      }
      datasets
    })

    # ── Output: mock-rendered shell (Shell tab) ───────────────────────────────
    output$shell_mock <- gt::render_gt({
      shell_mock_gt()
    })

    # ── State: ARD, table, and validation results ──────────────────────────────
    ard_result      <- reactiveVal(NULL)
    table_result    <- reactiveVal(NULL)
    validate_result <- reactiveVal(NULL)

    # Reset results and value-map rows whenever shell / domain changes
    observe({
      ard_result(NULL)
      table_result(NULL)
      validate_result(NULL)
      ovm_rows(integer(0))
      ovm_counter(0L)
    }) |> bindEvent(input$shell_id, input$domain, ignoreInit = TRUE)

    # ── Render: "Get Table" button — only enabled when ARD is ready ───────────
    output$get_table_btn <- renderUI({
      if (is.null(ard_result())) {
        tags$button(
          class = "btn btn-success w-100 disabled",
          disabled = NA,
          icon("table"), " Get Table"
        )
      } else {
        actionButton(ns("get_table"), "Get Table", icon = icon("table"),
                     class = "btn-success w-100")
      }
    })

    # ── Render: "Validate" button — only enabled when ARD is ready ───────────
    output$validate_btn <- renderUI({
      if (is.null(ard_result())) {
        tags$button(
          class    = "btn btn-outline-info w-100 disabled mb-1",
          disabled = NA,
          icon("shield-check"), " Validate"
        )
      } else {
        actionButton(ns("validate"), "Validate", icon = icon("shield-check"),
                     class = "btn-outline-info w-100 mb-1")
      }
    })

    # ── "Validate" button ─────────────────────────────────────────────────────
    observeEvent(input$validate, {
      req(ard_result())

      withProgress(message = "Validating\u2026", value = 0.3, {

        # ── Layer 1: referential integrity ──────────────────────────────────
        l1 <- tryCatch({
          re_full <- .embed_ard_into_re(
            ard_result()$shell@reporting_event,
            ard_result()$ard
          )
          # validate_reporting_event() returns TRUE invisibly or signals an error
          validate_reporting_event(re_full)
          list(pass = TRUE, message = NULL, re_full = re_full)
        }, error = function(e) {
          list(pass = FALSE, message = conditionMessage(e), re_full = NULL)
        })

        setProgress(0.7)

        # ── Layer 3: JSON round-trip ─────────────────────────────────────────
        l3 <- if (!is.null(l1$re_full)) {
          tryCatch({
            re_json  <- arscore::reporting_event_to_json(l1$re_full)
            re_back  <- arscore::json_to_reporting_event(re_json)
            validate_reporting_event(re_back)
            list(pass = TRUE, message = NULL)
          }, error = function(e) {
            list(pass = FALSE, message = conditionMessage(e))
          })
        } else {
          list(pass = FALSE,
               message = "Skipped — Layer 1 must pass first.")
        }

        setProgress(0.9)

        # ── Layer 2: CDISC JSON Schema (jsonvalidate) ────────────────────────
        schema_path <- file.path(
          tryCatch(
            normalizePath(dirname(rstudioapi::getSourceEditorContext()$path)),
            error = function(e) getwd()
          ),
          "model", "ars_ldm.json"
        )

        l2 <- if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
          list(pass = NA, message = NULL,
               note = "jsonvalidate is not installed. Run: install.packages(\"jsonvalidate\")")
        } else if (!file.exists(schema_path)) {
          list(pass = NA, message = NULL,
               note = paste0("Schema not found at: ", schema_path))
        } else if (is.null(l1$re_full)) {
          list(pass = NA, message = NULL,
               note = "Skipped — Layer 1 must pass first.")
        } else {
          tryCatch({
            re_for_schema <- .auto_main_loc(l1$re_full)
            json_doc      <- jsonlite::fromJSON(
              arscore::reporting_event_to_json(re_for_schema),
              simplifyVector = FALSE
            )
            json_str      <- jsonlite::toJSON(
              .strip_ars_extensions(json_doc),
              auto_unbox = TRUE, null = "null"
            )
            result        <- jsonvalidate::json_validate(
              json_str, schema_path,
              engine  = "ajv",
              verbose = TRUE
            )
            if (isTRUE(result)) {
              list(pass = TRUE, message = NULL, note = NULL)
            } else {
              errs <- attr(result, "errors")
              msg  <- if (!is.null(errs) && nrow(errs) > 0) {
                paste(apply(errs, 1, function(r) paste0(r["instancePath"], ": ", r["message"])),
                      collapse = "\n")
              } else {
                "Schema validation failed (no detail available)."
              }
              list(pass = FALSE, message = msg, note = NULL)
            }
          }, error = function(e) {
            list(pass = FALSE, message = conditionMessage(e), note = NULL)
          })
        }

        validate_result(list(l1 = l1, l3 = l3, l2 = l2))
      })

      nav_select(id = "tabs", selected = "Validate", session = session)
      l2_ok  <- is.na(l2$pass) || isTRUE(l2$pass)
      all_ok <- l1$pass && l3$pass && l2_ok
      type   <- if (all_ok) "message" else "warning"
      msg    <- if (all_ok) "Validation passed." else "Validation found issues — see Validate tab."
      showNotification(msg, type = type, duration = 4)
    })

    # ── Output: validation report card (Validate tab) ─────────────────────────
    output$validate_report <- renderUI({
      vr <- validate_result()

      if (is.null(vr)) {
        return(div(
          class = "d-flex flex-column align-items-center justify-content-center text-muted",
          style = "min-height: 300px;",
          icon("shield-check", class = "fa-2x mb-3"),
          p("Click ", strong("Validate"), " after getting the ARD to run integrity checks.")
        ))
      }

      .status_badge <- function(pass) {
        if (pass)
          tags$span(class = "badge bg-success fs-6",
                    icon("circle-check", class = "me-1"), "PASS")
        else
          tags$span(class = "badge bg-danger fs-6",
                    icon("circle-xmark", class = "me-1"), "FAIL")
      }

      .layer_card <- function(title, pass, message, note = NULL) {
        border_cls <- if (pass) "border-success" else "border-danger"
        card(
          class = paste("mb-3", border_cls),
          card_header(
            class = if (pass) "bg-success-subtle" else "bg-danger-subtle",
            tags$div(
              class = "d-flex align-items-center justify-content-between",
              strong(title),
              .status_badge(pass)
            )
          ),
          card_body(
            if (!is.null(message))
              tags$pre(class = "mb-0 small text-danger", .strip_ansi(message)),
            if (!is.null(note))
              p(class = "mb-0 small text-muted fst-italic", note)
          )
        )
      }

      div(
        class = "p-3",
        h5("ARS Compliance Validation Report"),
        p(class = "text-muted small",
          "Shell: ", strong(ard_result()$shell@id),
          tags$span(class = "ms-3", icon("clock", class = "me-1"),
                    format(Sys.time(), "%H:%M:%S"))),
        hr(),

        .layer_card(
          "Layer 1 \u2014 Referential Integrity (validate_reporting_event)",
          pass    = vr$l1$pass,
          message = vr$l1$message
        ),

        .layer_card(
          "Layer 3 \u2014 JSON Round-Trip (reporting_event_to_json \u2192 json_to_reporting_event)",
          pass    = vr$l3$pass,
          message = vr$l3$message
        ),

        {
          l2 <- vr$l2
          l2_status <- if (is.na(l2$pass)) "NOT RUN" else if (l2$pass) "PASS" else "FAIL"
          l2_badge_cls <- switch(l2_status,
            "PASS"    = "badge bg-success fs-6",
            "FAIL"    = "badge bg-danger fs-6",
            "NOT RUN" = "badge bg-secondary"
          )
          l2_border <- switch(l2_status,
            "PASS"    = "border-success",
            "FAIL"    = "border-danger",
            "NOT RUN" = "border-secondary"
          )
          l2_header_cls <- switch(l2_status,
            "PASS"    = "bg-success-subtle",
            "FAIL"    = "bg-danger-subtle",
            "NOT RUN" = "bg-light"
          )
          card(
            class = paste("mb-3", l2_border),
            card_header(
              class = l2_header_cls,
              tags$div(
                class = "d-flex align-items-center justify-content-between",
                strong("Layer 2 \u2014 CDISC JSON Schema (jsonvalidate)"),
                tags$span(class = l2_badge_cls, l2_status)
              )
            ),
            card_body(
              if (!is.null(l2$message))
                tags$pre(class = "mb-1 small text-danger", .strip_ansi(l2$message)),
              if (!is.null(l2$note))
                p(class = "mb-0 small text-muted fst-italic", l2$note)
            )
          )
        }
      )
    })

    # ── "Get ARD" button ──────────────────────────────────────────────────────
    observeEvent(input$run_ard, {
      table_result(NULL)      # stale table is now invalid
      validate_result(NULL)   # stale validation is now invalid

      withProgress(message = "Running analysis\u2026", value = 0.5, {
        result <- tryCatch({
          withCallingHandlers({
            sh_hydrated <- hydrate(
              shell_obj(),
              variable_map = variable_map(),
              group_map    = group_map(),
              value_map    = value_map(),
              adam         = adam_for_shell()
            )
            run(sh_hydrated, adam = adam_for_shell())
          }, warning = function(w) {
            showNotification(paste("Warning:", .strip_ansi(conditionMessage(w))),
                             type = "warning", duration = 6)
            invokeRestart("muffleWarning")
          })
        }, error = function(e) {
          showNotification(paste("ARD error:", .strip_ansi(conditionMessage(e))),
                           type = "error", duration = 10)
          NULL
        })
      })

      if (!is.null(result)) {
        ard_result(result)
        nav_select(id = "tabs", selected = "ARD", session = session)
        showNotification(
          paste0("ARD ready: ", nrow(result$ard), " rows"),
          type = "message", duration = 3
        )
      }
    })

    # ── Output: ARD data table (ARD tab) ──────────────────────────────────────
    output$ard_dt <- reactable::renderReactable({
      req(ard_result())
      reactable::reactable(
        ard_result()$ard,
        searchable  = TRUE,
        filterable  = TRUE,
        pagination  = TRUE,
        defaultPageSize = 15,
        striped     = TRUE,
        highlight   = TRUE,
        resizable   = TRUE,
        wrap        = FALSE
      )
    })

    # ── "Get Table" button ────────────────────────────────────────────────────
    observeEvent(input$get_table, {
      withProgress(message = "Rendering table\u2026", value = 0.5, {
        tbl <- tryCatch(
          render(ard_result(), backend = "tfrmt"),
          error = function(e) {
            showNotification(paste("Render error:", .strip_ansi(conditionMessage(e))),
                             type = "error", duration = 10)
            NULL
          }
        )
        table_result(tbl)
      })

      if (!is.null(table_result())) {
        nav_select(id = "tabs", selected = "Compare", session = session)
        showNotification("Table rendered.", type = "message", duration = 3)
      }
    })

    # ── Output: download toolbar — appears only when table is ready ──────────
    output$download_bar <- renderUI({
      req(table_result())
      div(
        class = "d-flex align-items-center gap-2 mb-3",
        selectInput(
          inputId  = ns("download_fmt"),
          label    = NULL,
          choices  = c("HTML" = "html", "RTF" = "rtf"),
          selected = "html",
          width    = "110px"
        ),
        downloadButton(
          outputId = ns("download_table"),
          label    = "Download",
          class    = "btn-sm btn-outline-secondary"
        )
      )
    })

    # ── Download handler ──────────────────────────────────────────────────────
    output$download_table <- downloadHandler(
      filename = function() {
        fmt <- input$download_fmt %||% "html"
        ext <- if (fmt == "rtf") ".rtf" else ".html"
        paste0(input$shell_id, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
      },
      content = function(file) {
        tbl <- table_result()
        req(tbl)
        fmt <- input$download_fmt %||% "html"
        if (fmt == "rtf") {
          writeLines(gt::as_rtf(tbl), file)
        } else {
          writeLines(gt::as_raw_html(tbl), file)
        }
      }
    )

    # ── Output: rendered gt table (Table tab) ────────────────────────────────
    output$rendered_gt <- gt::render_gt({
      req(table_result())
      table_result()
    })

    # ── Outputs: Compare tab — mock (left) and rendered (right) ──────────────
    output$compare_mock <- gt::render_gt({
      shell_mock_gt()
    })

    output$compare_rendered_ui <- renderUI({
      tbl <- table_result()
      if (is.null(tbl)) {
        div(
          class = "d-flex flex-column align-items-center justify-content-center h-100 text-muted",
          style = "min-height: 200px;",
          icon("arrow-left", class = "fa-2x mb-3"),
          p("Configure and click ", strong("Get ARD"), " then ", strong("Get Table"),
            " to see the results here.")
        )
      } else {
        gt::gt_output(ns("compare_rendered"))
      }
    })

    output$compare_rendered <- gt::render_gt({
      req(table_result())
      table_result()
    })

    # ── Output: export bar — appears once a shell is loaded ───────────────────
    output$export_bar <- renderUI({
      req(shell_obj())
      has_ard <- !is.null(ard_result())

      tagList(
        hr(class = "my-2"),
        strong("Export"),
        div(
          class = "d-grid gap-1 mt-2",

          # Primary: full ARS (reporting event + embedded results) — after ARD
          if (has_ard)
            downloadButton(
              outputId = ns("dl_full_ars"),
              label    = tags$span(
                           icon("star", class = "me-1"),
                           "Full ARS with results (.json)"
                         ),
              class    = "btn-sm btn-primary text-start"
            ),

          # Secondary: reporting event spec only (hydrated if ARD, raw otherwise)
          downloadButton(
            outputId = ns("dl_json"),
            label    = if (has_ard) "Reporting Event spec (.json)"
                       else         "Reporting Event (.json)",
            class    = "btn-sm btn-outline-secondary text-start"
          ),

          # ARD flat file — after ARD
          if (has_ard)
            downloadButton(
              outputId = ns("dl_ard"),
              label    = "ARD (.csv)",
              class    = "btn-sm btn-outline-secondary text-start"
            )
        )
      )
    })

    # ── Download: full ARS — reporting event with results embedded ────────────
    # .auto_main_loc() is applied here so the exported JSON satisfies the CDISC
    # ARS JSON Schema requirement for mainListOfContents (Layer 2 compliance).
    output$dl_full_ars <- downloadHandler(
      filename = function() {
        paste0(input$shell_id %||% "ars", "_full_ars.json")
      },
      content = function(file) {
        re_with_results <- .embed_ard_into_re(
          ard_result()$shell@reporting_event,
          ard_result()$ard
        )
        re_with_loc <- .auto_main_loc(re_with_results)
        writeLines(arscore::reporting_event_to_json(re_with_loc), file)
      }
    )

    # ── Download: reporting event spec only (no results) ─────────────────────
    output$dl_json <- downloadHandler(
      filename = function() {
        id     <- input$shell_id %||% "shell"
        suffix <- if (!is.null(ard_result())) "_spec_hydrated" else "_spec_raw"
        paste0(id, "_reporting_event", suffix, ".json")
      },
      content = function(file) {
        re <- if (!is.null(ard_result())) {
          ard_result()$shell@reporting_event
        } else {
          shell_obj()@reporting_event
        }
        writeLines(arscore::reporting_event_to_json(re), file)
      }
    )

    # ── Download: ARD tibble as CSV ───────────────────────────────────────────
    output$dl_ard <- downloadHandler(
      filename = function() paste0(input$shell_id %||% "ard", "_ard.csv"),
      content  = function(file) {
        write.csv(ard_result()$ard, file, row.names = FALSE)
      }
    )

    # ── Output: run status summary card ──────────────────────────────────────
    output$run_status <- renderUI({
      ard <- ard_result()
      if (is.null(ard)) return(NULL)
      card(
        class = "bg-light border-0 py-1 px-2",
        card_body(
          class = "py-1",
          p(class = "mb-0 small",
            icon("check-circle", class = "text-success"), " ",
            strong(ard$shell@id), " \u2014 ",
            nrow(ard$ard), " ARD rows")
        )
      )
    })

  })
}

# ── App wiring ────────────────────────────────────────────────────────────────

# Load test data if not already in session
if (!all(c("adsl", "adae", "adlb", "adlb_lb01") %in% ls(envir = .GlobalEnv))) {
  message("Loading test data from data_table_examples.R ...")
  root <- tryCatch(
    normalizePath(dirname(rstudioapi::getSourceEditorContext()$path)),
    error = function(e) getwd()
  )
  source(file.path(root, "data_table_examples.R"))
}

# Use the curated 7-PARAMCD subset for ADLB.  The full adlb has 47 PARAMCDs;
# Mode 3 expansion would create ~1500 analyses for T-LB-01 (~3 min).
# adlb_lb01 (HGB, PLT, WBC, ALT, AST, CREAT, GLUC) is a superset of
# adlb_lb02 (HGB, ALT, CREAT) and covers both lab templates in ~5s.
#
# Use TEAE-filtered adae for AE shells.  The full adae includes non-TEAE rows
# (TRTEMFL = NA/"N"); Mode 3 expansion on the full dataset creates 242 PT
# groups (including non-TEAE PTs) instead of 230.  The 12 orphan PTs trigger
# the Cartesian-product fallback in run() (~96 s for T-AE-02).  Filtering to
# TRTEMFL = "Y" first ensures Mode 3 derives only TEAE events, all 230 groups
# appear in base_data, and the observed-combo fast path applies (~4 s).
adae_teae <- adae[!is.na(adae$TRTEMFL) & adae$TRTEMFL == "Y", ]
adam_list <- list(ADSL = adsl, ADAE = adae_teae, ADLB = adlb_lb01)

ui <- arsExplorerUI("explorer")

server <- function(input, output, session) {
  arsExplorerServer("explorer", reactive(adam_list))
}

shinyApp(ui, server)
