"""Track AGUI threads by user and room.

If / when we move to a "persistent" history store, this module should firewall
that choice away from the rest of the system.
"""

import asyncio
import dataclasses
import uuid
from collections import abc

import fastapi
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
