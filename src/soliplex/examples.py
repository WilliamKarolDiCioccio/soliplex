import pydantic_ai
from pydantic_ai.models import openai as openai_models
from pydantic_ai.providers import ollama as ollama_providers

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
