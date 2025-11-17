import contextlib
import dataclasses
import datetime
import uuid
from unittest import mock

import fastapi
import jsonpatch
import pytest
from ag_ui import core as agui_core

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

UUID4 = uuid.uuid4()
TEST_THREAD_ID = str(UUID4)
OTHER_THREAD_ID = "thread-123"
TEST_RUN_ID = "run-345"
TEST_THREAD_ROOMID = "test-room"
TEST_THREAD = agui.Thread(
    thread_id=TEST_THREAD_ID,
    room_id=TEST_THREAD_ROOMID,
)
TEST_THREADS = {
    TEST_THREAD_ID: TEST_THREAD,
}

TEST_RUN_UUID = str(uuid.uuid4())

TEST_RUN_STARTED = agui_core.RunStartedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
)

TEST_RUN_FINISHED = agui_core.RunFinishedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
)

EMPTY_AGUI_RUN_INPUT = agui_core.RunAgentInput(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    state={},
    messages=[],
    tools=[],
    context=[],
    forwarded_props=None,
)

W_STATE_AGUI_RUN_INPUT = agui_core.RunAgentInput(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    state={"foo": "bar"},
    messages=[],
    tools=[],
    context=[],
    forwarded_props=None,
)

SYSTEM_PROMPT_MESSAGE_ID = "system-prompt"
SYSTEM_PROMPT_TEXT = "You are a test"
SYSTEM_PROMPT_MESSAGE = agui_core.SystemMessage(
    id=SYSTEM_PROMPT_MESSAGE_ID,
    content=SYSTEM_PROMPT_TEXT,
)

USER_PROMPT_MESSAGE_ID = "user-prompt"
USER_PROMPT_TEXT = "Which way is up?"
USER_PROMPT_MESSAGE = agui_core.UserMessage(
    id=USER_PROMPT_MESSAGE_ID,
    content=USER_PROMPT_TEXT,
)

TEXT_REPLY_MESSAGE_ID = "answer"
TEXT_REPLY_TEXT = "Opposite from down"
TEXT_REPLY_MESSAGE = agui_core.AssistantMessage(
    id=TEXT_REPLY_MESSAGE_ID,
    content=TEXT_REPLY_TEXT,
)

ACTIVITY_MESSAGE_ID = "activity-1"
ACTIVITY_TYPE = "test-one"
ACTIVITY_STATE = {"foo": "foo"}
ACTIVITY_MESSAGE = agui_core.ActivityMessage(
    id=ACTIVITY_MESSAGE_ID,
    activity_type=ACTIVITY_TYPE,
    content=ACTIVITY_STATE,
)

OTHER_ACTIVITY_MESSAGE_ID = "activity-2"
OTHER_ACTIVITY_TYPE = "test-two"
OTHER_ACTIVITY_STATE = {"qux": "spam"}
OTHER_ACTIVITY_MESSAGE = agui_core.ActivityMessage(
    id=OTHER_ACTIVITY_MESSAGE_ID,
    activity_type=OTHER_ACTIVITY_TYPE,
    content=OTHER_ACTIVITY_STATE,
)

TOOL_CALL_ID = "tc-456"
TOOL_CALL_FUNCTION = "test-tool"
TOOL_CALL_ARGS = "foo=1"

TOOL_CALL = agui_core.ToolCall(
    id=TOOL_CALL_ID,
    function=agui_core.FunctionCall(
        name=TOOL_CALL_FUNCTION,
        arguments=TOOL_CALL_ARGS,
    ),
)

TOOL_CALL_RESULT_MESSAGE_ID = "tooled-ya"
TOOL_CALL_RESULT_TEXT = "Dunno"
TOOL_CALL_RESULT_MESSAGE = agui_core.ToolMessage(
    id=TOOL_CALL_RESULT_MESSAGE_ID,
    content=TOOL_CALL_RESULT_TEXT,
    tool_call_id=TOOL_CALL_ID,
)

W_PROMPT_AGUI_RUN_INPUT = agui_core.RunAgentInput(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    state={},
    messages=[
        SYSTEM_PROMPT_MESSAGE,
    ],
    tools=[],
    context=[],
    forwarded_props=None,
)

E_RUN_STARTED = agui_core.RunStartedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
)
W_INPUT_E_RUN_STARTED = agui_core.RunStartedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    input=EMPTY_AGUI_RUN_INPUT,
)


E_RUN_FINISHED = agui_core.RunFinishedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
)
RESULT = object()
W_RESULT_E_RUN_FINISHED = agui_core.RunFinishedEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    result=RESULT,
)

