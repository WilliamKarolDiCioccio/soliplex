import uuid
from unittest import mock

import pytest
import sqlalchemy
from ag_ui import core as agui_core
from sqlalchemy import orm as sqla_orm

from soliplex.agui import persistence as agui_persistence

THREAD_UUID = str(uuid.uuid4())
THREAD_NAME = "Test Thread"
THREAD_DESCRIPTION = "This thread is for testing"

RUN_UUID = str(uuid.uuid4())
RUN_LABEL = "test-run-label"
PARENT_RUN_ID = str(uuid.uuid4())

USER_MESSAGE_ID = str(uuid.uuid4())
STATE = {
    "foo": "Bar",
}
USER_PROMPT = "Which way is up?"
USER_MESSAGE = agui_core.UserMessage(
    id=USER_MESSAGE_ID,
    content=USER_PROMPT,
)
CONTEXT_DESC = "This context is for testing"
CONTEXT_VALUE = "Test context"
CONTEXT = agui_core.Context(
    description=CONTEXT_DESC,
    value=CONTEXT_VALUE,
)
TOOL_NAME = "test-tool"
TOOL_DESC = "This tool is for testing"
TOOL = agui_core.Tool(
    name=TOOL_NAME,
    description=TOOL_DESC,
    parameters=None,
)
FORWRDED_PROPS = {
    "spam": "Qux",
}

EMPTY_RUN_AGENT_INPUT = agui_core.RunAgentInput(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
    parent_run_id=None,
    state=None,
    messages=[],
    context=[],
    tools=[],
    forwarded_props=None,
)

FULL_RUN_AGENT_INPUT = agui_core.RunAgentInput(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
    parent_run_id=PARENT_RUN_ID,
    state=STATE,
    messages=[USER_MESSAGE],
    context=[CONTEXT],
    tools=[TOOL],
    forwarded_props=FORWRDED_PROPS,
)

TEXT_MESSAGE_ID = str(uuid.uuid4())
TEXT_MESSAGE_DELTA = "delta"

TEXT_MESSAGE_START_EVENT = agui_core.TextMessageStartEvent(
    message_id=TEXT_MESSAGE_ID,
)

TEXT_MESSAGE_CONTENT_EVENT = agui_core.TextMessageContentEvent(
    message_id=TEXT_MESSAGE_ID,
    delta=TEXT_MESSAGE_DELTA,
)

TEXT_MESSAGE_END_EVENT = agui_core.TextMessageEndEvent(
    message_id=TEXT_MESSAGE_ID,
)

TEXT_MESSAGE_CHUNK_EVENT = agui_core.TextMessageChunkEvent(
    message_id=TEXT_MESSAGE_ID,
    delta=TEXT_MESSAGE_DELTA,
)

TOOL_CALL_ID = str(uuid.uuid4())
TOOL_CALL_NAME = "test-tool"
TOOL_CALL_ARGS_DELTA = "args delta"
TOOL_CALL_MESSAGE_ID = str(uuid.uuid4())
TOOL_CALL_RESULT_CONTENT = "tool result"

TOOL_CALL_START_EVENT = agui_core.ToolCallStartEvent(
    tool_call_id=TOOL_CALL_ID,
    tool_call_name=TOOL_CALL_NAME,
)

TOOL_CALL_ARGS_EVENT = agui_core.ToolCallArgsEvent(
    tool_call_id=TOOL_CALL_ID,
    delta=TOOL_CALL_ARGS_DELTA,
)

TOOL_CALL_END_EVENT = agui_core.ToolCallEndEvent(
    tool_call_id=TOOL_CALL_ID,
)

EMPTY_TOOL_CALL_CHUNK_EVENT = agui_core.ToolCallChunkEvent(
    tool_call_id=TOOL_CALL_ID,
)
TOOL_CALL_CHUNK_EVENT = agui_core.ToolCallChunkEvent(
    tool_call_id=TOOL_CALL_ID,
    tool_call_name=TOOL_CALL_NAME,
    parent_message_id=TOOL_CALL_MESSAGE_ID,
    delta=TOOL_CALL_ARGS_DELTA,
)

