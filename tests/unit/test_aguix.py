import contextlib
import dataclasses
import datetime
import uuid
from unittest import mock

import fastapi
import pytest
from ag_ui import core as agui_core

from soliplex import aguix

SYSTEM_PROMPT = "You are a testcase"
USER_PROMPT = "Which way is up?"
TOOL_RETURN = "Nailed it"
TOOL_CALL_ID = 1234
RETRY_PROMPT = "Please try again"
TEXT = "The opposite way from down"
THINKING = "Hold on a minute, I'm thinking"
TOOL_NAME = "hammer"

NOW = datetime.datetime(2025, 8, 11, 16, 59, 47, tzinfo=datetime.UTC)
TS_1 = NOW - datetime.timedelta(minutes=11)
TS_2 = NOW - datetime.timedelta(minutes=10)
TS_3 = NOW - datetime.timedelta(minutes=9)
TS_4 = NOW - datetime.timedelta(minutes=8)

ROOM_ID = "testing"
SYSTEM_PROMPT = "You are a test."
USER_PROMPT = "This is a test."
MODEL_RESPONSE = "Now you're talking!"
ANOTHER_USER_PROMPT = "Which way is up?"
ANOTHER_MODEL_RESPONSE = "The other way from down"

OLD_AGUI_MESSAGES = [
    agui_core.UserMessage(
        id="1",
        content=SYSTEM_PROMPT,
    ),
    agui_core.SystemMessage(
        id="2",
        content=MODEL_RESPONSE,
    ),
]
NEW_AGUI_MESSAGES = [
    agui_core.UserMessage(
        id="3",
        content=ANOTHER_USER_PROMPT,
    ),
    agui_core.SystemMessage(
        id="4",
        content=ANOTHER_MODEL_RESPONSE,
    ),
]

TEST_INTERACTION_UUID = uuid.uuid4()
TEST_INTERACTION_NAME = "Test Interaction"
TEST_INTERACTION_ROOMID = "test-room"
TEST_INTERACTION = aguix.Interaction(
    aguix_uuid=TEST_INTERACTION_UUID,
    name=TEST_INTERACTION_NAME,
    room_id=TEST_INTERACTION_ROOMID,
    message_history=OLD_AGUI_MESSAGES,
)
TEST_INTERACTIONS = {
    TEST_INTERACTION_UUID: TEST_INTERACTION,
}


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_interactions, expected",
    [
        ({}, {}),
        ({"testing": TEST_INTERACTIONS}, TEST_INTERACTIONS),
    ],
)
async def test_interactions_user_interactions(w_interactions, expected):
    the_interactions = aguix.Interactions()
    the_interactions._interactions.update(w_interactions)

    found = await the_interactions.user_interactions("testing")

    assert found == expected


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_interactions, expectation",
    [
        ({}, pytest.raises(aguix.UnknownInteraction)),
        ({"testing": {}}, pytest.raises(aguix.UnknownInteraction)),
        (
            {"testing": TEST_INTERACTIONS},
            contextlib.nullcontext(TEST_INTERACTION),
        ),
    ],
)
async def test_interactions_get_interaction(w_interactions, expectation):
    the_interactions = aguix.Interactions()
    the_interactions._interactions.update(w_interactions)

    with expectation as expected:
        found = await the_interactions.get_interaction(
            "testing", TEST_INTERACTION_UUID
        )

    if expected is TEST_INTERACTION:
        assert found is TEST_INTERACTION


@pytest.mark.anyio
@pytest.mark.parametrize("w_existing", [False, True])
@pytest.mark.parametrize("w_user", [False, True])
async def test_interactions_new_interaction(w_user, w_existing):
    the_interactions = aguix.Interactions()

    kw = {}
    if w_user:
        kw["testing"] = {}

    with (
        mock.patch.dict(the_interactions._interactions, **kw),
    ):
        found = await the_interactions.new_interaction(
            "testing",
            TEST_INTERACTION_ROOMID,
            TEST_INTERACTION_NAME,
            OLD_AGUI_MESSAGES,
        )

    assert isinstance(found.aguix_uuid, uuid.UUID)
    assert found.name == TEST_INTERACTION_NAME
    assert found.room_id == TEST_INTERACTION_ROOMID

    for f_msg, e_msg in zip(
        found.message_history,
        OLD_AGUI_MESSAGES,
        strict=True,
    ):
        assert f_msg == e_msg


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_interactions, expectation",
    [
        ({}, pytest.raises(aguix.UnknownInteraction)),
        ({"testing": {}}, pytest.raises(aguix.UnknownInteraction)),
        ({"testing": TEST_INTERACTIONS}, contextlib.nullcontext(None)),
    ],
)
async def test_interactions_append_to_interaction(w_interactions, expectation):
    the_interactions = aguix.Interactions()

    for user_name, interaction_map in list(w_interactions.items()):
        new_map = {}

        for aguix_uuid, interaction in list(interaction_map.items()):
            new_map[aguix_uuid] = dataclasses.replace(
                interaction,
                message_history=tuple(OLD_AGUI_MESSAGES[:]),
            )

        the_interactions._interactions[user_name] = new_map

    with expectation as expected:
        await the_interactions.append_to_interaction(
            "testing",
            TEST_INTERACTION_UUID,
            NEW_AGUI_MESSAGES,
        )

    if expected is None:
        assert new_map[TEST_INTERACTION_UUID].message_history == tuple(
            OLD_AGUI_MESSAGES + NEW_AGUI_MESSAGES
        )


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_interactions, expectation",
    [
        ({}, pytest.raises(aguix.UnknownInteraction)),
        ({"testing": {}}, pytest.raises(aguix.UnknownInteraction)),
        ({"testing": TEST_INTERACTIONS}, contextlib.nullcontext(None)),
    ],
)
async def test_interactions_delete_interaction(w_interactions, expectation):
    the_interactions = aguix.Interactions()

    for user_name, interaction_map in list(w_interactions.items()):
        new_map = {}

        for aguix_uuid, interaction in list(interaction_map.items()):
            new_map[aguix_uuid] = dataclasses.replace(interaction)

        the_interactions._interactions[user_name] = new_map

    with expectation as expected:
        await the_interactions.delete_interaction(
            "testing", TEST_INTERACTION_UUID
        )

    if expected is None:
        assert the_interactions._interactions["testing"] == {}


@pytest.mark.anyio
async def test_get_the_interactions():
    expected = object()
    request = fastapi.Request(scope={"type": "http"})
    request.state.the_interactions = expected

    found = await aguix.get_the_interactions(request)

    assert found is expected