TEST_ERROR_MESSAGE = "Whoopsie!"
TEST_ERROR_CODE = "999"
E_RUN_ERROR = agui_core.RunErrorEvent(
    thread_id=TEST_THREAD_ID,
    run_id=TEST_RUN_ID,
    message=TEST_ERROR_MESSAGE,
    code=TEST_ERROR_CODE,
)

TEST_STEP_NAME = "test-step"
E_STEP_STARTED = agui_core.StepStartedEvent(
    step_name=TEST_STEP_NAME,
)
E_STEP_FINISHED = agui_core.StepFinishedEvent(
    step_name=TEST_STEP_NAME,
)

E_TEXT_MESSAGE_START = agui_core.TextMessageStartEvent(
    message_id=TEXT_REPLY_MESSAGE_ID,
)

TEXT_DELTA = "...added"
E_TEXT_MESSAGE_CONTENT = agui_core.TextMessageContentEvent(
    message_id=TEXT_REPLY_MESSAGE_ID, delta=TEXT_DELTA
)

E_TEXT_MESSAGE_END = agui_core.TextMessageEndEvent(
    message_id=TEXT_REPLY_MESSAGE_ID,
)

TOOL_CALL_PARENT_MESSAGE_ID = "tool-call-message"

TOOL_CALL_PARENT_MESSAGE = agui_core.AssistantMessage(
    id=TOOL_CALL_PARENT_MESSAGE_ID,
    tool_calls=[],
)

TOOL_CALL_NAME = "test_tool"
TOOL_CALL_ARG_DELTA = ",bar=2"

E_TOOL_CALL_START = agui_core.ToolCallStartEvent(
    tool_call_id=TOOL_CALL_ID,
    tool_call_name=TOOL_CALL_NAME,
)

W_PARENT_E_TOOL_CALL_START = agui_core.ToolCallStartEvent(
    parent_message_id=TOOL_CALL_PARENT_MESSAGE_ID,
    tool_call_id=TOOL_CALL_ID,
    tool_call_name=TOOL_CALL_NAME,
)

E_TOOL_CALL_ARGS = agui_core.ToolCallArgsEvent(
    tool_call_id=TOOL_CALL_ID,
    delta=TOOL_CALL_ARG_DELTA,
)

E_TOOL_CALL_END = agui_core.ToolCallEndEvent(
    tool_call_id=TOOL_CALL_ID,
)

E_TOOL_CALL_RESULT = agui_core.ToolCallResultEvent(
    message_id=TOOL_CALL_RESULT_MESSAGE_ID,
    tool_call_id=TOOL_CALL_ID,
    content=TOOL_CALL_RESULT_TEXT,
)

E_STATE_DELTA = agui_core.StateDeltaEvent(
    delta=[
        {"op": "add", "path": "/foo", "value": "bar"},
    ]
)

W_TEST_E_STATE_DELTA = agui_core.StateDeltaEvent(
    delta=[
        {"op": "test", "path": "/foo", "value": "foo"},
        {"op": "add", "path": "/foo", "value": "bar"},
    ]
)

STATE_SNAPSHOT = {"foo": "qux", "spam": "baz"}
E_STATE_SNAPSHOT = agui_core.StateSnapshotEvent(
    snapshot=STATE_SNAPSHOT,
)

MESSAGES_SNAPSHOT = [
    SYSTEM_PROMPT_MESSAGE,
    USER_PROMPT_MESSAGE,
    TOOL_CALL_RESULT_MESSAGE,
    TEXT_REPLY_MESSAGE,
]
E_MESSAGES_SNAPSHOT = agui_core.MessagesSnapshotEvent(
    messages=MESSAGES_SNAPSHOT,
)

E_ACTIVITY_MESSAGE_DELTA = agui_core.ActivityDeltaEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type="other",
    patch=[
        {"op": "add", "path": "/foo", "value": "bar"},
    ],
)

W_TEST_E_ACTIVITY_MESSAGE_DELTA = agui_core.ActivityDeltaEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type="other",
    patch=[
        {"op": "test", "path": "/foo", "value": "foo"},
        {"op": "add", "path": "/foo", "value": "bar"},
    ],
)

ACTIVITY_SNAPSHOT = {
    "baz": "frob",
}
E_ACTIVITY_MESSAGE_SNAPSHOT = agui_core.ActivitySnapshotEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type="other",
    content=ACTIVITY_SNAPSHOT,
)

WO_REPLACE_E_ACTIVITY_MESSAGE_SNAPSHOT = agui_core.ActivitySnapshotEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type="other",
    content=ACTIVITY_SNAPSHOT,
    replace=False,
)


no_error = contextlib.nullcontext


