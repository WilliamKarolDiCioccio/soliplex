"""Generative UI tools: render interactive widgets in the chat via tool calls.

The LLM calls these tools to produce structured JSON specs. The AG-UI
TOOL_CALL_RESULT carries the spec back to the Flutter frontend, which
renders the matching widget (form, chart, …) directly in the message list.

render_bar_chart_from_script additionally runs a Python script in the
bubblewrap sandbox, validates its JSON output through Pydantic, and emits
a STATE_DELTA so the backend always knows what widget is on screen.
"""

import json as _json_std
from typing import Literal, Optional

import jsonpatch
import pydantic_ai
from ag_ui import core as agui_core
from bubble_sandbox import config as bs_config
from bubble_sandbox import sandbox as bs_sandbox
from pydantic import BaseModel, Field

from soliplex import agents
from soliplex.skills.bwrap_sandbox import (
    get_extra_volumes,
    get_workdir,
    skill_execute_script,
)

GENUI_STATE_KEY = "genui"


# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------


class FormField(BaseModel):
    """A single interactive form field."""

    label: str = Field(..., description="Display label shown above the input")
    field_type: Literal[
        "text", "email", "number", "checkbox", "dropdown", "selector"
    ] = Field(
        ...,
        description=(
            "Input kind: "
            "'text' — plain text input; "
            "'email' — email address input; "
            "'number' — numeric input; "
            "'checkbox' — yes/no toggle; "
            "'dropdown' — single choice from the 'options' list; "
            "'selector' — multi-select chips from the 'options' list."
        ),
    )
    required: bool = Field(default=True, description="Whether the field is required")
    placeholder: Optional[str] = Field(
        default=None,
        description="Hint text shown inside text/email/number inputs",
    )
    options: Optional[list[str]] = Field(
        default=None,
        description=(
            "Required when field_type is 'dropdown' or 'selector': "
            "selectable values"
        ),
    )


class DynamicForm(BaseModel):
    title: str
    fields: list[FormField]
    submit_label: str = "Submit"


async def render_form(
    title: str,
    fields: list[FormField],
    submit_label: str = "Submit",
) -> str:
    """Render an interactive data-entry form in the chat.

    Call this tool whenever you need to collect structured input from the user.
    Do NOT describe the form in prose — call this tool directly.

    Supported field_type values: text, email, number, checkbox, dropdown,
    selector. Use 'options' for 'dropdown' and 'selector' fields.

    Example — contact form:
      render_form(
          title="Contact Us",
          fields=[
              {"label": "Name",     "field_type": "text",     "required": true},
              {"label": "Email",    "field_type": "email",    "required": true},
              {"label": "Priority", "field_type": "dropdown", "required": true,
               "options": ["Low", "Medium", "High"]},
          ]
      )

    Returns:
        JSON spec consumed by the frontend to render the form widget.
    """
    form = DynamicForm(title=title, fields=fields, submit_label=submit_label)
    return form.model_dump_json()


# ---------------------------------------------------------------------------
# Stock chart
# ---------------------------------------------------------------------------


class StockBar(BaseModel):
    """A single data bar in the stock chart."""

    label: str = Field(
        ...,
        description=(
            "Bar label — use a ticker symbol ('AAPL') or a time period "
            "('Mon', 'Jan', 'Q1')"
        ),
    )
    value: float = Field(..., description="Price or numeric value for this bar")


class StockChart(BaseModel):
    title: str
    symbol: str
    bars: list[StockBar]
    currency: str = "USD"


async def render_stock_chart(
    title: str,
    symbol: str,
    bars: list[StockBar],
    currency: str = "USD",
) -> str:
    """Render a stock price bar chart in the chat.

    Call this tool to display price data, trends, or comparisons visually.
    Do NOT use Markdown tables for financial figures — always call this tool.

    Example — weekly AAPL prices:
      render_stock_chart(
          title="AAPL — This Week",
          symbol="AAPL",
          bars=[
              {"label": "Mon", "value": 189.50},
              {"label": "Tue", "value": 191.20},
              {"label": "Wed", "value": 188.80},
              {"label": "Thu", "value": 190.10},
              {"label": "Fri", "value": 192.30},
          ]
      )

    Returns:
        JSON spec consumed by the frontend to render the chart widget.
    """
    chart = StockChart(title=title, symbol=symbol, bars=bars, currency=currency)
    return chart.model_dump_json()


# ---------------------------------------------------------------------------
# Bar chart from sandbox script
# ---------------------------------------------------------------------------


class BarItem(BaseModel):
    """A single bar in a generic bar chart."""

    label: str = Field(..., description="X-axis label for this bar")
    value: float = Field(..., description="Numeric value for this bar")


