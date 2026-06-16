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

    last_activity = await the_threads.get_room_last_activity(
        user_name=user_name,
        room_id=room_id,
    )

    return models.RoomStats(
        room_id=room_id,
        last_activity=last_activity,
    )


@util.logfire_span("GET /v1/stats/rooms")
@router.get("/v1/stats/rooms", summary="Get activity stats for all rooms")
async def get_rooms_stats(
    request: fastapi.Request,
    the_threads: agui_package.ThreadStorage = depend_the_threads,
    the_user_claims: authn.UserClaims = depend_the_user_claims,
    the_logger: loggers.LogWrapper = depend_the_logger,
) -> dict[str, models.RoomStats]:
    """Return activity stats for every room the user has touched, keyed by
    room id, in a single query.

    Scoped to the requesting user's own threads (their own runs), so no
    per-room authorization round-trip is needed -- a user only has runs in
    rooms they have used. Rooms in which the user has no activity are
    omitted; the client treats an absent room as "no activity". Lets the
    lobby/room rail decorate a room list without an N+1 of per-room calls.
    """
    the_logger.debug(loggers.STATS_GET_ROOMS_STATS)

    user_name = the_user_claims.get("preferred_username", "<unknown>")

    activity = await the_threads.get_rooms_last_activity(user_name=user_name)

    return {
        room_id: models.RoomStats(room_id=room_id, last_activity=last_activity)
        for room_id, last_activity in activity.items()
    }
