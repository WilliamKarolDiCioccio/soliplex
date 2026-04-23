import json

import pytest

from soliplex.tools import genui


class TestFormField:
    def test_text_field(self):
        f = genui.FormField(label="Name", field_type="text")
        assert f.label == "Name"
        assert f.field_type == "text"
        assert f.required is True
        assert f.options is None

    def test_dropdown_with_options(self):
        f = genui.FormField(
            label="Priority",
            field_type="dropdown",
            options=["Low", "Medium", "High"],
        )
        assert f.field_type == "dropdown"
        assert f.options == ["Low", "Medium", "High"]

    def test_selector_with_options(self):
        f = genui.FormField(
            label="Topics",
            field_type="selector",
            options=["UI", "Performance", "Docs"],
            required=False,
        )
        assert f.field_type == "selector"
        assert f.options == ["UI", "Performance", "Docs"]
        assert f.required is False

    def test_invalid_field_type(self):
        with pytest.raises(Exception):
            genui.FormField(label="X", field_type="unknown")

    def test_email_field(self):
        f = genui.FormField(
            label="Email",
            field_type="email",
            placeholder="you@example.com",
        )
        assert f.field_type == "email"
        assert f.placeholder == "you@example.com"


class TestRenderForm:
    @pytest.mark.anyio
    async def test_returns_valid_json(self):
        result = await genui.render_form(
            title="Feedback",
            fields=[
                genui.FormField(label="Name", field_type="text"),
                genui.FormField(label="Score", field_type="number"),
            ],
        )
        data = json.loads(result)
        assert data["title"] == "Feedback"
        assert len(data["fields"]) == 2
        assert data["submit_label"] == "Submit"

    @pytest.mark.anyio
    async def test_custom_submit_label(self):
        result = await genui.render_form(
            title="Survey",
            fields=[genui.FormField(label="Comment", field_type="text")],
            submit_label="Send feedback",
        )
        data = json.loads(result)
        assert data["submit_label"] == "Send feedback"

    @pytest.mark.anyio
    async def test_selector_field_roundtrip(self):
        result = await genui.render_form(
            title="Topics",
            fields=[
                genui.FormField(
                    label="Areas",
                    field_type="selector",
                    options=["UI", "Performance"],
                )
            ],
        )
        data = json.loads(result)
        field = data["fields"][0]
        assert field["field_type"] == "selector"
        assert field["options"] == ["UI", "Performance"]
