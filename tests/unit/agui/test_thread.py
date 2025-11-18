import contextlib
import dataclasses
import uuid
from unittest import mock

import fastapi
import pytest
from ag_ui import core as agui_core

from soliplex.agui import thread as agui_thread

UUID4 = uuid.uuid4()
TEST_THREAD_ID = str(UUID4)
OTHER_THREAD_ID = "thread-123"
TEST_RUN_ID = "run-345"
TEST_THREAD_ROOMID = "test-room"
TEST_THREAD = agui_thread.Thread(
    thread_id=TEST_THREAD_ID,
    room_id=TEST_THREAD_ROOMID,
)
TEST_THREADS = {
    TEST_THREAD_ID: TEST_THREAD,
}


@pytest.fixture
def run_input():
    return agui_core.RunAgentInput(
        thread_id=TEST_THREAD_ID,
        run_id=TEST_RUN_ID,
        state={},
        messages=[],
        tools=[],
        context=[],
        forwarded_props=None,
    )


@mock.patch("uuid.uuid4")
def test__make_thread_id(uu4):
    uu4.return_value = UUID4

    assert agui_thread._make_thread_id() == str(UUID4)


@pytest.mark.anyio
async def test_thread_new_run_w_mismatched_thread_id(run_input):
    thread = dataclasses.replace(TEST_THREAD, thread_id=OTHER_THREAD_ID)

    with pytest.raises(agui_thread.WrongThreadId):
        await thread.new_run(run_input)


@pytest.mark.anyio
async def test_thread_new_run_w_duplicate_run_id(run_input):
    thread = dataclasses.replace(TEST_THREAD, runs={TEST_RUN_ID: object()})

    with pytest.raises(agui_thread.DuplicateRunId):
        await thread.new_run(run_input)


@pytest.mark.anyio
async def test_thread_new_run_w_missing_parent_run_id(run_input):
    run_input.parent_run_id = "BOGUS"
    thread = dataclasses.replace(TEST_THREAD, runs={})

    with pytest.raises(agui_thread.MissingParentRunId):
        await thread.new_run(run_input)


@pytest.mark.anyio
async def test_thread_new_run(run_input):
    thread = dataclasses.replace(TEST_THREAD, runs={})

    run = await thread.new_run(run_input)

    assert run.run_input is run_input
    assert run.events == []
    assert thread.runs[TEST_RUN_ID] == run


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expected",
    [
        ({}, {}),
        ({"testing": TEST_THREADS}, TEST_THREADS),
    ],
)
async def test_threads_user_threads(w_threads, expected):
    the_threads = agui_thread.Threads()
    the_threads._threads.update(w_threads)

    found = await the_threads.user_threads(user_name="testing")

    assert found == expected


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expectation",
    [
        ({}, pytest.raises(agui_thread.UnknownThread)),
        ({"testing": {}}, pytest.raises(agui_thread.UnknownThread)),
        (
            {"testing": TEST_THREADS},
            contextlib.nullcontext(TEST_THREAD),
        ),
    ],
)
async def test_threads_get_thread(w_threads, expectation):
    the_threads = agui_thread.Threads()
    the_threads._threads.update(w_threads)

    with expectation as expected:
        found = await the_threads.get_thread(
            user_name="testing",
            thread_id=TEST_THREAD_ID,
        )

    if expected is TEST_THREAD:
        assert found is TEST_THREAD


@pytest.mark.anyio
@pytest.mark.parametrize("w_thread_id", [False, True])
@pytest.mark.parametrize("w_user", [False, True])
@mock.patch("uuid.uuid4")
async def test_threads_new_thread(uu4, w_user, w_thread_id):
    uu4.return_value = UUID4
    the_threads = agui_thread.Threads()

    user_threads_patch = {}
    if w_user:
        before = user_threads_patch["testing"] = {"already": object()}

    kwargs = {}

    if w_thread_id:
        exp_thread_id = kwargs["thread_id"] = OTHER_THREAD_ID
    else:
        exp_thread_id = TEST_THREAD_ID

    with (
        mock.patch.dict(the_threads._threads, **user_threads_patch),
    ):
        found = await the_threads.new_thread(
            user_name="testing",
            room_id=TEST_THREAD_ROOMID,
            **kwargs,
        )
        if w_user:
            assert the_threads._threads["testing"] is before

        assert the_threads._threads["testing"][exp_thread_id] is found

    assert found.thread_id == exp_thread_id
    assert found.room_id == TEST_THREAD_ROOMID


@pytest.mark.anyio
@pytest.mark.parametrize(
    "w_threads, expectation",
    [
        ({}, pytest.raises(agui_thread.UnknownThread)),
        ({"testing": {}}, pytest.raises(agui_thread.UnknownThread)),
        ({"testing": TEST_THREADS}, contextlib.nullcontext(None)),
    ],
)
async def test_threads_delete_thread(w_threads, expectation):
    the_threads = agui_thread.Threads()

    for user_name, thread_map in list(w_threads.items()):
        new_map = {}

        for thread_id, thread in list(thread_map.items()):
            new_map[thread_id] = dataclasses.replace(thread)

        the_threads._threads[user_name] = new_map

    with expectation as expected:
        await the_threads.delete_thread(
            user_name="testing",
            thread_id=TEST_THREAD_ID,
        )

    if expected is None:
        assert the_threads._threads["testing"] == {}


@pytest.mark.anyio
async def test_get_the_threads():
    expected = object()
    request = fastapi.Request(scope={"type": "http"})
    request.state.the_threads = expected

    found = await agui_thread.get_the_threads(request)

    assert found is expected