TOOL_CALL_RESULT_EVENT = agui_core.ToolCallResultEvent(
    message_id=TOOL_CALL_MESSAGE_ID,
    tool_call_id=TOOL_CALL_ID,
    content=TOOL_CALL_RESULT_CONTENT,
)

STATE_SNAPTSHOT = {"foo": "Bar", "baz": "Quz"}
STATE_DELTA = {"baz": "Spam"}
STATE_SNAPSHOT_EVENT = agui_core.StateSnapshotEvent(
    snapshot=STATE_SNAPTSHOT,
)

STATE_DELTA_EVENT = agui_core.StateDeltaEvent(
    delta=[STATE_DELTA],
)

DEVELOPER_MESSAGE_ID = str(uuid.uuid4())
DEVELOPER_MESSAGE_CONTENT = "this is a test"
DEVELOPER_MESSAGE_NAME = "phreddy"
DEVELOPER_MESSAGE = agui_core.DeveloperMessage(
    id=DEVELOPER_MESSAGE_ID,
    content=DEVELOPER_MESSAGE_CONTENT,
    name=DEVELOPER_MESSAGE_NAME,
)
EMPTY_MESSAGES_SNAPSHOT_EVENT = agui_core.MessagesSnapshotEvent(
    messages=[],
)
MESSAGES_SNAPSHOT_EVENT = agui_core.MessagesSnapshotEvent(
    messages=[DEVELOPER_MESSAGE],
)

ACTIVITY_MESSAGE_ID = str(uuid.uuid4())
ACTIVITY_TYPE = "test activity"
ACTIVITY_CONTENT = {"waaa": "Blaah"}
ACTIVITY_PATCH = {"waaa": "Oooph"}
ACTIVITY_SNAPSHOT_EVENT = agui_core.ActivitySnapshotEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type=ACTIVITY_TYPE,
    content=ACTIVITY_CONTENT,
    replace=False,
)

ACTIVITY_DELTA_EVENT = agui_core.ActivityDeltaEvent(
    message_id=ACTIVITY_MESSAGE_ID,
    activity_type=ACTIVITY_TYPE,
    patch=[ACTIVITY_PATCH],
)

RAW_EVENT_EVENT = {"raw": "hide"}
RAW_SOURCE = "raw source"
NO_SOURCE_RAW_EVENT = agui_core.RawEvent(
    event=RAW_EVENT_EVENT,
)
RAW_EVENT = agui_core.RawEvent(
    event=RAW_EVENT_EVENT,
    source=RAW_SOURCE,
)

CUSTOM_NAME = "test-custom"
CUSTOM_VALUE = {"tailor": "made"}
CUSTOM_EVENT = agui_core.CustomEvent(
    name=CUSTOM_NAME,
    value=CUSTOM_VALUE,
)

BARE_RUN_STARTED_EVENT = agui_core.RunStartedEvent(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
)

W_PARENT_RUN_ID_RUN_STARTED_EVENT = agui_core.RunStartedEvent(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
    parent_run_id=PARENT_RUN_ID,
)

W_RAI_RUN_STARTED_EVENT = agui_core.RunStartedEvent(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
    run_agent_input=FULL_RUN_AGENT_INPUT,
)

RUN_RESULT = "test run result"
BARE_RUN_FINISHED_EVENT = agui_core.RunFinishedEvent(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
)
W_RESULT_RUN_FINISHED_EVENT = agui_core.RunFinishedEvent(
    thread_id=THREAD_UUID,
    run_id=RUN_UUID,
    result=RUN_RESULT,
)

RUN_ERROR_MESSAGE = "test error"
RUN_CODE = "999"
BARE_RUN_ERROR_EVENT = agui_core.RunErrorEvent(
    message=RUN_ERROR_MESSAGE,
)
W_CODE_RUN_ERROR_EVENT = agui_core.RunErrorEvent(
    message=RUN_ERROR_MESSAGE,
    code=RUN_CODE,
)