@pytest.fixture
def run_input():
    return EMPTY_AGUI_RUN_INPUT.model_copy(deep=True)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "events",
    [
        [],
        [TEST_RUN_STARTED],
        [TEST_RUN_STARTED, TEST_RUN_FINISHED],
    ],
)
async def test_run_stream_events(run_input, events):
    async def ev_iter():
        for event in events:
            yield event

    run = agui.Run(run_input=run_input)

    streamed = []

    async for event in run.stream_events(ev_iter()):
        streamed.append(event)

    for event, s_event, r_event in zip(
        events,
        streamed,
        run.events,
        strict=True,
    ):
        assert s_event is event
        assert r_event is event


@mock.patch("uuid.uuid4")
def test__make_thread_id(uu4):
    uu4.return_value = UUID4

    assert agui._make_thread_id() == str(UUID4)


@pytest.mark.anyio
def test_thread_new_run_w_mismatched_thread_id(run_input):
    thread = dataclasses.replace(TEST_THREAD, thread_id=OTHER_THREAD_ID)

    with pytest.raises(agui.WrongThreadId):
        thread.new_run(run_input)


@pytest.mark.anyio
def test_thread_new_run_w_duplicate_run_id(run_input):
    thread = dataclasses.replace(TEST_THREAD, runs={TEST_RUN_ID: object()})

    with pytest.raises(agui.DuplicateRunId):
        thread.new_run(run_input)


@pytest.mark.anyio
def test_thread_new_run_w_missing_parent_run_id(run_input):
    run_input.parent_run_id = "BOGUS"
    thread = dataclasses.replace(TEST_THREAD, runs={})

    with pytest.raises(agui.MissingParentRunId):
        thread.new_run(run_input)


@pytest.mark.anyio
def test_thread_new_run(run_input):
    thread = dataclasses.replace(TEST_THREAD, runs={})

    run = thread.new_run(run_input)

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
    the_threads = agui.Threads()
    the_threads._threads.update(w_threads)

    found = await the_threads.user_threads(user_name="testing")

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
    the_threads = agui.Threads()

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
        ({}, pytest.raises(agui.UnknownThread)),
        ({"testing": {}}, pytest.raises(agui.UnknownThread)),
        ({"testing": TEST_THREADS}, contextlib.nullcontext(None)),
    ],
)
async def test_threads_delete_thread(w_threads, expectation):
    the_threads = agui.Threads()

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

    found = await agui.get_the_threads(request)

    assert found is expected


@pytest.mark.parametrize(
    "json_dict, expectaton",
    [
        ({}, pytest.raises(agui.InvalidJSONEvent)),
        ({"type": "bogus"}, pytest.raises(agui.UnknownJSONEventType)),
        (
            {"type": agui_core.EventType.THINKING_START},
            no_error(agui_core.ThinkingStartEvent()),
        ),
        (
            {
                "type": agui_core.EventType.THINKING_START,
                "title": "I'm Thinking",
            },
            no_error(agui_core.ThinkingStartEvent(title="I'm Thinking")),
        ),
    ],
)
def test_agui_event_from_json(json_dict, expectaton):
    with expectaton as expected:
        found = agui.agui_event_from_json(json_dict)

    if isinstance(expected, agui_core.BaseEvent):
        assert found == expected


@pytest.mark.parametrize(
    "w_run",
    [
        None,
        mock.create_autospec(agui.Run),
    ],
)
def test_esp_ctor_wo_run_input(w_run):
    if w_run is not None:
        exp_run = w_run
        esp = agui.EventStreamParser(run=w_run)
    else:
        exp_run = None
        esp = agui.EventStreamParser()

    assert esp.run_input is None
    assert esp.the_run is exp_run
    assert esp.run_status == agui.RunStatus.INITIALIZED
    assert esp.active_steps == set()
    assert esp.error_message is None
    assert esp.error_code is None
    assert esp.result is None

    assert esp.state == {}
    assert esp.messages == []
    assert esp.messages_by_id == {}
    assert esp.active_tool_calls == {}
    assert esp.completed_tool_calls == set()


@pytest.mark.parametrize(
    "run_input",
    [
        EMPTY_AGUI_RUN_INPUT,
        W_STATE_AGUI_RUN_INPUT,
        W_PROMPT_AGUI_RUN_INPUT,
    ],
)
def test_esp_ctor_w_run_input(run_input):
    esp = agui.EventStreamParser(run_input)

    assert esp.run_input is run_input
    assert esp.the_run is None
    assert esp.run_status == agui.RunStatus.INITIALIZED
    assert esp.active_steps == set()
    assert esp.error_message is None
    assert esp.error_code is None
    assert esp.result is None

    assert esp.state == run_input.state
    assert esp.messages == run_input.messages
    assert esp.messages_by_id == {msg.id: msg for msg in run_input.messages}
    assert esp.active_tool_calls == {}
    assert esp.completed_tool_calls == set()


