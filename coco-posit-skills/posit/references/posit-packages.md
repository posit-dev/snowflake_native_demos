# Posit Open-Source Packages on Snowflake

Reach for these automatically based on what the user asks for. Default LLM
backend is Snowflake Cortex (no API key inside the Native App). All apps
deploy to Posit Connect and get their Snowflake token from the OAuth
integration via posit-sdk — never st.secrets or hardcoded keys.

---

## querychat — "let users ask questions about the data"

Natural-language → SQL over a table, with the LLM (Cortex) generating safe
SELECTs that run in Snowflake. RBAC is enforced by Snowflake automatically.

### Python (Shiny)

```python
# app.py
import os
import chatlas
from shiny import App, ui
import querychat
import snowflake.connector

def get_connection():
    from posit.connect.external.snowflake import PositAuthenticator
    auth = PositAuthenticator(local_authenticator="EXTERNALBROWSER")
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        authenticator=auth.authenticator, token=auth.token,
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE"),
    )

# Point querychat at a fully-qualified table; Cortex is the LLM
chat_client = chatlas.ChatSnowflake(model="claude-3-5-sonnet")

querychat_config = querychat.init(
    get_connection(),
    table_name="SOL_ENG_DEMO.GENOMEPATH_ONCOLOGY",
    client=chat_client,
    greeting="Ask me anything about the oncology dataset.",
)

app_ui = ui.page_sidebar(
    querychat.sidebar("chat"),
    ui.output_data_frame("table"),
    title="GenomePath Oncology Explorer",
)

def server(input, output, session):
    qc = querychat.server("chat", querychat_config)

    @render.data_frame
    def table():
        return qc["df"]()

app = App(app_ui, server)
```

requirements.txt: `shiny`, `querychat`, `chatlas`, `snowflake-connector-python`, `posit-sdk`, `pandas`

### R (Shiny)

```r
library(shiny)
library(querychat)
library(ellmer)
library(DBI)

con <- DBI::dbConnect(odbc::odbc(), dsn = "snowflake")

querychat_config <- querychat_init(
  con,
  table_name = "SOL_ENG_DEMO.GENOMEPATH_ONCOLOGY",
  chat_func  = function(...) ellmer::chat_snowflake(model = "claude-3-5-sonnet", ...),
  greeting   = "Ask me anything about the oncology dataset."
)

ui <- bslib::page_sidebar(
  title = "GenomePath Oncology Explorer",
  sidebar = querychat_sidebar("chat"),
  DT::DTOutput("table")
)

server <- function(input, output, session) {
  qc <- querychat_server("chat", querychat_config)
  output$table <- DT::renderDT(qc$df())
}

shinyApp(ui, server)
```

---

## ellmer (R) / chatlas (Python) — LLM chat & text generation

Posit's unified LLM interface. Same code works across providers; on Snowflake
it uses Cortex.

### R — ellmer

```r
library(ellmer)
chat <- chat_snowflake(
  model = "claude-3-5-sonnet",
  system_prompt = "You are a genomics data analyst. Be precise and concise."
)
chat$chat("Summarize the mutation frequency patterns in this cohort.")
```

### Python — chatlas

```python
import chatlas
chat = chatlas.ChatSnowflake(
    model="claude-3-5-sonnet",
    system_prompt="You are a genomics data analyst. Be precise and concise.",
)
chat.chat("Summarize the mutation frequency patterns in this cohort.")
```

Cortex models commonly available: claude-3-5-sonnet, claude-3-7-sonnet,
llama3.1-70b, mistral-large. List with `ellmer::models_snowflake()` /
`chatlas` equivalent.

---

## shinychat — streaming chat UI inside a Shiny app

Use when the user wants a conversational UI (not just NL→table). Pairs with
ellmer (R) or chatlas (Python).

### R

```r
library(shiny); library(shinychat); library(ellmer)

ui <- bslib::page_fluid(chat_ui("chat"))

server <- function(input, output, session) {
  chat <- chat_snowflake(model = "claude-3-5-sonnet",
                         system_prompt = "Answer questions about the oncology data.")
  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream)
  })
}
shinyApp(ui, server)
```

