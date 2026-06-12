from __future__ import annotations

import fastapi

from soliplex import agui as agui_package
from soliplex import authn
from soliplex import authz as authz_package
from soliplex import installation
from soliplex import loggers
from soliplex import models
from soliplex import util
from soliplex import views

router = fastapi.APIRouter(tags=["stats"])

depend_the_installation = installation.depend_the_installation
depend_the_threads = agui_package.depend_the_threads
depend_the_authz = authz_package.depend_the_authz_policy
depend_the_user_claims = views.depend_the_user_claims
depend_the_logger = views.depend_the_logger


@util.logfire_span("GET /v1/rooms/{room_id}/stats")
@router.get("/v1/rooms/{room_id}/stats", summary="Get room activity stats")
async def get_room_stats(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    the_threads: agui_package.ThreadStorage = depend_the_threads,
    the_authz_policy: authz_package.AuthorizationPolicy = depend_the_authz,
    the_user_claims: authn.UserClaims = depend_the_user_claims,
    the_logger: loggers.LogWrapper = depend_the_logger,
) -> models.RoomStats:
    """Return aggregate activity stats for a room.

    Scoped to the requesting user's own threads. Currently reports the
    timestamp of the user's most recent message turn in the room; the
    payload is expected to grow with further metrics over time.
    """
    the_logger.debug(loggers.STATS_GET_ROOM_STATS)

    user_name = the_user_claims.get("preferred_username", "<unknown>")

    try:
        await the_installation.get_room_config(
            room_id=room_id,
            user=the_user_claims,
            the_authz_policy=the_authz_policy,
            the_logger=the_logger,
        )
    except KeyError:
        # auth error logged in 'get_room_config'; could also be a
        # genuinely missing room -- either way the user cannot see it.
        the_logger.exception(loggers.ROOM_UNKNOWN_ROOM_ID, room_id)
        raise fastapi.HTTPException(
            status_code=404,
            detail=loggers.ROOM_UNKNOWN_ROOM_ID % room_id,
        ) from None

    last_message_at = await the_threads.get_room_last_activity(
        user_name=user_name,
        room_id=room_id,
    )

    return models.RoomStats(
        room_id=room_id,
        last_message_at=last_message_at,
    )
