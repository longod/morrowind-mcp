"""Reusable prompts/get cases."""

from case_api import CaseDefinition


def PromptCase(case_id: str, prompt_name: str) -> CaseDefinition:
    """Build a prompt retrieval case with the shared messages response contract."""
    return CaseDefinition(
        id=case_id,
        operation={"method": "prompts/get", "prompt_name": prompt_name},
        assertions=({"pointer": "/result/messages", "operator": "exists"},),
    )


CASES = {
    "prompt-get-loar": PromptCase("prompt-get-loar", "mw-loar"),
    "prompt-get-role": PromptCase("prompt-get-role", "mw-role"),
    "prompt-get-todo": PromptCase("prompt-get-todo", "mw-todo"),
    "prompt-get-translate": PromptCase("prompt-get-translate", "mw-translate"),
    "prompt-get-walkthrough": PromptCase("prompt-get-walkthrough", "mw-walkthrough"),
}