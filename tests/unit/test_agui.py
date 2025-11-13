import contextlib
import dataclasses
import datetime
import uuid
from unittest import mock

import fastapi
import pytest
from ag_ui import core as agui_core
from pydantic_ai import messages as ai_messages

from soliplex import agui

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

TEST_THREAD_UUID = uuid.uuid4()
TEST_THREAD_NAME = "Test Thread"
TEST_THREAD_ROOMID = "test-room"
TEST_THREAD = agui.Thread(
    thread_uuid=TEST_THREAD_UUID,
    name=TEST_THREAD_NAME,
    room_id=TEST_THREAD_ROOMID,
)
TEST_THREADS = {
    TEST_THREAD_UUID: TEST_THREAD,
}

TEST_RUN_UUID = uuid.uuid4()

timestamp = datetime.datetime.now(datetime.UTC)
system_prompt_part = ai_messages.SystemPromptPart(
    content=SYSTEM_PROMPT,
    timestamp=timestamp,
)
user_prompt_part = ai_messages.UserPromptPart(
    content=USER_PROMPT,
    timestamp=timestamp,
)
tool_return_part = ai_messages.ToolReturnPart(
    content=TOOL_RETURN,
    tool_call_id=TOOL_CALL_ID,
    tool_name=TOOL_NAME,
)
retry_prompt_part = ai_messages.RetryPromptPart(
    RETRY_PROMPT,
    timestamp=timestamp,
)

PROVIDER_RESPONSE_ID = "provider-test"
text_part = ai_messages.TextPart(
    content=TEXT,
)
thinking_part = ai_messages.ThinkingPart(content=THINKING)
tool_call_part = ai_messages.ToolCallPart(tool_name=TOOL_NAME)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expected",
    [
        ({}, {}),
        ({"testing": TEST_THREADS}, TEST_THREADS),
    ],
)
async def test_threads_user_threads(w_threads, expected):
    the_threads = agui.Threads()
    the_threads._threads.update(w_threads)

    found = await the_threads.user_threads("testing")

    assert found == expected


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expectation",
    [
        ({}, pytest.raises(agui.UnknownThread)),
        ({"testing": {}}, pytest.raises(agui.UnknownThread)),
        (
            {"testing": TEST_THREADS},
            contextlib.nullcontext(TEST_THREAD),
        ),
    ],
)
async def test_threads_get_thread(w_threads, expectation):
    the_threads = agui.Threads()
    the_threads._threads.update(w_threads)

    with expectation as expected:
        found = await the_threads.get_thread("testing", TEST_THREAD_UUID)

    if expected is TEST_THREAD:
        assert found is TEST_THREAD


@pytest.mark.anyio
@pytest.mark.parametrize("w_existing", [False, True])
@pytest.mark.parametrize("w_user", [False, True])
async def test_threads_new_thread(w_user, w_existing):
    the_threads = agui.Threads()

    kw = {}
    if w_user:
        kw["testing"] = {}

    with (
        mock.patch.dict(the_threads._threads, **kw),
    ):
        found = await the_threads.new_thread(
            "testing",
            TEST_THREAD_ROOMID,
            TEST_THREAD_NAME,
        )

    assert isinstance(found.thread_uuid, uuid.UUID)
    assert found.name == TEST_THREAD_NAME
    assert found.room_id == TEST_THREAD_ROOMID


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expectation",
    [
        ({}, pytest.raises(agui.UnknownThread)),
        ({"testing": {}}, pytest.raises(agui.UnknownThread)),
        ({"testing": TEST_THREADS}, contextlib.nullcontext(None)),
    ],
)
async def test_threads_delete_thread(w_threads, expectation):
    the_threads = agui.Threads()

    for user_name, thread_map in list(w_threads.items()):
        new_map = {}

        for thread_uuid, thread in list(thread_map.items()):
            new_map[thread_uuid] = dataclasses.replace(thread)

        the_threads._threads[user_name] = new_map

    with expectation as expected:
        await the_threads.delete_thread("testing", TEST_THREAD_UUID)

    if expected is None:
        assert the_threads._threads["testing"] == {}


@pytest.mark.anyio
async def test_get_the_threads():
    expected = object()
    request = fastapi.Request(scope={"type": "http"})
    request.state.the_threads = expected

    found = await agui.get_the_threads(request)

    assert found is expected


@pytest.mark.parametrize(
    "parts, expect_none",
    [
        ([system_prompt_part], True),
        ([user_prompt_part], False),
        ([tool_return_part], True),
        ([retry_prompt_part], True),
        ([system_prompt_part, tool_return_part], True),
        ([system_prompt_part, retry_prompt_part], True),
        ([tool_return_part, retry_prompt_part], True),
        ([system_prompt_part, tool_return_part, retry_prompt_part], True),
        ([system_prompt_part, user_prompt_part], False),
        ([tool_return_part, user_prompt_part], False),
        ([retry_prompt_part, user_prompt_part], False),
    ],
)
def test__to_agui_message_w_request(parts, expect_none):
    msg = ai_messages.ModelRequest(parts=parts)

    found = agui._to_agui_message(msg, TEST_RUN_UUID)

    if expect_none:
        assert found is None
    else:
        assert isinstance(found, agui_core.UserMessage)
        assert found.id == str(TEST_RUN_UUID)
        assert found.content == USER_PROMPT


@pytest.mark.parametrize(
    "parts, expect_none",
    [
        ([text_part], False),
        ([thinking_part, text_part], False),
        ([tool_call_part, text_part], False),
        ([thinking_part, tool_call_part, text_part], False),
        ([thinking_part], True),
        ([tool_call_part], True),
        ([thinking_part, tool_call_part], True),
    ],
)
def test__to_agui_message_w_response(parts, expect_none):
    msg = ai_messages.ModelResponse(
        parts=parts,
        provider_response_id=PROVIDER_RESPONSE_ID,
    )

    found = agui._to_agui_message(msg, TEST_RUN_UUID)

    if expect_none:
        assert found is None
    else:
        assert isinstance(found, agui_core.SystemMessage)
        assert found.content == TEXT
        assert found.id == PROVIDER_RESPONSE_ID
