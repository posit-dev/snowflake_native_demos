# Cortex-Backed AI Tools for Posit Workflows

Posit ships four open-source packages that integrate with Snowflake Cortex to
add AI capabilities inside the IDE and deployed apps — with no data leaving
the Snowflake security perimeter.

---

## Tool map

| Package | Purpose | Where used |
|---|---|---|
| `{chatlas}` | Chat with any LLM (including Cortex) from R | Scripts, Shiny, Quarto |
| `{querychat}` | Natural language → SQL in Shiny apps | Deployed Shiny apps |
| `{gander}` | Context-aware code suggestions in the IDE | Positron / RStudio |
| `{chores}` | Automate repetitive IDE tasks (document, test, refactor) | Positron / RStudio |

`gander` and `chores` are IDE-only tools invoked interactively. `chatlas` and
`querychat` are used in code — covered in detail below.

---

## `{chatlas}` — Cortex LLMs from R

`{chatlas}` is the Posit unified interface for LLM chat. It supports Anthropic,
OpenAI, Google, AWS Bedrock, and **Snowflake Cortex**. Inside the Posit Team
Native App, Cortex is used by default (no API key needed).

### Setup

```r
install.packages("chatlas")   # CRAN
```

### Create a Cortex chat session

```r
library(chatlas)

# Inside Native App: credentials are inherited automatically
chat <- chat_cortex(
  model    = "claude-sonnet-4",    # or "llama3.1-70b", "mistral-large", etc.
  system_prompt = "You are a data analyst assistant. Answer questions about
                   sales data concisely and accurately."
)

# Single-turn
chat$chat("What were the top 5 products by revenue last quarter?")

# Multi-turn (maintains history)
chat$chat("Which of those had the highest growth vs the prior quarter?")
```

### Available Cortex models (via chatlas)

```r
# List models configured for your Snowflake account
chatlas::cortex_models()
```

Common choices:

| Model ID | Use case |
|---|---|
| `claude-sonnet-4` | General assistant, code generation |
| `claude-opus-4` | Complex reasoning, long documents |
| `llama3.1-70b` | Fast, cost-effective general tasks |
| `mistral-large` | Multilingual, structured outputs |

### Streaming responses in Shiny

```r
library(shiny)
library(chatlas)
library(shinychat)  # companion package for Shiny streaming UI

ui <- fluidPage(
  chat_ui("chat")   # shinychat widget
)

server <- function(input, output, session) {
  chat <- chat_cortex(model = "claude-sonnet-4",
                      system_prompt = "You are a helpful data assistant.")

  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream)
  })
}
```

---

## `{querychat}` — Natural Language → SQL in Shiny

`{querychat}` adds a conversational interface to any Shiny app that lets
business users ask questions in plain English. Their question is translated to
SQL by a Cortex LLM, run against Snowflake, and the result is displayed — with
full viewer-level RBAC enforcement.

### Setup

```r
install.packages("querychat")
```

### Basic integration

```r
library(shiny)
library(bslib)
library(querychat)
library(DBI)
library(dplyr)

# Full Shiny app with querychat sidebar
ui <- page_sidebar(
  title   = "Sales Intelligence",
  sidebar = sidebar(
    title = "Ask a question",
    querychat_ui("qc")
  ),
  card(
    card_header("Results"),
    DT::dataTableOutput("results_table")
  )
)

server <- function(input, output, session) {
  con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")
  onStop(function() DBI::dbDisconnect(con))

  # Reference the tables querychat is allowed to query
  # Snowflake RBAC automatically limits what the viewer can see
  available_tables <- list(
    sales   = tbl(con, in_schema("ANALYTICS", "SALES_FACT")),
    products = tbl(con, in_schema("ANALYTICS", "PRODUCT_DIM")),
    customers = tbl(con, in_schema("ANALYTICS", "CUSTOMER_DIM"))
  )

  # querychat_server returns a reactive with the current query result
  qc <- querychat_server(
    "qc",
    tables     = available_tables,
    model      = "claude-sonnet-4",    # Cortex model
    con        = con
  )

  output$results_table <- DT::renderDataTable({
    qc()   # reactive data frame with the latest query result
  })
}

shinyApp(ui, server)
```

### Restricting scope

```r
# Pass a schema description to improve query accuracy and limit scope
qc <- querychat_server(
  "qc",
  tables       = available_tables,
  model        = "claude-sonnet-4",
  con          = con,
  schema_description = "
    sales: Daily transaction records. Columns: sale_id, sale_date, amount,
           region, product_id, customer_id.
    products: Product catalog. Columns: product_id, name, category, unit_price.
    customers: CRM data. Columns: customer_id, segment, signup_date, country.
    Only answer questions about revenue, volume, and customer behaviour.
    Do not return PII columns (email, phone).
  "
)
```

---

## Positron Assistant (IDE AI)

Positron Assistant is the AI coding assistant built into Positron IDE. When
running inside the Posit Team Native App:

- **Auto-configured**: Snowflake Cortex is the default LLM backend — no API
  key, no setup.
- **Data-aware**: It knows you are writing data science code, not application
  code, and tailors suggestions accordingly.
- **In-context**: It is aware of open files, loaded data frames, and the
  active Snowflake schema.

### Invocation

- **Chat pane**: Open with `Cmd+Shift+I` (Mac) / `Ctrl+Shift+I` (Windows).
- **Inline suggestions**: Press `Tab` to accept.
- **Command**: `Cmd+K` on a selection to explain, refactor, or document.

### Effective prompts for data science

```
# In chat pane:
"Rewrite this dbplyr pipeline to be more efficient for Snowflake"
"Generate a recipe with step_normalize and step_dummy for these columns: ..."
"Write a ggplot2 chart for this data frame showing revenue over time"
"Translate this tidymodels workflow to orbital SQL"
"Write rsconnect::deployApp() code for this Shiny app targeting prod-connect"
```

---

## Security note

All Cortex AI calls from within the Posit Team Native App stay inside your
Snowflake account. Prompts and responses are not sent to Anthropic or OpenAI
directly — they go through Snowflake Cortex, which operates under your
Snowflake RBAC policies and data residency controls. This is the key data
privacy advantage over external LLM APIs.
