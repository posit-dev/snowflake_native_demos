# R Conventions for Posit + Snowflake Workflows

## Core principle: push compute to Snowflake

Use `{dbplyr}` to keep transformations in Snowflake SQL. Only `collect()` when
you need data in R memory (plotting, modelling, small summary tables).

```r
library(DBI)
library(dplyr)
library(dbplyr)

# Reference a remote Snowflake table — no data transferred yet
sales_tbl <- tbl(con, in_schema("ANALYTICS", "SALES_FACT"))

# Build the transformation — still lazy SQL
result <- sales_tbl |>
  filter(region == "WEST", year(sale_date) == 2025) |>
  group_by(product_category) |>
  summarise(revenue = sum(amount, na.rm = TRUE)) |>
  arrange(desc(revenue))

# Inspect the generated SQL before running it
show_query(result)

# Pull into R only when needed
result_df <- collect(result)
```

---

## Data access patterns

### Table reference shortcuts

```r
# By full path
tbl(con, in_schema("DB.SCHEMA", "TABLE"))

# By Id (preferred for disambiguation)
tbl(con, Id(database = "ANALYTICS_DB", schema = "PUBLIC", table = "CUSTOMERS"))

# Via SQL string
tbl(con, sql("SELECT * FROM ANALYTICS_DB.PUBLIC.CUSTOMERS WHERE active = TRUE"))
```

### Writing results back

```r
# Write a new table
DBI::dbWriteTable(con, DBI::Id(schema = "SANDBOX", table = "MY_RESULTS"), result_df)

# Append to existing
DBI::dbWriteTable(con, "MY_RESULTS", result_df, append = TRUE)
```

---

## ggplot2 conventions

Always `collect()` before plotting. Use `{scales}` for formatting.

```r
library(ggplot2)
library(scales)

result_df |>
  ggplot(aes(x = reorder(product_category, revenue), y = revenue)) +
  geom_col(fill = "#447099") +         # Posit blue
  coord_flip() +
  scale_y_continuous(labels = dollar_format(scale = 1e-6, suffix = "M")) +
  labs(
    title    = "Revenue by Product Category",
    subtitle = "Snowflake ANALYTICS_DB · SALES_FACT",
    x        = NULL,
    y        = "Revenue (USD millions)"
  ) +
  theme_minimal(base_size = 13)
```

---

## Shiny app conventions

Use `{bslib}` for modern layout and `{thematic}` for auto-theming plots.

### Minimal Shiny + Snowflake template

```r
library(shiny)
library(bslib)
library(DBI)
library(dplyr)

# Connection is shared across the session for Shiny
# In the Native App, this inherits viewer-level Snowflake credentials
# when viewer OAuth is enabled in Posit Connect

ui <- page_sidebar(
  title = "Sales Dashboard",
  sidebar = sidebar(
    selectInput("region", "Region", choices = c("EAST", "WEST", "CENTRAL"))
  ),
  card(plotOutput("revenue_chart"))
)

server <- function(input, output, session) {
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  onStop(function() DBI::dbDisconnect(con))

  revenue_data <- reactive({
    tbl(con, in_schema("ANALYTICS", "SALES_FACT")) |>
      filter(region == !!input$region) |>
      group_by(month = floor_date(sale_date, "month")) |>
      summarise(revenue = sum(amount)) |>
      collect()
  })

  output$revenue_chart <- renderPlot({
    revenue_data() |>
      ggplot(aes(month, revenue)) +
      geom_line(color = "#447099", linewidth = 1.2) +
      scale_y_continuous(labels = scales::dollar_format()) +
      labs(title = paste("Monthly Revenue —", input$region)) +
      theme_minimal()
  })
}

shinyApp(ui, server)
```

### Key Shiny best practices

- Use `reactive()` for data dependencies, not `observe()`.
- Call `onStop()` to close the DB connection when the session ends.
- For large datasets, filter on the Snowflake side before `collect()`.
- Use `{bslib}` `page_*` layouts (not `fluidPage` / `navbarPage`).
- Wrap heavy operations in `withProgress()` for user feedback.

---

## Quarto document conventions

```yaml
---
title: "Q3 Revenue Analysis"
author: "Data Science Team"
date: today
format:
  html:
    toc: true
    code-fold: true
execute:
  echo: false
  warning: false
---
```

```r
#| label: setup
#| include: false
library(DBI)
library(dplyr)
library(ggplot2)
con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
```

```r
#| label: fig-revenue
#| fig-cap: "Monthly revenue trend"
tbl(con, "SALES_FACT") |>
  group_by(month = floor_date(sale_date, "month")) |>
  summarise(revenue = sum(amount)) |>
  collect() |>
  ggplot(aes(month, revenue)) +
  geom_line(color = "#447099") +
  theme_minimal()
```

### Parameterised Quarto reports

```yaml
params:
  region: "WEST"
  start_date: "2025-01-01"
```

```r
#| label: filtered-data
data <- tbl(con, "SALES_FACT") |>
  filter(region == params$region, sale_date >= params$start_date) |>
  collect()
```

Render with specific parameters from R:

```r
quarto::quarto_render(
  "report.qmd",
  execute_params = list(region = "EAST", start_date = "2025-06-01")
)
```

---

## Package standards

| Task | Preferred package | Notes |
|---|---|---|
| DB connections | `{DBI}` + `{odbc}` | Use Posit Professional Drivers |
| Remote SQL | `{dbplyr}` | Never write raw SQL for transforms |
| Data wrangling | `{dplyr}`, `{tidyr}` | |
| Visualisation | `{ggplot2}`, `{plotly}` | |
| ML | `{tidymodels}` (parsnip + recipes) | See orbital-patterns.md |
| Shiny layout | `{bslib}` | Not `fluidPage` |
| Reports | `{quarto}` | Not `{rmarkdown}` for new projects |
| Package management | `{renv}` | Always lock before deploying |
| AI chat | `{chatlas}` | See cortex-ai-tools.md |
| NL-to-SQL | `{querychat}` | See cortex-ai-tools.md |