### Python

```python
from shiny import App, ui
from shinychat import chat_ui, Chat
import chatlas

app_ui = ui.page_fluid(chat_ui("chat"))

def server(input, output, session):
    chat = Chat("chat")
    client = chatlas.ChatSnowflake(model="claude-3-5-sonnet")
    @chat.on_user_submit
    async def _(message):
        await chat.append_message_stream(client.stream(message))

app = App(app_ui, server)
```

---

## ragnar (R) — retrieval-augmented generation

Use when the user wants to "search documents" or ground answers in a corpus.
Store embeddings in Snowflake, retrieve, then answer with ellmer.

```r
library(ragnar); library(ellmer)

store <- ragnar_store_create(
  location = "SOL_ENG_DEMO.RAG.ONCOLOGY_LITERATURE",  # Snowflake-backed store
  embed = \(x) embed_snowflake(x, model = "snowflake-arctic-embed-m")
)
# Retrieve + answer
chunks <- ragnar_retrieve(store, "BRCA1 treatment response", top_k = 6)
chat <- chat_snowflake(model = "claude-3-5-sonnet")
chat$chat(paste("Using these sources, answer the question:",
                paste(chunks$text, collapse = "\n\n")))
```

---

## Tables — gt / great_tables, reactable / itables

- **Static, publication-quality:** gt (R) / great_tables (Python)
- **Interactive (sort/filter/page):** reactable (R) / itables (Python)

```r
library(gt)
df |> gt() |> tab_header(title = "Cohort Summary") |> fmt_number(columns = where(is.numeric))
```
```python
from great_tables import GT
GT(df).tab_header(title="Cohort Summary")
```

---

## Maps — leaflet

```r
library(leaflet)
leaflet(sites_df) |> addTiles() |>
  addCircleMarkers(~lon, ~lat, popup = ~site_name)
```

---

## ML lifecycle — tidymodels + orbital + vetiver + pins

- **tidymodels**: build the model in R
- **orbital**: translate the fitted workflow to Snowflake SQL for in-database
  scoring (see `references/orbital-patterns.md`)
- **vetiver**: version, deploy, and monitor the model
- **pins**: store model + data artifacts on Connect

These compose: fit with tidymodels → score in-DB with orbital → publish the
scoring view → serve/monitor with vetiver, artifacts pinned to Connect.

---

## mall — run an LLM over every row of a table

Use when the user wants per-row LLM work: sentiment, classification,
extraction, summarization across a column. Runs against Cortex; works in
both R and Python and operates on data frames / dbplyr tables.

### R
```r
library(mall); library(dplyr)
llm_use("snowflake", "claude-3-5-sonnet")   # Cortex backend

tbl(con, in_schema("SOL_ENG_DEMO", "GENOMEPATH_ONCOLOGY")) |>
  head(500) |>
  llm_classify(clinical_note, c("responder", "non-responder")) |>
  collect()
```

### Python
```python
import mall
df.llm.use("snowflake", "claude-3-5-sonnet")
df.llm.classify("clinical_note", ["responder", "non-responder"])
```

---

## btw (R) — complete R-to-LLM toolkit with tool calling

Use when the chatbot needs to call R functions / query data as tools, not
just chat. Pairs with ellmer.

```r
library(btw); library(ellmer)
chat <- chat_snowflake(model = "claude-3-5-sonnet")
btw_register_tools(chat)   # exposes data + R tools to the model
chat$chat("How many high-risk patients are in the cohort, and plot the age distribution?")
```

---

## Rule of thumb

If the user describes an *outcome* ("ask questions", "search docs", "nice
table", "predict"), pick the package from the map in SKILL.md and wire it to
Cortex + Connect using the patterns above. Always add the package to
requirements.txt (Python) or library() calls (R), and include posit-sdk so
the Snowflake token resolves on Connect. Bake fully-qualified table names
into the code.
