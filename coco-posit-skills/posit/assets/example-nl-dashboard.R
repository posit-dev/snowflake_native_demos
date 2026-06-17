# Worked Example: Natural Language Sales Dashboard
# Posit Team Native App + Snowflake + querychat + Cortex
#
# BEFORE YOUR FIRST RUN:
#   Run scripts/setup-demo-data.sql to create sample data.
#
# CONFIGURE via environment variables (or edit defaults below):
#   DEMO_DATABASE  — default: SOL_ENG_DEMO
#   DEMO_SCHEMA    — default: COCO_DEMO
#
# Deploy with: rsconnect::deployApp(appDir = ".", appName = "sales-nl-dashboard")
# Cleanup:     Run scripts/teardown-demo.sql

library(shiny)
library(bslib)
library(DBI)
library(dplyr)
library(ggplot2)
library(scales)
library(querychat)
library(chatlas)

# ── Configuration ─────────────────────────────────────────────────────────────
DEMO_DB     <- Sys.getenv("DEMO_DATABASE", "SOL_ENG_DEMO")
DEMO_SCHEMA <- Sys.getenv("DEMO_SCHEMA", "COCO_DEMO")
FQN         <- paste(DEMO_DB, DEMO_SCHEMA, sep = ".")

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- page_navbar(
  title = "Sales Intelligence",
  theme = bs_theme(preset = "flatly", primary = "#447099"),

  nav_panel(
    "Ask a Question",
    layout_columns(
      col_widths = c(4, 8),

      # Left: Natural language query panel
      card(
        card_header("Ask in plain English"),
        querychat_ui("qc"),
        p(class = "text-muted mt-2 small",
          "Powered by Snowflake Cortex. ",
          "Results are filtered to your Snowflake role.")
      ),

      # Right: Dynamic results
      card(
        card_header("Results"),
        DT::dataTableOutput("query_results"),
        uiOutput("query_sql_display")
      )
    )
  ),

  nav_panel(
    "Overview",
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Revenue by Region"), plotOutput("region_chart")),
      card(card_header("Top Products"),      plotOutput("product_chart"))
    )
  ),

  nav_panel(
    "AI Analyst",
    card(
      card_header("Chat with your data"),
      # shinychat streaming widget
      shinychat::chat_ui("analyst_chat"),
      p(class = "text-muted small",
        "This assistant has read-only access to your Snowflake views.")
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # Connection — in Native App, inherits viewer OAuth token automatically
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  onStop(function() DBI::dbDisconnect(con))

  # ── Remote table references (lazy — no data transferred yet) ──
  sales_tbl    <- tbl(con, in_schema(FQN, "SALES_FACT"))
  products_tbl <- tbl(con, in_schema(FQN, "PRODUCT_DIM"))
  customers_tbl <- tbl(con, in_schema(FQN, "CUSTOMER_DIM"))

  # ── querychat ──────────────────────────────────────────────────
  qc <- querychat_server(
    "qc",
    tables = list(
      sales     = sales_tbl,
      products  = products_tbl,
      customers = customers_tbl
    ),
    model = "claude-sonnet-4",
    con   = con,
    schema_description = "
      sales: Transaction records. Columns: sale_id (PK), sale_date, amount (USD),
             region (EAST|WEST|CENTRAL|SOUTH), product_id (FK), customer_id (FK).
      products: Product catalog. Columns: product_id (PK), name, category, unit_price.
      customers: CRM data. Columns: customer_id (PK), segment, country, signup_date.
      Scope: Answer questions about revenue, volume, product mix, and segments.
      Do NOT expose customer_id or sale_id in results — aggregate only.
    "
  )

  output$query_results <- DT::renderDataTable({
    req(qc())
    DT::datatable(qc(), options = list(pageLength = 10, scrollX = TRUE))
  })

  output$query_sql_display <- renderUI({
    req(attr(qc(), "sql"))
    tagList(
      hr(),
      strong("Generated SQL:"),
      pre(class = "bg-light p-2 small", attr(qc(), "sql"))
    )
  })

  # ── Overview charts ────────────────────────────────────────────
  overview_data <- reactive({
    sales_tbl |>
      left_join(products_tbl, by = "product_id") |>
      collect()
  })

  output$region_chart <- renderPlot({
    overview_data() |>
      group_by(region) |>
      summarise(revenue = sum(amount)) |>
      ggplot(aes(reorder(region, revenue), revenue, fill = region)) +
      geom_col(show.legend = FALSE) +
      coord_flip() +
      scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
      scale_fill_brewer(palette = "Blues", direction = -1) +
      labs(x = NULL, y = "Revenue (millions)") +
      theme_minimal(base_size = 13)
  })

  output$product_chart <- renderPlot({
    overview_data() |>
      group_by(category) |>
      summarise(revenue = sum(amount)) |>
      slice_max(revenue, n = 10) |>
      ggplot(aes(reorder(category, revenue), revenue)) +
      geom_col(fill = "#447099") +
      coord_flip() +
      scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
      labs(x = NULL, y = "Revenue (millions)") +
      theme_minimal(base_size = 13)
  })

  # ── AI Analyst chat ────────────────────────────────────────────
  analyst <- chat_cortex(
    model = "claude-sonnet-4",
    system_prompt = paste(
      "You are a data analyst for this company.",
      "You have access to Snowflake tables: ANALYTICS.SALES_FACT,",
      "ANALYTICS.PRODUCT_DIM, ANALYTICS.CUSTOMER_DIM.",
      "Answer business questions about revenue, products, and customers.",
      "Be concise and precise. Use numbers when available.",
      "Do not expose PII or raw customer IDs."
    )
  )

  observeEvent(input$analyst_chat_user_input, {
    stream <- analyst$stream_async(input$analyst_chat_user_input)
    shinychat::chat_append("analyst_chat", stream)
  })
}

shinyApp(ui, server)