def test_esp_run_input_setter_w_already():
    esp = agui.EventStreamParser(EMPTY_AGUI_RUN_INPUT)

    with pytest.raises(agui.RunInputAlreadySet):
        esp.run_input = W_STATE_AGUI_RUN_INPUT


INITIALIZED = agui.RunStatus.INITIALIZED
RUNNING = agui.RunStatus.RUNNING
FINISHED = agui.RunStatus.FINISHED
ERROR = agui.RunStatus.ERROR

NO_STEPS = set()
W_TEST_STEP = set([TEST_STEP_NAME])

inv_status = pytest.raises(agui.InvalidRunStatusWithTarget)
not_running = pytest.raises(agui.NotRunning)
step_already = pytest.raises(agui.StepAlreadyStarted)
step_not_started = pytest.raises(agui.StepNotStarted)


@pytest.fixture(params=[None, False, True])
def event_kept(request):
    kw = {}
    event_log = [] if request.param else None

    if request.param is not None:
        kw["event_log"] = event_log

    def check_log(event):
        if request.param:
            assert event_log[-1] == event

    return kw, check_log


#
#   Lifecycle events
#


@pytest.mark.parametrize(
    "status, event, expectation, sets_input",
    [
        (INITIALIZED, E_RUN_STARTED, no_error(RUNNING), False),
        (INITIALIZED, W_INPUT_E_RUN_STARTED, no_error(RUNNING), True),
        (RUNNING, E_RUN_STARTED, inv_status, None),
        (FINISHED, E_RUN_STARTED, inv_status, None),
        (ERROR, E_RUN_STARTED, inv_status, None),
    ],
)
def test_esp_call_w_run_start(
    event_kept,
    status,
    event,
    expectation,
    sets_input,
):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, agui.RunStatus):
        assert esp.run_status == expected

        if sets_input:
            assert esp.run_input is event.input

    check_log(event)


@pytest.mark.parametrize(
    "status, event, expectation",
    [
        (INITIALIZED, E_RUN_FINISHED, inv_status),
        (RUNNING, E_RUN_FINISHED, no_error(FINISHED)),
        (RUNNING, W_RESULT_E_RUN_FINISHED, no_error(FINISHED)),
        (FINISHED, E_RUN_FINISHED, inv_status),
        (ERROR, E_RUN_FINISHED, inv_status),
    ],
)
def test_esp_call_w_run_finished(event_kept, status, event, expectation):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, agui.RunStatus):
        assert esp.run_status == expected
        assert esp.result is event.result

    check_log(event)


@pytest.mark.parametrize(
    "status, event, expectation",
    [
        (INITIALIZED, E_RUN_ERROR, inv_status),
        (RUNNING, E_RUN_ERROR, no_error(ERROR)),
        (FINISHED, E_RUN_ERROR, inv_status),
        (ERROR, E_RUN_ERROR, inv_status),
    ],
)
def test_esp_call_w_run_error(event_kept, status, event, expectation):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, agui.RunStatus):
        assert esp.run_status == expected
        assert esp.error_message is event.message
        assert esp.error_code is event.code

    check_log(event)


@pytest.mark.parametrize(
    "status, steps, event, expectation",
    [
        (INITIALIZED, NO_STEPS, E_STEP_STARTED, not_running),
        (RUNNING, W_TEST_STEP, E_STEP_STARTED, step_already),
        (RUNNING, NO_STEPS, E_STEP_STARTED, no_error(W_TEST_STEP)),
        (FINISHED, NO_STEPS, E_STEP_STARTED, not_running),
        (ERROR, NO_STEPS, E_STEP_STARTED, not_running),
    ],
)
def test_esp_call_w_step_start(event_kept, status, steps, event, expectation):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(
        run_status=status, active_steps=steps.copy(), **kw
    )

    with expectation as expected:
        esp(event)

    if isinstance(expected, set):
        assert esp.active_steps == expected

    check_log(event)