STEP_NAME = "test step"
STEP_STARTED_EVENT = agui_core.StepStartedEvent(
    step_name=STEP_NAME,
)

STEP_FINISHED_EVENT = agui_core.StepFinishedEvent(
    step_name=STEP_NAME,
)

ROOM_ID = "test-room"
USER_NAME = "phreddy"

TEST_AGUI_RUN_EVENTS = [
    BARE_RUN_STARTED_EVENT,
    STEP_STARTED_EVENT,
    ACTIVITY_SNAPSHOT_EVENT,
    ACTIVITY_DELTA_EVENT,
    STEP_FINISHED_EVENT,
    TEXT_MESSAGE_START_EVENT,
    TEXT_MESSAGE_CONTENT_EVENT,
    TEXT_MESSAGE_END_EVENT,
    TOOL_CALL_START_EVENT,
    TOOL_CALL_ARGS_EVENT,
    TOOL_CALL_END_EVENT,
    TOOL_CALL_RESULT_EVENT,
    W_RESULT_RUN_FINISHED_EVENT,
]


@pytest.mark.parametrize(
    "agui_rai",
    [
        EMPTY_RUN_AGENT_INPUT,
        FULL_RUN_AGENT_INPUT,
    ],
)
def test_runagentinput_from_agui_model(agui_rai):
    run = agui_persistence.Run()

    found = agui_persistence.RunAgentInput.from_agui_model(run, agui_rai)

    assert found.run is run
    assert found.data == agui_rai.model_dump()

    assert found.thread_id == agui_rai.thread_id
    assert found.run_id == agui_rai.run_id
    assert found.parent_run_id == agui_rai.parent_run_id
    assert found.state == agui_rai.state
    assert found.messages == agui_rai.messages
    assert found.context == agui_rai.context
    assert found.tools == agui_rai.tools
    assert found.forwarded_props == agui_rai.forwarded_props


@pytest.mark.parametrize(
    "agui_event",
    [
        TEXT_MESSAGE_START_EVENT,
        TEXT_MESSAGE_CONTENT_EVENT,
        TEXT_MESSAGE_END_EVENT,
        TEXT_MESSAGE_CHUNK_EVENT,
        TOOL_CALL_START_EVENT,
        TOOL_CALL_ARGS_EVENT,
        TOOL_CALL_END_EVENT,
        EMPTY_TOOL_CALL_CHUNK_EVENT,
        TOOL_CALL_CHUNK_EVENT,
        TOOL_CALL_RESULT_EVENT,
        STATE_SNAPSHOT_EVENT,
        STATE_DELTA_EVENT,
        EMPTY_MESSAGES_SNAPSHOT_EVENT,
        MESSAGES_SNAPSHOT_EVENT,
        ACTIVITY_SNAPSHOT_EVENT,
        ACTIVITY_DELTA_EVENT,
        NO_SOURCE_RAW_EVENT,
        RAW_EVENT,
        CUSTOM_EVENT,
        BARE_RUN_STARTED_EVENT,
        W_PARENT_RUN_ID_RUN_STARTED_EVENT,
        W_RAI_RUN_STARTED_EVENT,
        BARE_RUN_FINISHED_EVENT,
        W_RESULT_RUN_FINISHED_EVENT,
        BARE_RUN_ERROR_EVENT,
        W_CODE_RUN_ERROR_EVENT,
        STEP_STARTED_EVENT,
        STEP_FINISHED_EVENT,
    ],
)
def test_runevent_from_agui_event(agui_event):
    run = agui_persistence.Run()

    found = agui_persistence.RunEvent.from_agui_model(run, agui_event)

    assert found.run is run
    assert found.data == agui_event.model_dump()

    assert found.type == agui_event.type


