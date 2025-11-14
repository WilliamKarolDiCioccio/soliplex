"""Track AGUI threads by user and room.

If / when we move to a "persistent" history store, this module should firewall
that choice away from the rest of the system.
"""

import asyncio
import dataclasses
import enum
import typing
import uuid
from collections import abc

import fastapi
import jsonpatch
from ag_ui import core as agui_core

REQUEST_CONTEXT_PARTS = ("system-prompt", "user-prompt")
RESPONSE_CONTEXT_PARTS = ("text",)


# =============================================================================
#   In-memory storage for room-based AGUI threads.
# =============================================================================

AGUI_Events = list[agui_core.BaseEvent]
AGUI_EventIterator = abc.AsyncIterator[agui_core.BaseEvent]


@dataclasses.dataclass(frozen=True)
class Run:
    """Hold original input data and events for an AGUI run"""

    run_input: agui_core.RunAgentInput
    events: AGUI_Events = dataclasses.field(
        default_factory=list,
    )

    async def stream_events(
        self,
        event_iter: AGUI_EventIterator,
    ) -> AGUI_EventIterator:
        """Tee stream of AGUI events to our own 'events'"""

        async for event in event_iter:
            self.events.append(event)

            yield event


class WrongThreadId(ValueError):
    def __init__(self, thread_id: str, expected_thread_id: str):
        self.thread_id = thread_id
        self.expected_thread_id = expected_thread_id
        super().__init__(
            f"Run input thread ID {thread_id} "
            f"does not match thread's ID {expected_thread_id}"
        )


class DuplicateRunId(ValueError):
    def __init__(self, run_id: str):
        self.run_id = run_id
        super().__init__(f"Run input run ID {run_id} already exists in thread")


class MissingParentRunId(ValueError):
    def __init__(self, parent_run_id: str):
        self.parent_run_id = parent_run_id
        super().__init__(
            f"Run input parent run ID {parent_run_id} does not exist in thread"
        )


def _make_thread_id() -> str:
    return str(uuid.uuid4())


@dataclasses.dataclass(frozen=True)
class Thread:
    """Hold a set of AGUI runs sharing the same 'thread_id'"""

    thread_id: str = dataclasses.field(default_factory=_make_thread_id)
    room_id: str = dataclasses.field(kw_only=True)
    name: str | None = dataclasses.field(default=None, kw_only=True)
    runs: dict[Run] = dataclasses.field(default_factory=dict)

    def new_run(self, run_input: agui_core.RunAgentInput) -> Run:
        if run_input.thread_id != self.thread_id:
            raise WrongThreadId(run_input.thread_id, self.thread_id)

        if run_input.run_id in self.runs:
            raise DuplicateRunId(run_input.run_id)

        parent_run_id = run_input.parent_run_id

        if parent_run_id is not None and parent_run_id not in self.runs:
            raise MissingParentRunId(parent_run_id)

        run = self.runs[run_input.run_id] = Run(run_input)
        return run


ThreadsByID = dict[str, Thread]


class UnknownThread(fastapi.HTTPException):
    def __init__(self, user_name: str, thread_id: str):
        self.user_name = user_name
        self.thread_id = thread_id
        message = f"Unknown thread: UUID {thread_id} for user {user_name}"
        super().__init__(status_code=404, detail=message)


class Threads:
    def __init__(self):
        self._lock = asyncio.Lock()
        # {user_name -> {thread_id: Thread}}
        self._threads = {}

    async def _find_user_threads(
        self,
        user_name: str,
    ) -> ThreadsByID:
        user_threads = self._threads.get(user_name)

        if user_threads is None:
            return {}

        return user_threads.copy()

    async def _find_thread(
        self,
        user_name: str,
        thread_id: str,
    ) -> Thread:
        user_threads = self._threads.get(user_name)

        if user_threads is None:
            raise UnknownThread(user_name, thread_id)

        thread = user_threads.get(thread_id)

        if thread is None:
            raise UnknownThread(user_name, thread_id)

        return thread

    async def user_threads(self, *, user_name: str) -> ThreadsByID:
        async with self._lock:
            return await self._find_user_threads(user_name)

    async def get_thread(
        self,
        *,
        user_name: str,
        thread_id: str,
    ) -> Thread:
        """Return the actual thread instance

        N.B.:  caller must treat the instance as read-only!
        """
        async with self._lock:
            return await self._find_thread(user_name, thread_id)

    async def new_thread(
        self,
        *,
        user_name: str,
        room_id: str,
        thread_name: str,
        thread_id: str = None,
    ) -> Thread:
        """Create a new thread"""
        if thread_id is None:
            thread_id = _make_thread_id()

        thread = Thread(
            thread_id=thread_id,
            name=thread_name,
            room_id=room_id,
        )

        async with self._lock:
            user_threads = self._threads.setdefault(user_name, {})
            user_threads[thread.thread_id] = thread

        return thread

    async def delete_thread(
        self,
        *,
        user_name: str,
        thread_id: str,
    ) -> None:
        """Remove a thread"""
        async with self._lock:
            threads = await self._find_user_threads(user_name)

            try:
                del threads[thread_id]
            except KeyError:
                raise UnknownThread(user_name, thread_id) from None

            self._threads[user_name] = threads


