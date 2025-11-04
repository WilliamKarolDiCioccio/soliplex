import fastapi
from fastapi import responses
from fastapi import security
from pydantic_ai import ag_ui as ai_ag_ui

from soliplex import auth
from soliplex import installation
from soliplex import mcp_auth
from soliplex import models
from soliplex import util

router = fastapi.APIRouter(tags=["rooms"])

depend_the_installation = installation.depend_the_installation


@util.logfire_span("GET /v1/rooms")
@router.get("/v1/rooms", summary="Get available rooms")
async def get_rooms(
    request: fastapi.Request,
    the_installation: installation.Installation = depend_the_installation,
    token: security.HTTPAuthorizationCredentials = auth.oauth2_predicate,
) -> models.ConfiguredRooms:
    """Return a manifest of the rooms available to the user"""
    user = auth.authenticate(the_installation, token)
    room_configs = the_installation.get_room_configs(user)

    def _key(item):
        key, value = item
        return value.sort_key

    rc_items = sorted(room_configs.items(), key=_key)

    return {
        room_id: models.Room.from_config(room) for room_id, room in rc_items
    }


@util.logfire_span("GET /v1/rooms/{room_id}")
@router.get("/v1/rooms/{room_id}")
async def get_room(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    token: security.HTTPAuthorizationCredentials = auth.oauth2_predicate,
) -> models.Room:
    """Return a single room's configuration"""
    user = auth.authenticate(the_installation, token)

    try:
        room_config = the_installation.get_room_config(room_id, user)
    except KeyError:
        raise fastapi.HTTPException(
            status_code=404,
            detail=f"No such room: {room_id}",
        ) from None

    return models.Room.from_config(room_config)


@util.logfire_span("GET /v1/rooms/{room_id}/bg_image")
@router.get(
    "/v1/rooms/{room_id}/bg_image",
    response_class=responses.FileResponse,
)
async def get_room_bg_image(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    token: security.HTTPAuthorizationCredentials = auth.oauth2_predicate,
) -> str:  # file path, converted to file response by FastAPI
    """Return a room's background image"""
    user = auth.authenticate(the_installation, token)

    try:
        room_config = the_installation.get_room_config(room_id, user)
    except KeyError:
        raise fastapi.HTTPException(
            status_code=404,
            detail=f"No such room: {room_id}",
        ) from None

    logo_image = room_config.get_logo_image()

    if logo_image is None:
        raise fastapi.HTTPException(
            status_code=404,
            detail="No image for room",
        )

    return str(logo_image)


@util.logfire_span("GET /v1/rooms/{room_id}/mcp_token")
@router.get("/v1/rooms/{room_id}/mcp_token")
async def get_room_mcp_token(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    token: security.HTTPAuthorizationCredentials = auth.oauth2_predicate,
) -> models.MCPToken:
    """Return a token for use in an MCP client addressing the room"""
    user = auth.authenticate(the_installation, token)

    try:
        the_installation.get_room_config(room_id, user=user)
    except ValueError as e:
        raise fastapi.HTTPException(
            status_code=404,
            detail=str(e),
        ) from None

    secret = the_installation.get_secret("URL_SAFE_TOKEN_SECRET")
    token = mcp_auth.generate_url_safe_token(secret, room_id, **user)
    return models.MCPToken(room_id=room_id, mcp_token=token)


@util.logfire_span("POST /v1/rooms/{room_id}/agui")
@router.post("/v1/rooms/{room_id}/agui")
async def post_room_agui(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    token: security.HTTPAuthorizationCredentials = auth.oauth2_predicate,
) -> responses.StreamingResponse:
    """Process an AGUI interaction request"""
    user = auth.authenticate(the_installation, token)

    user_profile = models.UserProfile(
        given_name=user.get("given_name", "<unknown>"),
        family_name=user.get("family_name", "<unknown>"),
        email=user.get("email", "<unknown>"),
        preferred_username=user.get("preferred_username", "<unknown>"),
    )

    try:
        agent = the_installation.get_agent_for_room(room_id, user)
    except KeyError:
        raise fastapi.HTTPException(
            status_code=404,
            detail=f"No such room: {room_id}",
        ) from None

    agent_deps = models.AgentDependencies(
        the_installation=the_installation,
        user=user_profile,
    )

    # 'pydantic-ai 1.4.0' doesn't have 'AGUIAdapter'.
    # return await ai_ag_ui.AGUIAdapter.dispatch_request(
    return await ai_ag_ui.handle_ag_ui_request(
        request=request,
        agent=agent,
        deps=agent_deps,
        # Note hook for future use:
        # on_complete=do_something_with_agent_run_result,
    )
