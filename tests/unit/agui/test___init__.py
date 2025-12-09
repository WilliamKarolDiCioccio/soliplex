from unittest import mock

import fastapi
import pytest

from soliplex import agui as agui_package


@pytest.mark.anyio
@mock.patch("soliplex.agui.persistence.ThreadStorage")
@mock.patch("sqlalchemy.ext.asyncio.AsyncSession")
async def test_get_the_threads(as_klass, ts_klass):
    engine = object()
    request = fastapi.Request(scope={"type": "http"})
    request.state.threads_engine = engine

    counter = 0

    async for the_threads in agui_package.get_the_threads(request):
        assert the_threads is ts_klass.return_value
        counter += 1

    assert counter == 1

    ts_klass.assert_called_once_with(
        as_klass.return_value.__aenter__.return_value,
    )

    as_klass.assert_called_once_with(bind=engine)
