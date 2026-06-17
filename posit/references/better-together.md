# Better Together: CoCo + Posit Assistant + Connect

Three agents, one Snowflake security perimeter, one data lifecycle. Each does
what it's positioned for; the handoffs are where the value compounds.

## The three agents

| Agent | Where it runs | Cortex-backed | Best at |
|---|---|---|---|
| **CoCo** ($posit, $posit-prepare) | Snowsight / Desktop / CLI | yes | Snowflake-side work: catalog discovery, views, governance, scaffolding apps, deploy from outside the IDE |
| **Posit Assistant** | Positron IDE (in Workbench) | yes (Cortex inside the Native App) | IDE-side work: writing/iterating R & Python, running the app locally, refining, then deploying |
| **Posit Connect** | SPCS (in the Native App) | n/a | Hosting, scheduling, email, versioned + git-backed publishing, viewer-level RBAC |

All three use the same Snowflake identity and RBAC. Cortex is the shared LLM
backend for both CoCo and Posit Assistant — no external API keys, nothing
leaves the Snowflake perimeter.

## Who can deploy, and how (important distinction)

- **CoCo is OUTSIDE Workbench/SPCS.** It cannot reach https://connect
  directly, so it deploys via the stage-deploy bridge, or hands code to git
  for the user to publish. The $posit skill exists largely to solve this.
- **Posit Assistant is INSIDE Workbench/SPCS.** https://connect resolves
  natively, so it deploys directly — `rsconnect deploy` or the Positron
  Publish button. It does NOT need the $posit skill or the bridge to deploy.
  The skill is a CoCo construct; Posit Assistant is a separate agent and
  cannot invoke `$posit`. But it doesn't need to — deploy is built into the
  IDE it lives in.

So: the "$posit deploy" experience is for CoCo. The Posit-Assistant deploy
experience is the native Publish/rsconnect path. Same destination (Connect),
two different mechanisms, because the two agents sit on different sides of the
SPCS boundary.

## The full loop

```
1. CoCo / $posit-prepare      Discover + shape the data on Snowflake:
   (Snowsight or CLI)         curated views, dynamic tables, governance.
                              Emits a handoff summary.
        │  Snowflake objects (visible in every IDE) + handoff
        ▼
2. CoCo / $posit              Scaffold the app (10 frameworks), wire the
                              Connect connection, bake in FQ table names.
                              Deliver to git or the Workbench home dir.
        │  project folder in Workbench
        ▼
3. Posit Assistant            Iterate in Positron: refine UI, add logic,
   (in Workbench, Cortex)     run locally against live Snowflake data,
                              use ellmer/chatlas/querychat with Cortex.
        │  finished, tested app
        ▼
4. Posit Assistant → Connect  Click Publish (or rsconnect deploy). Deploys
                              directly because it's inside SPCS. Git-backed,
                              so the commit and the deployed version stay
                              linked. Viewer OAuth → Snowflake RBAC enforced.
```

## Why this beats any single agent

- **No context switching for the user.** They stay in Positron; the agents
  meet at Snowflake objects (going in) and the running app on Connect
  (coming out).
- **Right tool each step.** CoCo sees the whole account and the infra;
  Posit Assistant sees the open files and the live data frame. Neither does
  the other's job badly.
- **One security story.** Same Snowflake identity and RBAC across all three,
  Cortex as the shared model backend, nothing leaving the perimeter.
- **Versioned end to end.** Git-backed delivery + git-backed Connect publish
  means every deployed app traces to a commit.

## How $posit should talk about this

When a user is clearly working inside Workbench and wants to iterate, prefer
delivering code (git or home dir) and tell them Posit Assistant + the Publish
button will take it the rest of the way — don't force a CoCo-side deploy. When
a user just wants a running app and isn't in the IDE, use the bridge. Match
the path to where the user already is.