class BarChart(BaseModel):
    title: str
    bars: list[BarItem]
    x_label: str = ""
    y_label: str = ""


async def render_bar_chart_from_script(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    title: str,
    script: str,
    x_label: str = "",
    y_label: str = "",
    environment_name: str = "pandas-only",
) -> pydantic_ai.ToolReturn:
    """Render a bar chart by running a Python script in the sandbox.

    The script MUST print a JSON array to stdout:
        [{"label": "<x-axis label>", "value": <number>}, ...]

    Uploaded files are available inside the sandbox at:
        /sandbox/volumes/room/   — room-level uploads (shared)
        /sandbox/volumes/thread/ — thread-level uploads (user's files)

    Use environment_name='pandas-only' for CSV/DataFrame work.

    Example — TKV by customer from uploaded CSVs:
      render_bar_chart_from_script(
          title="Tiered Kinetic Value by Customer",
          x_label="Customer",
          y_label="TKV ($)",
          environment_name="pandas-only",
          script=\"\"\"
    import pandas as pd, json
    customers = pd.read_csv('/sandbox/volumes/thread/customers.csv')
    products  = pd.read_csv('/sandbox/volumes/thread/products.csv')
    txns      = pd.read_csv('/sandbox/volumes/thread/transactions.csv')
    df = txns.merge(products, on='product_id').merge(customers, on='customer_id')
    df['unit_profit'] = df['retail_price'] - df['wholesale_cost']
    TIER = {'Bronze': 1.1, 'Silver': 2.5, 'Gold': 3.0, 'Platinum': 5.5}
    df['tkv'] = df['unit_profit'] * df['quantity'] * df['loyalty_tier'].map(TIER)
    result = df.groupby('name')['tkv'].sum().reset_index()
    print(json.dumps([{'label': r['name'], 'value': round(r['tkv'], 2)}
                      for _, r in result.iterrows()]))
    \"\"\"
      )

    Returns:
        Validated JSON spec consumed by the frontend BarChartWidget, or an
        error string the model can use to fix the script and retry.
    """
    i_config = ctx.deps.the_installation

    if i_config is None or i_config.sandbox_config is None:
        return pydantic_ai.ToolReturn(
            return_value="Error: sandbox not configured for this installation."
        )

    sc = i_config.sandbox_config
    sandbox_cfg = bs_config.Config()
    sandbox_cfg.environments_pathname = sc.environments_path

    workdir = get_workdir(
        sc.workdirs_path,
        ctx.deps.room_id or "",
        ctx.deps.thread_id or "",
        ctx.deps.run_id or "",
    )
    extra_volumes = get_extra_volumes(
        i_config.rooms_upload_path,
        i_config.threads_upload_path,
        ctx.deps.room_id or "",
        ctx.deps.thread_id or "",
    )

    sandbox = bs_sandbox.BwrapSandbox(
        default_environment_name=environment_name,
        config=sandbox_cfg,
    )

    raw = await skill_execute_script(
        bwrap_sandbox=sandbox,
        script=script,
        environment_name=environment_name,
        workdir=workdir,
        extra_volumes=extra_volumes,
    )

    # skill_execute_script returns error strings on failure — pass them back
    # so pydantic-ai retries and the model can fix the script.
    if raw.startswith("Error:") or raw.startswith("Command failed"):
        return pydantic_ai.ToolReturn(return_value=raw)

    try:
        bars_data = _json_std.loads(raw)
        bars = [BarItem(**b) for b in bars_data]
    except Exception as exc:
        return pydantic_ai.ToolReturn(
            return_value=(
                "Error: script output is not valid bar JSON.\n"
                "Expected: [{\"label\": \"...\", \"value\": 0.0}, ...]\n"
                f"Got: {raw[:300]}\n"
                f"Parse error: {exc}"
            )
        )

    chart = BarChart(title=title, bars=bars, x_label=x_label, y_label=y_label)
    spec = chart.model_dump()

    state_delta = _build_state_delta(
        current=ctx.deps.state,
        widget=render_bar_chart_from_script.__name__,
        spec=spec,
    )

    return pydantic_ai.ToolReturn(
        return_value=chart.model_dump_json(),
        metadata=[state_delta],
    )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _build_state_delta(
    *,
    current: dict,
    widget: str,
    spec: dict,
) -> agui_core.StateDeltaEvent:
    """Return a StateDeltaEvent that sets state[GENUI_STATE_KEY] to the spec."""
    new_state = {**current, GENUI_STATE_KEY: {"widget": widget, "spec": spec}}
    patch = jsonpatch.make_patch(current, new_state)
    return agui_core.StateDeltaEvent(delta=list(patch))
