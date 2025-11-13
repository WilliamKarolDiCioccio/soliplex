"""Track AGUI threads by user and room.

If / when we move to a "persistent" history store, this module should firewall
that choice away from the rest of the system.
"""

import asyncio
import dataclasses
import uuid

import fastapi
from ag_ui import core as agui_core
from pydantic_ai import messages as ai_messages

REQUEST_CONTEXT_PARTS = ("system-prompt", "user-prompt")
RESPONSE_CONTEXT_PARTS = ("text",)


# =============================================================================
#   In-memory storage for room-based AGUI threads.
# =============================================================================


def _make_thread_id() -> str:
    return str(uuid.uuid4())


@dataclasses.dataclass(frozen=True)
class Thread:
    """AG/UI thread w/ message history for a user / room."""

    thread_id: str = dataclasses.field(default_factory=_make_thread_id)
    room_id: str = dataclasses.field(kw_only=True)
    name: str | None = dataclasses.field(default=None, kw_only=True)


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


def _to_agui_message(
    m: ai_messages.ModelMessage,
    run_uuid: uuid.UUID,
) -> agui_core.BaseMessage | None:
    for part in m.parts:
        if isinstance(m, ai_messages.ModelRequest):
            if isinstance(part, ai_messages.UserPromptPart):
                assert isinstance(part.content, str)

                return agui_core.UserMessage(
                    id=str(run_uuid),
                    content=part.content,
                )

        elif isinstance(m, ai_messages.ModelResponse):
            if isinstance(part, ai_messages.TextPart):
                return agui_core.SystemMessage(
                    id=m.provider_response_id,
                    content=part.content,
                )

            elif isinstance(part, ai_messages.ThinkingPart):
                continue

            elif isinstance(part, ai_messages.ToolCallPart):
                continue

            else:  # pragma: NO COVER suppress spurious branch miss
                pass

        else:  # pragma: NO COVER suppress spurious branch miss
            pass

    # Return None for messages with no displayable content
    # (e.g., only ToolCallPart or ThinkingPart)
    return None
