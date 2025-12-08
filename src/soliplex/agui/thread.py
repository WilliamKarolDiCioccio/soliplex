"""Track AGUI threads by user and room.

If / when we move to a "persistent" history store, this module should firewall
that choice away from the rest of the system.
"""

import asyncio
import dataclasses
import datetime
import uuid

import fastapi
from ag_ui import core as agui_core

from soliplex import agui as agui_package

AGUI_Events = list[agui_core.BaseEvent]


def _make_uuid_str() -> str:
    return str(uuid.uuid4())


def _timestamp() -> datetime.datetime:
    return datetime.datetime.now(datetime.UTC)


timestamp = dataclasses.field(default_factory=_timestamp)


@dataclasses.dataclass(frozen=True)
class RunMetadata(agui_package.RunMetadata):
    label: str


@dataclasses.dataclass(frozen=True)
class Run(agui_package.Run):
    """Hold original input data and events for an AGUI run"""

    run_id: str = dataclasses.field(default_factory=_make_uuid_str)

    _: dataclasses.KW_ONLY

    metadata: RunMetadata = None
    _created: datetime.datetime = timestamp

    run_input: agui_core.RunAgentInput = None

    _events: AGUI_Events = dataclasses.field(
        default_factory=list,
    )

    @property
    def thread_id(self) -> str | None:
        if self.run_input is not None:
            return self.run_input.thread_id

    @property
    def parent_run_id(self) -> str | None:
        if self.run_input is not None:
            return self.run_input.parent_run_id

    @property
    def label(self) -> str | None:
        if self.metadata is not None:
            return self.metadata.label

    @property
    def created(self) -> datetime.datetime:
        return self._created

    def check_run_input(self, other_run_input: agui_core.RunAgentInput):
        """Raise if 'other_run_input' IDs do not match"""
        if self.thread_id != other_run_input.thread_id:
            raise agui_package.RunInputMismatch("thread_id")

        if self.run_id != other_run_input.run_id:
            raise agui_package.RunInputMismatch("run_id")

        if self.parent_run_id != other_run_input.parent_run_id:
            raise agui_package.RunInputMismatch("parent_run_id")

    def list_events(self) -> AGUI_Events:
        return self._events[:]


RunMap = dict[str, Run]


@dataclasses.dataclass(frozen=True)
class ThreadMetadata(agui_package.ThreadMetadata):
    name: str
    description: str = None


@dataclasses.dataclass(frozen=True)
class Thread(agui_package.Thread):
    """Hold a set of AGUI runs sharing the same 'thread_id'"""

    room_id: str

    thread_id: str = dataclasses.field(default_factory=_make_uuid_str)

    _: dataclasses.KW_ONLY

    metadata: ThreadMetadata = None

    _lock: asyncio.Lock = dataclasses.field(default_factory=asyncio.Lock)
    _created: datetime.datetime = timestamp
    _runs: RunMap = dataclasses.field(default_factory=dict)

    @property
    def created(self) -> datetime.datetime:
        return self._created

    def list_runs(self) -> list[Run]:
        return list(self._runs.values())


ThreadsByID = dict[str, Thread]


