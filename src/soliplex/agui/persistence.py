from __future__ import annotations

import copy
import datetime
import typing

import pydantic
import sqlalchemy
from ag_ui import core as agui_core
from sqlalchemy import orm as sqla_orm
from sqlalchemy import schema as sqla_schema
from sqlalchemy.ext import asyncio as sqla_asyncio
from sqlalchemy.sql import sqltypes as sqla_sqltypes

from soliplex.agui import util as agui_util

DeclarativeBase = sqla_orm.DeclarativeBase
ForeignKey = sqlalchemy.ForeignKey
Mapped = sqla_orm.Mapped
mapped_column = sqla_orm.mapped_column
relationship = sqla_orm.relationship

MESSAGE_DESERIALIZER = pydantic.TypeAdapter(agui_core.Message)

SYNC_MEMORY_ENGINE_URL = "sqlite://"
ASYNC_MEMORY_ENGINE_URL = "sqlite+aiosqlite://"

# Recommended naming convention used by Alembic, as various different database
# providers will autogenerate vastly different names making migrations more
# difficult. See: https://alembic.sqlalchemy.org/en/latest/naming.html
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

JSON_Mapped_From = dict[str, typing.Any]

metadata = sqla_schema.MetaData(naming_convention=NAMING_CONVENTION)


class Base(DeclarativeBase):
    metadata = metadata
    type_annotation_map = {
        JSON_Mapped_From: sqla_sqltypes.JSON,
    }


class Thread(Base):
    """Hold a set of AG-UI runs sharing the same 'thread_id'

    'thread_id': the AG-UI protocol level 'thread_id' (distinct from our
        actual primary key).

    'thread_metadata': optional thread metadata, stored in the
        'ThreadMetadata' table via an optional one-to-one relationship.

    'runs": stored in the 'Run' table via a one-to-many relationship.
    """

    __tablename__ = "thread"

    id_: Mapped[int] = mapped_column(primary_key=True)
    # created: Mapped[datetime.datetime] = mapped_column(
    #    default=sqla_func.now(),
    # )
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    thread_id: Mapped[str] = mapped_column(
        default=agui_util._make_uuid_str,
        index=True,
    )

    room_id: Mapped[str] = mapped_column(index=True)
    user_name: Mapped[str] = mapped_column(index=True)

    thread_metadata: Mapped[ThreadMetadata | None] = sqla_orm.relationship(
        back_populates="thread",
        cascade="all, delete",
        passive_deletes=True,
    )

    runs: Mapped[list[Run]] = relationship(
        back_populates="thread",
        order_by="Run.created",
        cascade="all, delete",
        passive_deletes=True,
    )


class ThreadMetadata(Base):
    """Hold optional metadata for an AG-UI thread

    'thread' is a one-to-one relationship to 'Thread' (but optional from
             the thread side).

    'name', required

    'description', optional
    """

    __tablename__ = "thread_metadata"

    id_: Mapped[int] = mapped_column(primary_key=True)
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    thread_id_: Mapped[int] = mapped_column(
        ForeignKey("thread.id_", ondelete="CASCADE"),
    )
    thread: Mapped[Thread] = relationship(back_populates="thread_metadata")

    name: Mapped[str] = mapped_column()
    description: Mapped[str | None] = mapped_column()


class Run(Base):
    """Hold information about an AG-UI runs.

    'run_id': the AG-UI protocol level 'run_id' (distinct from our
        actual primary key).

    'parent_id_': foreign key reference to parent run

    'parent': optional reference to the run's parent run.

    'children': list of the run's child runs.

    'run_metadata': optional run metadata, stored in the 'RunMetadata'
        table via an optional one-to-one relationship.

    'run_agent_input': holds optional AG-UI 'RunAgentInput' (runs can
        be created before the client posts an initial protocol-
        level run).
    """

    __tablename__ = "run"

    id_: Mapped[int] = mapped_column(primary_key=True)
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    thread_id_: Mapped[int] = mapped_column(
        ForeignKey("thread.id_", ondelete="CASCADE"),
    )
    thread: sqla_orm.Mapped[Thread] = relationship(
        back_populates="runs",
    )

    parent_id_: Mapped[int | None] = mapped_column(
        ForeignKey("run.id_", ondelete="CASCADE"),
    )
    parent: Mapped[Run | None] = relationship(
        back_populates="children",
        remote_side="Run.id_",
    )
    children: Mapped[list[Run]] = relationship(
        back_populates="parent",
        order_by="Run.created",
        cascade="all, delete",
        passive_deletes=True,
    )

    run_metadata: Mapped[RunMetadata | None] = relationship(
        back_populates="run",
        cascade="all, delete",
        passive_deletes=True,
    )

    run_agent_input: Mapped[RunAgentInput | None] = relationship(
        back_populates="run",
        cascade="all, delete",
        passive_deletes=True,
    )

    events: Mapped[list[RunEvent]] = relationship(
        back_populates="run",
        order_by="RunEvent.created",
        cascade="all, delete",
        passive_deletes=True,
    )

    run_id: Mapped[str] = mapped_column(
        default=agui_util._make_uuid_str,
        index=True,
    )

    @property
    def parent_run_id(self) -> str | None:
        return self.parent.run_id if self.parent is not None else None


