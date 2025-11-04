"""Track AGUI interactions by user and room.

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
#   In-memory storage for room-based user interactions.
# =============================================================================


def _to_aguix_message(
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


@dataclasses.dataclass(frozen=True)
class Interaction:
    """AG/UI interaction w/ message history for a user / room."""

    room_id: str
    message_history: tuple[agui_core.BaseMessage]
    name: str | None
    aguix_uuid: uuid.UUID = dataclasses.field(
        default_factory=uuid.uuid4,
    )


InteractionsByUUID = dict[str, Interaction]


class UnknownInteraction(fastapi.HTTPException):
    def __init__(self, user_name: str, aguix_uuid: str):
        self.user_name = user_name
        self.aguix_uuid = aguix_uuid
        message = (
            f"Unknown interaction: UUID {aguix_uuid} for user {user_name}"
        )
        super().__init__(status_code=404, detail=message)


class Interactions:
    def __init__(self):
        self._lock = asyncio.Lock()
        # {user_name -> {aguix_uuid: Interaction}}
        self._interactions = {}

    async def _find_user_interactions(
        self,
        user_name: str,
    ) -> InteractionsByUUID:
        user_interactions = self._interactions.get(user_name)

        if user_interactions is None:
            return {}

        return user_interactions.copy()

    async def _find_interaction(
        self,
        user_name: str,
        aguix_uuid: str,
    ) -> Interaction:
        user_interactions = self._interactions.get(user_name)

        if user_interactions is None:
            raise UnknownInteraction(user_name, aguix_uuid)

        interaction = user_interactions.get(aguix_uuid)

        if interaction is None:
            raise UnknownInteraction(user_name, aguix_uuid)

        return interaction

    async def user_interactions(self, user_name: str) -> InteractionsByUUID:
        async with self._lock:
            return await self._find_user_interactions(user_name)

    async def get_interaction(
        self,
        user_name: str,
        aguix_uuid: str,
    ) -> Interaction:
        """Return the actual interaction instance

        N.B.:  caller must treat the instance as read-only!
        """
        async with self._lock:
            return await self._find_interaction(user_name, aguix_uuid)

    async def new_interaction(
        self,
        user_name: str,
        room_id: str,
        interaction_name: str,
        new_messages: list[agui_core.BaseMessage] = (),
    ) -> Interaction:
        """Create a new interaction"""
        interaction = Interaction(
            name=interaction_name,
            room_id=room_id,
            message_history=tuple(new_messages),
        )

        async with self._lock:
            user_interactions = self._interactions.setdefault(user_name, {})
            user_interactions[interaction.aguix_uuid] = interaction

        return interaction

    async def append_to_interaction(
        self,
        user_name: str,
        aguix_uuid: str,
        new_messages: list[agui_core.BaseMessage],
    ) -> None:
        """Append messsages to history for a interaction"""
        async with self._lock:
            user_interactions = self._interactions.setdefault(user_name, {})
            interaction = user_interactions.get(aguix_uuid)

            if interaction is None:
                raise UnknownInteraction(user_name, aguix_uuid)

            history = list(interaction.message_history)
            history.extend(new_messages)

            user_interactions[interaction.aguix_uuid] = dataclasses.replace(
                interaction,
                message_history=tuple(history),
            )

    async def delete_interaction(
        self,
        user_name: str,
        aguix_uuid: uuid.UUID,
    ) -> None:
        """Remove a interaction"""
        async with self._lock:
            interactions = await self._find_user_interactions(user_name)

            try:
                del interactions[aguix_uuid]
            except KeyError:
                raise UnknownInteraction(user_name, aguix_uuid) from None

            self._interactions[user_name] = interactions


async def get_the_interactions(request: fastapi.Request) -> Interactions:
    return request.state.the_interactions


depend_the_interactions = fastapi.Depends(get_the_interactions)
