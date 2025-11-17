from unittest import mock

import fastapi
import pytest

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
@pytest.mark.parametrize(
    "w_auth_user, exp_user",
    [
        ({}, UNKNOWN_USER),
        (AUTH_USER, AUTH_USER),
    ],
)
@mock.patch("pydantic_ai.ui.ag_ui.AGUIAdapter")
@mock.patch("soliplex.auth.authenticate")
async def test_post_room_agui(auth_fn, aga, w_error, w_auth_user, exp_user):
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

    token = object()

    if w_error:
        with pytest.raises(fastapi.HTTPException) as exc:
            await agui_views.post_room_agui(
                request,
                room_id=ROOM_ID,
                the_installation=the_installation,
                token=token,
            )

        assert exc.value.status_code == 404

    else:
        found = await agui_views.post_room_agui(
            request,
            room_id=ROOM_ID,
            the_installation=the_installation,
            token=token,
        )

        exp_user_profile = models.UserProfile(**exp_user)

        expected_deps = models.AgentDependencies(
            the_installation=the_installation,
            user=exp_user_profile,
        )

        assert found is aga.dispatch_request.return_value

        aga.dispatch_request.assert_called_once_with(
            agent=AGENT,
            request=request,
            deps=expected_deps,
        )

    the_installation.get_agent_for_room.assert_called_once_with(
        ROOM_ID,
        user=auth_fn.return_value,
    )
    auth_fn.assert_called_once_with(the_installation, token)
