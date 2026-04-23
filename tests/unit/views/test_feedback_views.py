import datetime
from unittest import mock

import pytest

from soliplex.views import feedback as feedback_views

THE_USER_CLAIMS = {"sub": "user-123", "email": "user@example.com"}

PAYLOAD = feedback_views.FeedbackPayload(
    room_id="demo",
    thread_id="thread-1",
    form_title="App Feedback",
    data={"rating": "5", "comment": "Great app!"},
)


@pytest.mark.anyio
@mock.patch("soliplex.views.feedback.logfire")
async def test_submit_feedback_success(mock_logfire):
    result = await feedback_views.submit_feedback(
        payload=PAYLOAD,
        the_user_claims=THE_USER_CLAIMS,
    )

    assert isinstance(result, feedback_views.FeedbackResponse)
    assert isinstance(result.received_at, datetime.datetime)
    assert result.received_at.tzinfo == datetime.UTC

    mock_logfire.info.assert_called_once_with(
        "feedback received",
        room_id="demo",
        thread_id="thread-1",
        form_title="App Feedback",
        data={"rating": "5", "comment": "Great app!"},
        user=THE_USER_CLAIMS.get("sub"),
    )


@pytest.mark.anyio
@mock.patch("soliplex.views.feedback.logfire")
async def test_submit_feedback_empty_data(mock_logfire):
    payload = feedback_views.FeedbackPayload(
        room_id="r",
        thread_id="t",
        form_title="Empty",
        data={},
    )

    result = await feedback_views.submit_feedback(
        payload=payload,
        the_user_claims=THE_USER_CLAIMS,
    )

    assert isinstance(result.received_at, datetime.datetime)
    mock_logfire.info.assert_called_once()


@pytest.mark.anyio
@mock.patch("soliplex.views.feedback.logfire")
async def test_submit_feedback_nested_data(mock_logfire):
    payload = feedback_views.FeedbackPayload(
        room_id="r",
        thread_id="t",
        form_title="Nested",
        data={"topics": ["UI", "Performance"], "score": 4},
    )

    result = await feedback_views.submit_feedback(
        payload=payload,
        the_user_claims=THE_USER_CLAIMS,
    )

    assert isinstance(result.received_at, datetime.datetime)
    _, kwargs = mock_logfire.info.call_args
    assert kwargs["data"]["topics"] == ["UI", "Performance"]