async def get_the_threads(request: fastapi.Request) -> Threads:
    return request.state.the_threads


depend_the_threads = fastapi.Depends(get_the_threads)


class EPSError(ValueError):
    pass


class RunInputAlreadySet(EPSError):
    def __init__(self):
        super().__init__("'run_input' already set, cannot be replaced")


class NotRunning(EPSError):
    def __init__(self, current_status):
        self.current_status = current_status
        super().__init__(f"Parser not in RUNNING state: {current_status}: ")


class InvalidRunStatusWithTarget(EPSError):
    def __init__(self, current_status, target_status):
        self.current_status = current_status
        self.target_status = target_status
        super().__init__(
            f"Invalid run status {current_status} "
            f"for transition to target status {target_status}"
        )


class StepAlreadyStarted(EPSError):
    def __init__(self, step_name):
        self.step_name = step_name
        super().__init__(f"Step {step_name} already started")


class StepNotStarted(EPSError):
    def __init__(self, step_name):
        self.step_name = step_name
        super().__init__(f"Step {step_name} not yet started")


class MessageAlreadyExists(EPSError):
    def __init__(self, message_id):
        self.message_id = message_id
        super().__init__(f"Message w/ ID {message_id} already exists")


class ToolCallDoesNotExist(EPSError):
    def __init__(self, tool_call_id):
        self.tool_call_id = tool_call_id
        super().__init__(f"Tool call w/ ID {tool_call_id} does not exist")


class ToolCallAlreadyExists(EPSError):
    def __init__(self, tool_call_id):
        self.tool_call_id = tool_call_id
        super().__init__(f"Tool call w/ ID {tool_call_id} already exists")


class MessageDoesNotExist(EPSError):
    def __init__(self, message_id):
        self.message_id = message_id
        super().__init__(f"Message w/ ID {message_id} does not exist")


class NoRunInput(EPSError):
    def __init__(self):
        super().__init__("Parser does not have a base 'run_input' assigned")


class RunStatus(enum.Enum):
    INITIALIZED = 0
    RUNNING = 1
    FINISHED = 2
    ERROR = -1


Messages = list[agui_core.Message]
MessagesByID = dict[str, agui_core.Message]
ToolCallInfo = tuple[agui_core.ToolCall, agui_core.Message | None]
ToolCallsByID = dict[str, ToolCallInfo]