@pytest.mark.parametrize("init_schema", [False, True])
@mock.patch("sqlalchemy.create_engine")
@mock.patch("soliplex.agui.persistence.metadata.create_all")
def test_get_session(
    ca,
    ce,
    init_schema,
):
    kwargs = {}

    if init_schema:
        kwargs["init_schema"] = True

    with agui_persistence.get_session(**kwargs) as session:
        assert isinstance(session, sqla_orm.Session)
        assert session.bind is ce.return_value

        ce.assert_called_once_with(agui_persistence.MEMORY_ENGINE_URL)

        if init_schema:
            connection = ce.return_value.connect.return_value
            ca.assert_called_once_with(connection.__enter__.return_value)
        else:
            ca.assert_not_called()


@pytest.fixture
def the_engine():
    engine = sqlalchemy.create_engine(agui_persistence.MEMORY_ENGINE_URL)

    yield engine

    engine.dispose()


@pytest.fixture
def the_session(the_engine):
    with the_engine.connect() as connection:
        agui_persistence.Base.metadata.create_all(connection)

    assert connection.closed

    with sqla_orm.Session(bind=the_engine) as session:
        yield session


def test_sqla_thread_ctor(the_session):
    thread = agui_persistence.Thread(
        room_id=ROOM_ID,
        user_name=USER_NAME,
    )
    the_session.add(thread)
    the_session.commit()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "agui_rai",
    [
        EMPTY_RUN_AGENT_INPUT,
        FULL_RUN_AGENT_INPUT,
    ],
)
def test_sqla_thread_run_interactions(the_session, agui_rai):
    with the_session as session:
        thread = agui_persistence.Thread(
            room_id=ROOM_ID,
            user_name=USER_NAME,
        )
        session.add(thread)
        session.commit()

        assert thread.thread_metadata is None
        assert thread.runs == []

        thread_meta = agui_persistence.ThreadMetadata(
            thread=thread,
            name=THREAD_NAME,
            description=THREAD_DESCRIPTION,
        )
        session.add(thread_meta)
        session.commit()

        assert thread.thread_metadata is thread_meta

        run = agui_persistence.Run(
            thread=thread,
        )
        session.add(run)
        session.commit()

        assert thread.runs == [run]

        assert run.run_metadata is None
        assert run.run_agent_input is None

        run_meta = agui_persistence.RunMetadata(
            run=run,
            label=RUN_LABEL,
        )
        session.add(run_meta)
        session.commit()

        assert run.run_metadata is run_meta

        rai = agui_persistence.RunAgentInput.from_agui_model(
            run,
            agui_rai,
        )
        session.add(rai)
        session.commit()

        assert run.run_agent_input is rai


def test_sqla_run_hierarchy(the_session):
    with the_session as session:
        thread = agui_persistence.Thread(
            room_id=ROOM_ID,
            user_name=USER_NAME,
        )
        session.add(thread)
        session.commit()

        parent_run = agui_persistence.Run(
            thread=thread,
        )
        session.add(parent_run)
        session.commit()

        assert thread.runs == [parent_run]
        assert parent_run.children == []

        child_run = agui_persistence.Run(thread=thread, parent=parent_run)
        session.add(parent_run)
        session.commit()

        assert thread.runs == [parent_run, child_run]
        assert parent_run.children == [child_run]


def test_sqla_run_events(the_session):
    with the_session as session:
        thread = agui_persistence.Thread(
            room_id=ROOM_ID,
            user_name=USER_NAME,
        )
        session.add(thread)
        session.commit()

        run = agui_persistence.Run(
            thread=thread,
        )
        session.add(run)
        session.commit()

        events = []

        for agui_event in TEST_AGUI_RUN_EVENTS:
            event = agui_persistence.RunEvent.from_agui_model(run, agui_event)
            events.append(event)
            session.add(event)

        session.commit()

        for agui_event, db_event in zip(
            TEST_AGUI_RUN_EVENTS,
            run.events,
            strict=True,
        ):
            assert db_event.type == agui_event.type
