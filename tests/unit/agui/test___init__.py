import fastapi
import pytest

from soliplex import agui as agui_package


@pytest.mark.anyio
async def test_get_the_threads():
    expected = object()
    request = fastapi.Request(scope={"type": "http"})
    request.state.the_threads = expected

    found = await agui_package.get_the_threads(request)

    assert found is expected