@pytest.mark.parametrize(
    "status, steps, event, expectation",
    [
        (INITIALIZED, NO_STEPS, E_STEP_FINISHED, not_running),
        (RUNNING, W_TEST_STEP, E_STEP_FINISHED, no_error(NO_STEPS)),
        (RUNNING, NO_STEPS, E_STEP_FINISHED, step_not_started),
        (FINISHED, NO_STEPS, E_STEP_FINISHED, not_running),
        (ERROR, NO_STEPS, E_STEP_FINISHED, not_running),
    ],
)
def test_esp_call_w_step_finished(
    event_kept, status, steps, event, expectation
):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(
        run_status=status, active_steps=steps.copy(), **kw
    )

    with expectation as expected:
        esp(event)

    if isinstance(expected, set):
        assert esp.active_steps == expected

    check_log(event)


#
#   TextMessage events
#
message_already = pytest.raises(agui.MessageAlreadyExists)
message_nonesuch = pytest.raises(agui.MessageDoesNotExist)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_TEXT_MESSAGE_START, not_running),
        (RUNNING, [], E_TEXT_MESSAGE_START, no_error(None)),
        (RUNNING, [TEXT_REPLY_MESSAGE], E_TEXT_MESSAGE_START, message_already),
        (FINISHED, [], E_TEXT_MESSAGE_START, not_running),
        (ERROR, [], E_TEXT_MESSAGE_START, not_running),
    ],
)
def test_esp_call_w_text_message_start(
    event_kept, status, messages, event, expectation
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]

    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id={msg.id: msg for msg in esp_messages},
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.messages) == len(messages) + 1
        assert esp.messages[-1].id == event.message_id
        assert esp.messages[-1].content == ""

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_TEXT_MESSAGE_CONTENT, not_running),
        (RUNNING, [], E_TEXT_MESSAGE_CONTENT, message_nonesuch),
        (
            RUNNING,
            [TEXT_REPLY_MESSAGE],
            E_TEXT_MESSAGE_CONTENT,
            no_error(None),
        ),
        (FINISHED, [], E_TEXT_MESSAGE_CONTENT, not_running),
        (ERROR, [], E_TEXT_MESSAGE_CONTENT, not_running),
    ],
)
def test_esp_call_w_text_message_content(
    event_kept, status, messages, event, expectation
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]

    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id={msg.id: msg for msg in esp_messages},
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.messages) == len(messages)
        assert esp.messages[-1].id == event.message_id
        assert esp.messages[-1].content == messages[-1].content + TEXT_DELTA

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_TEXT_MESSAGE_END, not_running),
        (RUNNING, [], E_TEXT_MESSAGE_END, message_nonesuch),
        (
            RUNNING,
            [TEXT_REPLY_MESSAGE],
            E_TEXT_MESSAGE_END,
            no_error(None),
        ),
        (FINISHED, [], E_TEXT_MESSAGE_END, not_running),
        (ERROR, [], E_TEXT_MESSAGE_END, not_running),
    ],
)
def test_esp_call_w_text_message_end(
    event_kept, status, messages, event, expectation
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]

    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id={msg.id: msg for msg in esp_messages},
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.messages) == len(messages)
        assert esp.messages[-1].id == event.message_id
        assert esp.messages[-1].content == messages[-1].content

    check_log(event)


#
#   ToolCall events
#
tool_call_already = pytest.raises(agui.ToolCallAlreadyExists)
tool_call_nonesuch = pytest.raises(agui.ToolCallDoesNotExist)


@pytest.mark.parametrize(
    "status, messages, active_tcs, event, expectation",
    [
        (INITIALIZED, [], {}, E_TOOL_CALL_START, not_running),
        (RUNNING, [], {}, E_TOOL_CALL_START, no_error(None)),
        (
            RUNNING,
            [],
            {TOOL_CALL_ID: (TOOL_CALL, None)},
            E_TOOL_CALL_START,
            tool_call_already,
        ),
        (
            RUNNING,
            [TOOL_CALL_PARENT_MESSAGE.model_copy(deep=True)],
            {},
            W_PARENT_E_TOOL_CALL_START,
            no_error(None),
        ),
        (RUNNING, [], {}, W_PARENT_E_TOOL_CALL_START, no_error(None)),
        (FINISHED, [], {}, E_TOOL_CALL_START, not_running),
        (ERROR, [], {}, E_TOOL_CALL_START, not_running),
    ],
)
def test_esp_call_w_tool_call_start(
    event_kept,
    status,
    messages,
    active_tcs,
    event,
    expectation,
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]
    esp_tool_calls_by_id = {
        key: (value[0].model_copy(deep=True), value[1])
        for key, value in active_tcs.items()
    }

    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id={msg.id: msg for msg in esp_messages},
        active_tool_calls=esp_tool_calls_by_id,
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.active_tool_calls) == len(active_tcs) + 1
        tool_call, parent = esp.active_tool_calls[event.tool_call_id]

        assert tool_call.id == event.tool_call_id
        assert tool_call.function.name == event.tool_call_name
        assert tool_call.function.arguments == ""

        if event.parent_message_id is None:
            assert parent is None
        else:
            assert parent is esp_messages[0]

    check_log(event)


