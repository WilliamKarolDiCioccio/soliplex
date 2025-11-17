import fastapi
from fastapi import responses
from fastapi import security
from pydantic_ai.ui import ag_ui as ai_ag_ui

from soliplex import auth
from soliplex import installation
from soliplex import models
from soliplex import util

router = fastapi.APIRouter(tags=["rooms"])

depend_the_installation = installation.depend_the_installation


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

    # return await ai_ag_ui.handle_ag_ui_request(  # XXX: pydantic-ai==1.4.0
    return await ai_ag_ui.AGUIAdapter.dispatch_request(
        request=request,
        agent=agent,
        deps=agent_deps,
        # Note hook for future use:
        # on_complete=do_something_with_agent_run_result,
    )