@dataclasses.dataclass
class EventStreamParser:
    run_agent_input: dataclasses.InitVar[agui_core.RunAgentInput] = None

    _ = dataclasses.KW_ONLY

    _run_input: agui_core.RunAgentInput = None

    run_status: RunStatus = RunStatus.INITIALIZED
    active_steps: set[str] = dataclasses.field(default_factory=set)
    error_message: str = None
    error_code: str = None
    result: typing.Any = None

    state: dict = dataclasses.field(default_factory=dict)
    messages: Messages = dataclasses.field(default_factory=list)

    messages_by_id: MessagesByID = dataclasses.field(default_factory=dict)
    tool_calls_by_id: ToolCallsByID = dataclasses.field(default_factory=dict)

    def __post_init__(self, run_agent_input=None):
        if run_agent_input is not None:
            self.run_input = run_agent_input

    @property
    def run_input(self) -> agui_core.RunAgentInput:
        return self._run_input

    @run_input.setter
    def run_input(self, value: agui_core.RunAgentInput):
        if self._run_input is not None:
            raise RunInputAlreadySet()

        self._run_input = value
        self.state = value.state
        self.messages[:] = value.messages
        self.messages_by_id = {msg.id: msg for msg in value.messages}

    def _assert_running(self):
        if self.run_status != RunStatus.RUNNING:
            raise NotRunning(self.run_status)

    def _assert_run_status_for_target(self, expected, target):
        if self.run_status != expected:
            raise InvalidRunStatusWithTarget(
                self.run_status,
                target,
            )

    def _add_message(self, message: agui_core.BaseMessage):
        self.messages.append(message)
        self.messages_by_id[message.id] = message

    def __call__(self, event: agui_core.BaseEvent):
        match event.type:
            #
            #   Lifecycle events
            #
            case agui_core.EventType.RUN_STARTED:
                self._assert_run_status_for_target(
                    RunStatus.INITIALIZED, RunStatus.RUNNING
                )

                self.run_status = RunStatus.RUNNING

                if event.input is not None and self.run_input is None:
                    self.run_input = event.input

            case agui_core.EventType.RUN_FINISHED:
                self._assert_run_status_for_target(
                    RunStatus.RUNNING,
                    RunStatus.FINISHED,
                )

                self.run_status = RunStatus.FINISHED
                self.result = event.result

            case agui_core.EventType.RUN_ERROR:
                self._assert_run_status_for_target(
                    RunStatus.RUNNING,
                    RunStatus.ERROR,
                )

                self.run_status = RunStatus.ERROR
                self.error_message = event.message
                self.error_code = event.code

            case agui_core.EventType.STEP_STARTED:
                self._assert_running()

                if event.step_name in self.active_steps:
                    raise StepAlreadyStarted(event.step_name)

                self.active_steps.add(event.step_name)

            case agui_core.EventType.STEP_FINISHED:
                self._assert_running()

                if event.step_name not in self.active_steps:
                    raise StepNotStarted(event.step_name)

                self.active_steps.remove(event.step_name)

            #
            #   Text message events
            #
            case agui_core.EventType.TEXT_MESSAGE_START:
                self._assert_running()

                if event.message_id in self.messages_by_id:
                    raise MessageAlreadyExists(event.message_id)

                self._add_message(
                    agui_core.AssistantMessage(
                        id=event.message_id,
                        content="",
                    ),
                )

            case agui_core.EventType.TEXT_MESSAGE_CONTENT:
                self._assert_running()

                to_update = self.messages_by_id.get(event.message_id)
                if to_update is None:
                    raise MessageDoesNotExist(event.message_id)

                to_update.content += event.delta

            case agui_core.EventType.TEXT_MESSAGE_END:
                self._assert_running()

                if event.message_id not in self.messages_by_id:
                    raise MessageDoesNotExist(event.message_id)

            #
            #   Tool call events
            #
            case agui_core.EventType.TOOL_CALL_START:
                self._assert_running()

                if event.tool_call_id in self.tool_calls_by_id:
                    raise ToolCallAlreadyExists(event.tool_call_id)

                parent_id = event.parent_message_id
                if parent_id is not None:
                    parent_message = self.messages_by_id.get(parent_id)

                    if parent_message is None:
                        parent_message = agui_core.AssistantMessage(
                            id=parent_id,
                        )
                        self._add_message(parent_message)

                else:
                    parent_message = None

                self.tool_calls_by_id[event.tool_call_id] = (
                    agui_core.ToolCall(
                        id=event.tool_call_id,
                        function=agui_core.FunctionCall(
                            name=event.tool_call_name,
                            arguments="",
                        ),
                    ),
                    parent_message,
                )

            case agui_core.EventType.TOOL_CALL_ARGS:
                self._assert_running()

                if event.tool_call_id not in self.tool_calls_by_id:
                    raise ToolCallDoesNotExist(event.tool_call_id)

                tool_call, _ = self.tool_calls_by_id[event.tool_call_id]

                tool_call.function.arguments += event.delta

            case agui_core.EventType.TOOL_CALL_END:
                self._assert_running()

                if event.tool_call_id not in self.tool_calls_by_id:
                    raise ToolCallDoesNotExist(event.tool_call_id)

                tool_call, parent = self.tool_calls_by_id.pop(
                    event.tool_call_id,
                )

                if parent is not None:
                    parent.tool_calls.append(tool_call)

            case agui_core.EventType.TOOL_CALL_RESULT:
                self._assert_running()

                if event.tool_call_id not in self.tool_calls_by_id:
                    raise ToolCallDoesNotExist(event.tool_call_id)

                new_message = agui_core.ToolMessage(
                    id=event.message_id,
                    tool_call_id=event.tool_call_id,
                    content=event.content,
                )
                self._add_message(new_message)

            #
            #   State management events
            #
            case agui_core.EventType.STATE_DELTA:
                self._assert_running()

                new_state = jsonpatch.apply_patch(self.state, event.delta)

                self.state = new_state

            case agui_core.EventType.STATE_SNAPSHOT:
                self._assert_running()

                self.state = event.snapshot

            case agui_core.EventType.MESSAGES_SNAPSHOT:
                self._assert_running()

                self.messages = event.messages

            case agui_core.EventType.ACTIVITY_DELTA:
                self._assert_running()

                message = self.messages_by_id.get(event.message_id)

                if message is None:
                    message = agui_core.ActivityMessage(
                        id=event.message_id,
                        activity_type=event.activity_type,
                        content=jsonpatch.apply_patch({}, event.patch),
                    )
                    self._add_message(message)

                else:
                    message.activity_type = event.activity_type
                    new_state = jsonpatch.apply_patch(
                        message.content,
                        event.patch,
                    )
                    message.content = new_state

            case agui_core.EventType.ACTIVITY_SNAPSHOT:
                self._assert_running()

                message = self.messages_by_id.get(event.message_id)

                if message is None:
                    message = agui_core.ActivityMessage(
                        id=event.message_id,
                        activity_type=event.activity_type,
                        content=event.content,
                    )
                    self._add_message(message)

                else:
                    if not event.replace:
                        raise MessageAlreadyExists(event.message_id)

                    message.activity_type = event.activity_type
                    message.content = event.content

            case _:  # pragma: NO COVER
                pass

    async def parse_stream(
        self,
        stream: AGUI_EventIterator,
    ) -> AGUI_EventIterator:
        async for event in stream:
            self(event)
            yield event

    @property
    def as_run_agent_input(self) -> agui_core.RunAgentInput:
        if self.run_input is None:
            raise NoRunInput()

        return self.run_input.model_copy(
            update={
                "messages": self.messages,
                "state": self.state,
            },
        )
