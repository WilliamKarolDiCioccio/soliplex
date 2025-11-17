import fastapi
from fastapi import responses
from fastapi import security
from pydantic_ai.ui import ag_ui as ai_ag_ui

from soliplex import agui
from soliplex import auth
from soliplex import installation
from soliplex import models
from soliplex import util

router = fastapi.APIRouter(tags=["rooms"])

depend_the_installation = installation.depend_the_installation
depend_the_threads = agui.depend_the_threads


@util.logfire_span("POST /v1/rooms/{room_id}/agui")
@router.post("/v1/rooms/{room_id}/agui")
async def post_room_agui(
    request: fastapi.Request,
    room_id: str,
    the_installation: installation.Installation = depend_the_installation,
    the_threads: agui.Threads = depend_the_threads,
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
    user_name = user_profile.preferred_username

    try:
        agent = the_installation.get_agent_for_room(room_id, user)
    except KeyError:
        raise fastapi.HTTPException(
            status_code=404,
            detail=f"No such room: {room_id}",
        ) from None

    agui_adapter = await ai_ag_ui.AGUIAdapter.from_request(
        request=request,
        agent=agent,
    )

    run_input = agui_adapter.run_input

    thread_id = run_input.thread_id

    try:
        thread = await the_threads.get_thread(
            user_name=user_name,
            thread_id=thread_id,
        )
    except agui.UnknownThread:
        thread = await the_threads.new_thread(
            user_name=user_name,
            room_id=room_id,
            thread_id=thread_id,
        )

    run = await thread.new_run(run_input)

    agent_deps = models.AgentDependencies(
        the_installation=the_installation,
        user=user_profile,
    )

    agent_stream = agui_adapter.run_stream(deps=agent_deps)

    esp = agui.EventStreamParser(run_input, run=run)
    esp_stream = esp.parse_stream(agent_stream)
    sse_stream = agui_adapter.encode_stream(esp_stream)

    return responses.StreamingResponse(
        sse_stream,
        media_type=agui_adapter.accept,
    )