class Threads:
    def __init__(self):
        self._lock = asyncio.Lock()
        # {user_name -> {thread_id: Thread}}
        self._threads = {}

    async def _find_user_threads(
        self,
        user_name: str,
        room_id: str = None,
    ) -> ThreadsByID:
        user_threads = self._threads.get(user_name)

        if user_threads is None:
            return {}

        return {
            thread_id: thread
            for thread_id, thread in user_threads.items()
            if room_id is None or thread.room_id == room_id
        }

    async def _find_thread(
        self,
        user_name: str,
        thread_id: str,
    ) -> Thread:
        user_threads = self._threads.get(user_name)

        if user_threads is None:
            raise agui_package.UnknownThread(user_name, thread_id)

        thread = user_threads.get(thread_id)

        if thread is None:
            raise agui_package.UnknownThread(user_name, thread_id)

        return thread

    async def list_user_threads(
        self,
        *,
        user_name: str,
        room_id: str = None,
    ) -> list[Thread]:
        async with self._lock:
            found = await self._find_user_threads(user_name, room_id=room_id)
            return list(found.values())

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
        metadata: ThreadMetadata = None,
        initial_run: bool = True,
    ) -> Thread:
        """Create a new thread"""
        thread_id = _make_uuid_str()

        thread = Thread(
            thread_id=thread_id,
            room_id=room_id,
            metadata=metadata,
        )

        if initial_run:
            run_id = _make_uuid_str()
            thread._runs[run_id] = Run(
                run_id=run_id,
                run_input=agui_core.RunAgentInput(
                    thread_id=thread_id,
                    run_id=run_id,
                    parent_run_id=None,
                    state=None,
                    messages=[],
                    tools=[],
                    context=[],
                    forwarded_props=None,
                ),
            )

        async with self._lock:
            user_threads = self._threads.setdefault(user_name, {})
            assert thread_id not in user_threads

            user_threads[thread_id] = thread

        return thread

    async def update_thread(
        self,
        *,
        user_name: str,
        thread_id: str,
        metadata: ThreadMetadata = None,
    ) -> Thread:
        """Update thread instance with the given metadata, or None"""
        async with self._lock:
            before = await self._find_thread(user_name, thread_id)
            after = dataclasses.replace(before, metadata=metadata)
            self._threads[user_name][thread_id] = after
            return after

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
                raise agui_package.UnknownThread(
                    user_name,
                    thread_id,
                ) from None

            self._threads[user_name] = threads

    async def new_run(
        self,
        *,
        room_id: str,
        user_name: str,
        thread_id: str,
        metadata: RunMetadata = None,
        parent_run_id: str = None,
    ) -> Run:
        """Create a new run for the thread

        If 'parent_run_id' is passed, ensure it is valid.
        """
        async with self._lock:
            user_threads = await self._find_user_threads(
                room_id=room_id,
                user_name=user_name,
            )

            try:
                thread = user_threads[thread_id]
            except KeyError:
                raise agui_package.UnknownThread(
                    user_name,
                    thread_id,
                ) from None

            if parent_run_id is not None and parent_run_id not in thread._runs:
                raise agui_package.MissingParentRun(parent_run_id)

            run_id = _make_uuid_str()

            assert run_id not in thread._runs

            run = thread._runs[run_id] = Run(
                run_id=run_id,
                metadata=metadata,
                run_input=agui_core.RunAgentInput(
                    thread_id=thread.thread_id,
                    run_id=run_id,
                    parent_run_id=parent_run_id,
                    state=None,
                    messages=[],
                    tools=[],
                    context=[],
                    forwarded_props=None,
                ),
            )

            return run

    async def get_run(
        self,
        room_id: str,
        user_name: str,
        thread_id: str,
        run_id: str,
    ) -> Run:
        async with self._lock:
            user_threads = await self._find_user_threads(
                room_id=room_id,
                user_name=user_name,
            )

            try:
                thread = user_threads[thread_id]
            except KeyError:
                raise agui_package.UnknownThread(
                    user_name,
                    thread_id,
                ) from None

            try:
                return thread._runs[run_id]
            except KeyError:
                raise agui_package.UnknownRun(run_id) from None

    async def update_run(
        self,
        *,
        room_id: str,
        user_name: str,
        thread_id: str,
        run_id: str,
        metadata: RunMetadata = None,
    ) -> Run:
        """Update run instance with the given metadata, or None"""
        async with self._lock:
            user_threads = await self._find_user_threads(
                room_id=room_id,
                user_name=user_name,
            )

            try:
                thread = user_threads[thread_id]
            except KeyError:
                raise agui_package.UnknownThread(
                    user_name,
                    thread_id,
                ) from None

            try:
                before = thread._runs[run_id]
            except KeyError:
                raise agui_package.UnknownRun(run_id) from None

            after = dataclasses.replace(before, metadata=metadata)
            thread._runs[run_id] = after

            return after


async def get_the_threads(request: fastapi.Request) -> Threads:
    return request.state.the_threads


depend_the_threads = fastapi.Depends(get_the_threads)