@pytest.mark.parametrize(
    "status, active_tcs, event, expectation",
    [
        (INITIALIZED, {}, E_TOOL_CALL_ARGS, not_running),
        (
            RUNNING,
            {TOOL_CALL_ID: (TOOL_CALL, None)},
            E_TOOL_CALL_ARGS,
            no_error(None),
        ),
        (
            RUNNING,
            {},
            E_TOOL_CALL_ARGS,
            tool_call_nonesuch,
        ),
        (FINISHED, {}, E_TOOL_CALL_ARGS, not_running),
        (ERROR, {}, E_TOOL_CALL_ARGS, not_running),
    ],
)
def test_esp_call_w_tool_call_args(
    event_kept,
    status,
    active_tcs,
    event,
    expectation,
):
    kw, check_log = event_kept

    esp_tool_calls_by_id = {
        key: (value[0].model_copy(deep=True), value[1])
        for key, value in active_tcs.items()
    }
    before, _ = active_tcs.get(event.tool_call_id, (None, None))

    esp = agui.EventStreamParser(
        run_status=status,
        active_tool_calls=esp_tool_calls_by_id,
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.active_tool_calls) == len(active_tcs)
        tool_call, parent = esp.active_tool_calls[event.tool_call_id]

        assert tool_call.id == event.tool_call_id
        assert tool_call.function.arguments == (
            before.function.arguments + event.delta
        )

    check_log(event)


@pytest.mark.parametrize(
    "status, active_tcs, event, expectation",
    [
        (INITIALIZED, {}, E_TOOL_CALL_END, not_running),
        (
            RUNNING,
            {
                TOOL_CALL_ID: (TOOL_CALL, None),
            },
            E_TOOL_CALL_END,
            no_error(None),
        ),
        (
            RUNNING,
            {
                TOOL_CALL_ID: (
                    TOOL_CALL,
                    TOOL_CALL_PARENT_MESSAGE.model_copy(deep=True),
                )
            },
            E_TOOL_CALL_END,
            no_error(None),
        ),
        (
            RUNNING,
            {},
            E_TOOL_CALL_END,
            tool_call_nonesuch,
        ),
        (FINISHED, {}, E_TOOL_CALL_END, not_running),
        (ERROR, {}, E_TOOL_CALL_END, not_running),
    ],
)
def test_esp_call_w_tool_call_end(
    event_kept, status, active_tcs, event, expectation
):
    kw, check_log = event_kept

    esp_tool_calls_by_id = {
        key: (value[0].model_copy(deep=True), value[1])
        for key, value in active_tcs.items()
    }

    esp = agui.EventStreamParser(
        run_status=status,
        active_tool_calls=esp_tool_calls_by_id,
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        tool_call, parent = active_tcs[event.tool_call_id]

        if parent is not None:
            assert parent.tool_calls[-1] == tool_call

        assert len(esp.active_tool_calls) == len(active_tcs) - 1

        assert event.tool_call_id in esp.completed_tool_calls

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, completed_tcs, event, expectation",
    [
        (INITIALIZED, [], set(), E_TOOL_CALL_RESULT, not_running),
        (
            RUNNING,
            [],
            set([TOOL_CALL_ID]),
            E_TOOL_CALL_RESULT,
            no_error(None),
        ),
        (
            RUNNING,
            [],
            set(),
            E_TOOL_CALL_RESULT,
            tool_call_nonesuch,
        ),
        (FINISHED, [], set(), E_TOOL_CALL_RESULT, not_running),
        (ERROR, [], set(), E_TOOL_CALL_RESULT, not_running),
    ],
)
def test_esp_call_w_tool_call_result(
    event_kept,
    status,
    messages,
    completed_tcs,
    event,
    expectation,
):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(
        run_status=status,
        completed_tool_calls=set(completed_tcs),
        **kw,
    )

    with expectation as expected:
        esp(event)

    if expected is None:
        assert len(esp.messages) == len(messages) + 1
        added = esp.messages[-1]
        assert added is esp.messages_by_id[event.message_id]
        assert added.tool_call_id == event.tool_call_id
        assert added.content == event.content

    check_log(event)


#
#   State management events
#
patch_failed = pytest.raises(jsonpatch.JsonPatchException)


