"""Feedback ingest endpoint: receives form submissions from Flutter clients."""

from __future__ import annotations

import datetime

import fastapi
import logfire
import pydantic

from soliplex import authn
from soliplex import views

router = fastapi.APIRouter(tags=["telemetry"])

depend_the_user_claims = views.depend_the_user_claims


class FeedbackPayload(pydantic.BaseModel):
    """Free-form form submission from a genui render_form widget."""

    room_id: str
    thread_id: str
    form_title: str
    data: dict[str, object]


class FeedbackResponse(pydantic.BaseModel):
    received_at: datetime.datetime


@router.post("/v1/feedback", status_code=200)
async def submit_feedback(
    payload: FeedbackPayload,
    the_user_claims: authn.UserClaims = depend_the_user_claims,
) -> FeedbackResponse:
    """Accept a form submission and log it for observability.

    No persistent storage — submissions are emitted to Logfire so they
    appear in the observability dashboard alongside other telemetry.
    """
    logfire.info(
        "feedback received",
        room_id=payload.room_id,
        thread_id=payload.thread_id,
        form_title=payload.form_title,
        data=payload.data,
        user=the_user_claims.get("sub"),
    )
    return FeedbackResponse(
        received_at=datetime.datetime.now(datetime.UTC),
    )
