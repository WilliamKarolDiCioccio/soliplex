import datetime
from unittest import mock

import fastapi
import pytest

from soliplex import agui as agui_package
from soliplex import authz as authz_package
from soliplex import installation
from soliplex import loggers
from soliplex.views import stats as stats_views

NOW = datetime.datetime.now(datetime.UTC)

ROOM_ID = "test-room"
USER_NAME = "phreddy"

THE_USER_CLAIMS = {"preferred_username": USER_NAME}
UNKNOWN_USER_CLAIMS = {}


@pytest.fixture
def the_threads():
    return mock.create_autospec(agui_package.ThreadStorage)


@pytest.mark.anyio
@pytest.mark.parametrize("last_message_at", [NOW, None])
async def test_get_room_stats(the_threads, last_message_at):
    request = mock.create_autospec(fastapi.Request)
    the_installation = mock.create_autospec(installation.Installation)
    the_authz_policy = mock.create_autospec(authz_package.AuthorizationPolicy)
    the_logger = mock.create_autospec(loggers.LogWrapper)

    the_threads.get_room_last_activity.return_value = last_message_at

    found = await stats_views.get_room_stats(
        request,
        room_id=ROOM_ID,
        the_installation=the_installation,
        the_threads=the_threads,
        the_authz_policy=the_authz_policy,
        the_user_claims=THE_USER_CLAIMS,
        the_logger=the_logger,
    )

    assert found.room_id == ROOM_ID
    assert found.last_message_at == last_message_at

    the_installation.get_room_config.assert_awaited_once_with(
        room_id=ROOM_ID,
        user=THE_USER_CLAIMS,
        the_authz_policy=the_authz_policy,
        the_logger=the_logger,
    )
    the_threads.get_room_last_activity.assert_awaited_once_with(
        user_name=USER_NAME,
        room_id=ROOM_ID,
    )


@pytest.mark.anyio
async def test_get_room_stats_unknown_user(the_threads):
    request = mock.create_autospec(fastapi.Request)
    the_installation = mock.create_autospec(installation.Installation)
    the_authz_policy = mock.create_autospec(authz_package.AuthorizationPolicy)
    the_logger = mock.create_autospec(loggers.LogWrapper)

    the_threads.get_room_last_activity.return_value = None

    await stats_views.get_room_stats(
        request,
        room_id=ROOM_ID,
        the_installation=the_installation,
        the_threads=the_threads,
        the_authz_policy=the_authz_policy,
        the_user_claims=UNKNOWN_USER_CLAIMS,
        the_logger=the_logger,
    )

    the_threads.get_room_last_activity.assert_awaited_once_with(
        user_name="<unknown>",
        room_id=ROOM_ID,
    )


@pytest.mark.anyio
async def test_get_room_stats_unknown_room(the_threads):
    request = mock.create_autospec(fastapi.Request)
    the_installation = mock.create_autospec(installation.Installation)
    the_authz_policy = mock.create_autospec(authz_package.AuthorizationPolicy)
    the_logger = mock.create_autospec(loggers.LogWrapper)

    the_installation.get_room_config.side_effect = KeyError("testing")

    with pytest.raises(fastapi.HTTPException) as exc_info:
        await stats_views.get_room_stats(
            request,
            room_id=ROOM_ID,
            the_installation=the_installation,
            the_threads=the_threads,
            the_authz_policy=the_authz_policy,
            the_user_claims=THE_USER_CLAIMS,
            the_logger=the_logger,
        )

    assert exc_info.value.status_code == 404
    the_threads.get_room_last_activity.assert_not_called()