@pytest.mark.parametrize(
    "status, state, event, expectation",
    [
        (INITIALIZED, {}, E_STATE_DELTA, not_running),
        (RUNNING, {}, E_STATE_DELTA, no_error({"foo": "bar"})),
        (RUNNING, {"foo": "foo"}, E_STATE_DELTA, no_error({"foo": "bar"})),
        (RUNNING, {}, W_TEST_E_STATE_DELTA, patch_failed),
        (
            RUNNING,
            {"foo": "foo"},
            W_TEST_E_STATE_DELTA,
            no_error({"foo": "bar"}),
        ),
        (FINISHED, {}, E_STATE_DELTA, not_running),
        (ERROR, {}, E_STATE_DELTA, not_running),
    ],
)
def test_esp_call_w_state_delta(event_kept, status, state, event, expectation):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, state=state.copy(), **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, dict):
        assert esp.state == expected

    check_log(event)


@pytest.mark.parametrize(
    "status, state, event, expectation",
    [
        (INITIALIZED, {}, E_STATE_SNAPSHOT, not_running),
        (RUNNING, {}, E_STATE_SNAPSHOT, no_error(STATE_SNAPSHOT)),
        (RUNNING, {"foo": "foo"}, E_STATE_SNAPSHOT, no_error(STATE_SNAPSHOT)),
        (FINISHED, {}, E_STATE_SNAPSHOT, not_running),
        (ERROR, {}, E_STATE_SNAPSHOT, not_running),
    ],
)
def test_esp_call_w_state_snapshot(
    event_kept, status, state, event, expectation
):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, state=state.copy(), **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, dict):
        assert esp.state == expected

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_MESSAGES_SNAPSHOT, not_running),
        (RUNNING, [], E_MESSAGES_SNAPSHOT, no_error(MESSAGES_SNAPSHOT)),
        (
            RUNNING,
            [
                SYSTEM_PROMPT_MESSAGE,
                USER_PROMPT_MESSAGE,
                TOOL_CALL_RESULT_MESSAGE,
            ],
            E_MESSAGES_SNAPSHOT,
            no_error(MESSAGES_SNAPSHOT),
        ),
        (FINISHED, [], E_MESSAGES_SNAPSHOT, not_running),
        (ERROR, [], E_MESSAGES_SNAPSHOT, not_running),
    ],
)
def test_esp_call_w_messages_snapshot(
    event_kept, status, messages, event, expectation
):
    kw, check_log = event_kept

    esp = agui.EventStreamParser(run_status=status, messages=messages, **kw)

    with expectation as expected:
        esp(event)

    if isinstance(expected, list):
        assert esp.messages == expected

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_ACTIVITY_MESSAGE_DELTA, not_running),
        (RUNNING, [], E_ACTIVITY_MESSAGE_DELTA, no_error({"foo": "bar"})),
        (
            RUNNING,
            [ACTIVITY_MESSAGE],
            E_ACTIVITY_MESSAGE_DELTA,
            no_error({"foo": "bar"}),
        ),
        (
            RUNNING,
            [OTHER_ACTIVITY_MESSAGE],
            W_TEST_E_ACTIVITY_MESSAGE_DELTA,
            patch_failed,
        ),
        (
            RUNNING,
            [ACTIVITY_MESSAGE],
            W_TEST_E_ACTIVITY_MESSAGE_DELTA,
            no_error({"foo": "bar"}),
        ),
        (FINISHED, [], E_ACTIVITY_MESSAGE_DELTA, not_running),
        (ERROR, [], E_ACTIVITY_MESSAGE_DELTA, not_running),
    ],
)
def test_esp_call_w_activity_message_delta(
    event_kept,
    status,
    messages,
    event,
    expectation,
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]
    esp_messages_by_id = {
        msg.id: msg.model_copy(deep=True) for msg in messages
    }
    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id=esp_messages_by_id,
        **kw,
    )

    with expectation as expected:
        esp(event)

    if isinstance(expected, dict):
        activity_message = esp.messages_by_id[ACTIVITY_MESSAGE_ID]
        assert activity_message.activity_type == event.activity_type
        assert activity_message.content == expected

    check_log(event)