class RunMetadata(Base):
    """Hold optional metadata for an AG-UI run

    'run' is a one-to-one relationship to 'Run' (but optional from
          the run side).

    'label', required
    """

    __tablename__ = "run_metadata"

    id_: Mapped[int] = mapped_column(primary_key=True)
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    run_id_: Mapped[int] = mapped_column(
        ForeignKey("run.id_", ondelete="CASCADE"),
    )
    run: Mapped[Run] = relationship(back_populates="run_metadata")

    label: Mapped[str] = mapped_column()


class RunAgentInput(Base):
    """Hold AG-UI 'RunAgentInput' data for a run

    'run' is a one-to-one relationship to 'Run' (but optional from
          the run side).

    'data' is the dumped state of the 'RunAgentInput'.
    """

    __tablename__ = "run_agent_input"

    id_: Mapped[int] = mapped_column(primary_key=True)
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    run_id_: Mapped[int | None] = mapped_column(
        ForeignKey("run.id_", ondelete="CASCADE"),
    )
    run: Mapped[Run] = relationship(
        back_populates="run_agent_input",
    )

    data: Mapped[JSON_Mapped_From] = mapped_column()

    @classmethod
    def from_agui_model(cls, run: Run, model: agui_core.RunAgentInput):
        return cls(run=run, data=model.model_dump())

    @property
    def thread_id(self) -> str:
        return self.data["thread_id"]

    @property
    def run_id(self) -> str:
        return self.data["run_id"]

    @property
    def parent_run_id(self) -> str:
        return self.data.get("parent_run_id")

    @property
    def state(self) -> typing.Any:
        return copy.deepcopy(self.data["state"])

    @property
    def messages(self) -> list[agui_core.Message]:
        return [
            MESSAGE_DESERIALIZER.validate_python(msg_data)
            for msg_data in self.data["messages"]
        ]

    @property
    def context(self) -> list[agui_core.Context]:
        return [
            agui_core.Context(**ctx_data) for ctx_data in self.data["context"]
        ]

    @property
    def tools(self) -> list[agui_core.Tool]:
        return [
            agui_core.Tool(**tool_data) for tool_data in self.data["tools"]
        ]

    @property
    def forwarded_props(self) -> typing.Any:
        return copy.deepcopy(self.data["forwarded_props"])


class RunEvent(Base):
    """Hold data for a singl AG-UI event within a run

    'run' is a many-to-one relationship to 'Run'

    'data' is the dumped state of the event.
    """

    __tablename__ = "run_event"

    id_: Mapped[int] = mapped_column(primary_key=True)
    created: Mapped[datetime.datetime] = mapped_column(
        default=agui_util._timestamp,
    )

    run_id_: Mapped[int] = mapped_column(
        ForeignKey("run.id_", ondelete="CASCADE"),
    )
    run: Mapped[Run] = relationship(back_populates="events")

    data: Mapped[JSON_Mapped_From] = mapped_column()

    @classmethod
    def from_agui_model(cls, run, model: agui_core.Event):
        return cls(run=run, data=model.model_dump())

    @property
    def type(self) -> str:
        return self.data["type"]


def get_session(
    engine_url=SYNC_MEMORY_ENGINE_URL,
    init_schema=False,
    **engine_kwargs,
):
    engine = sqlalchemy.create_engine(engine_url, **engine_kwargs)

    if init_schema:
        with engine.connect() as connection:
            Base.metadata.create_all(connection)

    return sqla_orm.Session(bind=engine)


async def get_async_session(
    engine_url=ASYNC_MEMORY_ENGINE_URL,
    init_schema=False,
    **engine_kwargs,
):
    engine = sqla_asyncio.create_async_engine(engine_url, **engine_kwargs)

    if init_schema:
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)

    return sqla_asyncio.AsyncSession(bind=engine)
