from unittest import mock

import fastapi
import pytest

from soliplex import agui
from soliplex import installation
from soliplex import models
from soliplex.views import agui as agui_views

USER_NAME = "phreddy"
GIVEN_NAME = "Phred"
FAMILY_NAME = "Phlyntstone"
EMAIL = "phreddy@example.com"

AUTH_USER = {
    "preferred_username": USER_NAME,
    "given_name": GIVEN_NAME,
    "family_name": FAMILY_NAME,
    "email": EMAIL,
}

UNKNOWN_USER = {
    "preferred_username": "<unknown>",
    "given_name": "<unknown>",
    "family_name": "<unknown>",
    "email": "<unknown>",
}


@pytest.mark.anyio
@pytest.mark.parametrize("w_error", [False, True])
@pytest.mark.parametrize("w_thread", [False, True])
@pytest.mark.parametrize(
    "w_auth_user, exp_user",
    [
        ({}, UNKNOWN_USER),
        (AUTH_USER, AUTH_USER),
    ],
)
@mock.patch("fastapi.responses.StreamingResponse")
@mock.patch("pydantic_ai.ui.ag_ui.AGUIAdapter")
@mock.patch("soliplex.agui.EventStreamParser")
@mock.patch("soliplex.auth.authenticate")
async def test_post_room_agui(
    auth_fn,
    esp,
    aga,
    sr,
    w_error,
    w_thread,
    w_auth_user,
    exp_user,
):
    auth_fn.return_value = w_auth_user
    aga.dispatch_request = mock.AsyncMock()

    ROOM_ID = "test-room"
    AGENT = object()

    request = fastapi.Request(scope={"type": "http"})

    the_installation = mock.create_autospec(installation.Installation)

    if w_error:
        the_installation.get_agent_for_room.side_effect = KeyError("testing")
    else:
        the_installation.get_agent_for_room.return_value = AGENT

    aga.from_request = mock.AsyncMock()
    exp_adapter = aga.from_request.return_value
    exp_adapter.encode_stream = mock.MagicMock()
    exp_adapter.run_stream = mock.MagicMock()

    token = object()

    exp_user_profile = models.UserProfile(**exp_user)

    the_threads = mock.create_autospec(agui.Threads)

    if w_thread:
        exp_thread = the_threads.get_thread.return_value
    else:
        the_threads.get_thread.side_effect = [
            agui.UnknownThread(user_name="user-name", thread_id="thread-id"),
        ]
        exp_new_thread = the_threads.new_thread = mock.AsyncMock()
        exp_thread = exp_new_thread.return_value

    exp_new_run = exp_thread.new_run = mock.AsyncMock()

    exp_run = exp_new_run.return_value

    exp_deps = models.AgentDependencies(
        the_installation=the_installation,
        user=exp_user_profile,
    )

    exp_agent_stream = exp_adapter.run_stream.return_value

    exp_esp = esp.return_value

    exp_esp_stream = exp_esp.parse_stream.return_value

    exp_sse_stream = exp_adapter.encode_stream.return_value

    if w_error:
        with pytest.raises(fastapi.HTTPException) as exc:
            await agui_views.post_room_agui(
                request,
                room_id=ROOM_ID,
                the_installation=the_installation,
                the_threads=the_threads,
                token=token,
            )

        assert exc.value.status_code == 404

    else:
        found = await agui_views.post_room_agui(
            request,
            room_id=ROOM_ID,
            the_installation=the_installation,
            the_threads=the_threads,
            token=token,
        )

        assert found is sr.return_value

        sr.assert_called_once_with(
            exp_sse_stream,
            media_type=exp_adapter.accept,
        )

        exp_adapter.encode_stream.assert_called_once_with(exp_esp_stream)

        exp_esp.parse_stream.assert_called_once_with(exp_agent_stream)

        esp.assert_called_once_with(exp_adapter.run_input, run=exp_run)

        exp_adapter.run_stream.assert_called_once_with(deps=exp_deps)

        exp_new_run.assert_called_once_with(exp_adapter.run_input)

        if w_thread:
            the_threads.new_thread.assert_not_called()
        else:
            the_threads.new_thread.assert_called_once_with(
                user_name=exp_user_profile.preferred_username,
                room_id=ROOM_ID,
                thread_id=exp_adapter.run_input.thread_id,
            )

        aga.from_request.assert_called_once_with(
            request=request,
            agent=AGENT,
        )

    the_installation.get_agent_for_room.assert_called_once_with(
        ROOM_ID,
        user=auth_fn.return_value,
    )
    auth_fn.assert_called_once_with(the_installation, token)