@pytest.mark.parametrize(
    "status, messages, event, expectation",
    [
        (INITIALIZED, [], E_ACTIVITY_MESSAGE_SNAPSHOT, not_running),
        (
            RUNNING,
            [],
            E_ACTIVITY_MESSAGE_SNAPSHOT,
            no_error(ACTIVITY_SNAPSHOT),
        ),
        (
            RUNNING,
            [ACTIVITY_MESSAGE],
            E_ACTIVITY_MESSAGE_SNAPSHOT,
            no_error(ACTIVITY_SNAPSHOT),
        ),
        (
            RUNNING,
            [ACTIVITY_MESSAGE],
            WO_REPLACE_E_ACTIVITY_MESSAGE_SNAPSHOT,
            message_already,
        ),
        (
            RUNNING,
            [],
            WO_REPLACE_E_ACTIVITY_MESSAGE_SNAPSHOT,
            no_error(ACTIVITY_SNAPSHOT),
        ),
        (FINISHED, [], E_ACTIVITY_MESSAGE_SNAPSHOT, not_running),
        (ERROR, [], E_ACTIVITY_MESSAGE_SNAPSHOT, not_running),
    ],
)
def test_esp_call_w_activity_message_snapshot(
    event_kept,
    status,
    messages,
    event,
    expectation,
):
    kw, check_log = event_kept

    esp_messages = [msg.model_copy(deep=True) for msg in messages]
    esp_messages_by_id = {
        msg.id: msg.model_copy(deep=True) for msg in messages
    }
    esp = agui.EventStreamParser(
        run_status=status,
        messages=esp_messages,
        messages_by_id=esp_messages_by_id,
        **kw,
    )

    with expectation as expected:
        esp(event)

    if isinstance(expected, dict):
        activity_message = esp.messages_by_id[ACTIVITY_MESSAGE_ID]
        assert activity_message.activity_type == event.activity_type
        assert activity_message.content == expected

    check_log(event)


@pytest.mark.parametrize(
    "event",
    [
        agui_core.ThinkingTextMessageStartEvent(),
        agui_core.ThinkingTextMessageContentEvent(delta=" "),
        agui_core.ThinkingTextMessageEndEvent(),
        agui_core.RawEvent(event=object()),
        agui_core.CustomEvent(name="custom", value=object()),
    ],
)
def test_esp_call_w_ignored_event_types(
    event,
):
    event_log = []
    esp = agui.EventStreamParser(event_log=event_log)

    esp(event)

    assert event_log == []


@pytest.mark.anyio
@pytest.mark.parametrize(
    "events",
    [
        (),
        [
            TEST_RUN_STARTED,
            TEST_RUN_FINISHED,
        ],
    ],
)
@pytest.mark.parametrize(
    "w_run",
    [
        None,
        mock.create_autospec(agui.Run, events=[]),
    ],
)
async def test_esp__store_run_events(w_run, events):
    esp = agui.EventStreamParser(run=w_run, event_log=events)

    await esp._store_run_events()

    if w_run is not None:
        assert w_run.events == list(events)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "events",
    [
        (),
        [
            TEST_RUN_STARTED,
            TEST_RUN_FINISHED,
        ],
    ],
)
async def test_esp_parse_stream(run_input, events):
    async def stream() -> agui.AGUI_EventIterator:
        for event in events:
            yield event

    esp = agui.EventStreamParser(run_input)
    sre = esp._store_run_events = mock.AsyncMock(spec_set=())

    found = [event async for event in esp.parse_stream(stream())]

    assert len(found) == len(events)

    sre.assert_called_once_with()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "json_dicts, events",
    [
        ([], []),
        (
            [
                TEST_RUN_STARTED.model_dump(),
                TEST_RUN_FINISHED.model_dump(),
            ],
            [
                TEST_RUN_STARTED,
                TEST_RUN_FINISHED,
            ],
        ),
    ],
)
async def test_esp_parse_json_stream(run_input, json_dicts, events):
    async def stream() -> agui.AGUI_EventIterator:
        for json_dict in json_dicts:
            yield json_dict

    esp = agui.EventStreamParser(run_input)
    sre = esp._store_run_events = mock.AsyncMock(spec_set=())

    found = [event async for event in esp.parse_json_stream(stream())]

    assert found == events

    sre.assert_called_once_with()


def test_esp_as_run_agent_input_wo_run_input():
    esp = agui.EventStreamParser()

    with pytest.raises(agui.NoRunInput):
        _ = esp.as_run_agent_input


@pytest.mark.parametrize(
    "state",
    [
        None,
        STATE_SNAPSHOT,
    ],
)
@pytest.mark.parametrize(
    "messages",
    [
        None,
        [TEST_RUN_STARTED, TEST_RUN_FINISHED],
    ],
)
def test_esp_as_run_agent_input_w_run_input(run_input, messages, state):
    esp = agui.EventStreamParser(run_input)

    if messages is not None:
        exp_messages = esp.messages = [
            msg.model_copy(deep=True) for msg in messages
        ]
    else:
        exp_messages = run_input.messages[:]

    if state is not None:
        exp_state = esp.state = state.copy()
    else:
        exp_state = run_input.state.copy()

    found = esp.as_run_agent_input

    assert found.messages == exp_messages
    assert found.state == exp_state
