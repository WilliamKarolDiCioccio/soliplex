import dataclasses
import random
import time
import typing
from collections import abc

import pydantic_ai
from pydantic_ai import messages as ai_messages
from pydantic_ai import output as ai_output
from pydantic_ai import run as ai_run
from pydantic_ai import tools as ai_tools
from pydantic_ai.models import openai as openai_models
from pydantic_ai.providers import ollama as ollama_providers

from soliplex import config

JOKER_AGENT_PROMPT = """\
Use the `joke_factory` to generate some jokes, then choose the best. 

You must return just a single joke.
"""


def joker_agent_factory(agent_config):  # pragma NO COVER
    installation_config = agent_config._installation_config

    provider_base_url = installation_config.get_environment("OLLAMA_BASE_URL")
    provider_kw = {
        "base_url": f"{provider_base_url}/v1",
    }
    provider = ollama_providers.OllamaProvider(**provider_kw)

    joke_selection_agent = pydantic_ai.Agent(
        model=openai_models.OpenAIChatModel(
            model_name="qwen3:latest",
            provider=provider,
        ),
        system_prompt=JOKER_AGENT_PROMPT,
    )

    joke_generation_agent = pydantic_ai.Agent(
        model=openai_models.OpenAIChatModel(
            model_name="gpt-oss:latest",
            provider=provider,
        ),
        output_type=list[str],
    )

    @joke_selection_agent.tool
    async def joke_factory(
        ctx: pydantic_ai.RunContext[None], count: int, topic: str = None
    ) -> list[str]:
        if topic is None:
            prompt = f"Please generate {count} jokes."
        else:
            prompt = f"Please generate {count} jokes about {topic}."

        r = await joke_generation_agent.run(
            prompt,
            usage=ctx.usage,
        )
        return r.output

    return joke_selection_agent


NativeEvent = (
    ai_messages.AgentStreamEvent | ai_run.AgentRunResultEvent[typing.Any]
)
MessageHistory = typing.Sequence[ai_messages.ModelMessage]


@dataclasses.dataclass
class FauxAgent:
    agent_config: config.FactoryAgentConfig

    output_type = None

    async def run_stream_events(
        self,
        output_type: ai_output.OutputSpec[typing.Any] | None = None,
        message_history: MessageHistory | None = None,
        deferred_tool_results: pydantic_ai.DeferredToolResults | None = None,
        deps: ai_tools.AgentDepsT = None,
        # model=model,
        # model_settings=model_settings,
        # toolsets=toolsets,
        # builtin_tools=builtin_tools,
        # infer_name=infer_name,
        # usage_limits=usage_limits,
        # usage=usage,
        **kwargs,
    ) -> abc.AsyncIterator[NativeEvent]:
        think_part = ai_messages.ThinkingPart("I'm thinking")

        yield ai_messages.PartStartEvent(
            index=0,
            part=think_part,
        )
        last_message = message_history[-1]

        time.sleep(random.uniform(0.5, 2.0))

        if isinstance(last_message, ai_messages.ModelRequest):
            ups = [
                part
                for part in last_message.parts
                if isinstance(part, ai_messages.UserPromptPart)
            ]
            if ups:
                up = ups[0]
                delta = f"\n\nHmm, you asked {up.content}"
                think_part.content += delta
                yield ai_messages.PartDeltaEvent(
                    index=0,
                    delta=ai_messages.ThinkingPartDelta(
                        content_delta=delta,
                    ),
                )

            time.sleep(random.uniform(0.5, 2.0))

        yield ai_messages.PartEndEvent(
            index=0,
            part=think_part,
        )

        time.sleep(random.uniform(2.5, 3.0))

        text_part = ai_messages.TextPart("I don't know!")
        yield ai_messages.PartStartEvent(
            index=1,
            part=text_part,
        )
        yield ai_messages.PartEndEvent(
            index=1,
            part=text_part,
        )


def faux_agent_factory(agent_config: config.FactoryAgentConfig):
    return FauxAgent(agent_config)
