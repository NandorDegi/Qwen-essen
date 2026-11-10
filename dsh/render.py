"""Render the pilot's dsh configuration from the kit. Standard library only.

  python3 -I dsh/render.py KIT DSH_HOME

Values come from the environment (phase 55 exports them from config.env). One source for both
harnesses: the role prompts are the bodies of opencode/agents/<role>.md, the skills are
opencode/commands/<name>.md. Writes:
  $DSH_HOME/cordis.patch.yml               provider, default model, limits, MCP servers (all profiles)
  $DSH_HOME/AGENTS.md                      working rules
  $DSH_HOME/profiles/web/cordis.patch.yml  one agent preset per role, default `lead`
  $DSH_HOME/profiles/{web,headless}/package.json   bundles, including dsh-pilot-secrets
  $DSH_HOME/skills/<name>/SKILL.md         the demo procedures
"""
import json
import os
import re
import sys
from pathlib import Path

ROLES = ["lead", "coder", "tester", "reviewer", "browser-qa", "researcher"]
CHILDREN = [r for r in ROLES if r != "lead"]
READ_ONLY = {"reviewer", "researcher", "browser-qa"}
SKILLS = ["polyglot", "scada-twin", "ship", "review", "qa"]

# The child plugins of the web app's `standard` preset (dsh 0.2.2), without the delegation group
# and the plugin-manager tools. The lead adds the delegation group with a role allowlist.
COMMON = """\
- id: agent-instructions
  name: '@deepseek-ai/dsh-agent-instructions'
  config:
    maxBytes: 65536
- id: time-context
  name: '@deepseek-ai/dsh-time-context'
- id: tool-bash
  name: '@deepseek-ai/dsh-tool-bash'
- id: tool-fs
  name: '@deepseek-ai/dsh-tool-fs'
  config:
    applyPatch: false
- id: tool-fs-search
  name: '@deepseek-ai/dsh-tool-fs-search'
  config:
    sampleOverCapGlobResults: false
- id: tool-jobs
  name: '@deepseek-ai/dsh-tool-jobs'
- id: skill-filesystem
  name: '@deepseek-ai/dsh-skill-filesystem'
- id: tool-skill
  name: '@deepseek-ai/dsh-tool-skill'
- id: compaction
  name: cordis:group
  group: true
  isolate:
    compaction: true
    toolResultPruner: true
  config:
    - id: compaction-basic
      name: '@deepseek-ai/dsh-compaction-basic'
    - id: command-compact
      name: '@deepseek-ai/dsh-command-compact'
    - id: tool-result-pruner
      name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
      config:
        thresholdChars: 8192
        headChars: 4096
        tailChars: 1024
- id: tool-ask-user
  name: '@deepseek-ai/dsh-tool-ask-user'
- id: tool-todo
  name: '@deepseek-ai/dsh-tool-todo'
  config:
    allowParallelInProgress: true
- id: tool-web
  name: '@deepseek-ai/dsh-tool-web'
  config:
    fetch: true
    searchTimeoutMs: 60000
- id: present
  name: '@deepseek-ai/dsh-tool-present'
"""

DELEGATION = f"""\
- id: delegation
  name: cordis:group
  group: true
  isolate:
    workflowEngine: true
  config:
    - id: tool-subagent-control
      name: '@deepseek-ai/dsh-tool-subagent-control'
    - id: tool-subagent
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: spawn
        toolName: subagent
        agentPreset: coder
        allowedAgentPresets: {json.dumps(CHILDREN)}
"""

LEAD_NOTE = """
In this harness a subagent is the `subagent` tool: set `agent_preset` to coder, tester, reviewer,
browser-qa or researcher. Several `subagent` calls in one message run in parallel. Each call returns
at once; the child's final answer arrives as a completion notice. Where these instructions say
`task`, use `subagent`. Web search is `searxng_web_search`; the browser is the Playwright tools."""

CHILD_NOTE = """
You are a subagent: do the brief, then end with your report; it goes back to the lead.
Web search is `searxng_web_search`; the browser is the Playwright tools; `web_fetch` reads a page."""

RO_NOTE = """
This role is read-only. Do not create, edit or delete files, even though the tools allow it."""


def env(name):
    v = os.environ.get(name)
    if v is None:
        sys.exit(f"render.py: {name} is not set")
    return v


def split_md(path: Path):
    """(frontmatter dict of the simple `key: value` lines, body)."""
    text = path.read_text()
    m = re.match(r"\A---\n(.*?)\n---\n", text, flags=re.S)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        mm = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if mm and mm.group(2):
            meta[mm.group(1)] = mm.group(2).strip().strip("'\"")
    return meta, text[m.end():]


def indent(text, n):
    pad = " " * n
    return "".join(pad + line if line.strip() else line for line in text.splitlines(True))


def preset(kit: Path, role: str, order: int) -> str:
    meta, body = split_md(kit / "opencode" / "agents" / f"{role}.md")
    prompt = (f"You are the `{role}` agent of a small team of coding agents on an NVIDIA DGX Spark, "
              f"powered by the {{{{model}}}} model, which runs on this machine.\n\n{body.strip()}\n"
              + (LEAD_NOTE if role == "lead" else CHILD_NOTE) + (RO_NOTE if role in READ_ONLY else "") + "\n")
    plugins = ("- id: persona\n  name: '@deepseek-ai/dsh-persona'\n  config:\n    prefix: |\n"
               + indent(prompt, 6) + COMMON + (DELEGATION if role == "lead" else ""))
    return (f"    - id: preset-pilot-{role}\n"
            f"      name: '@deepseek-ai/dsh-agent-preset'\n"
            f"      config:\n"
            f"        id: {role}\n"
            f"        name: {json.dumps(role)}\n"
            f"        description: {json.dumps(meta.get('description', role))}\n"
            f"        order: {order}\n"
            f"        plugins:\n" + indent(plugins, 10))


def skill(kit: Path, name: str) -> str:
    meta, body = split_md(kit / "opencode" / "commands" / f"{name}.md")
    body = body.replace("$ARGUMENTS", "(the extra requirements the user gave with the request; may be none)")
    body = body.replace("`task` calls", "`subagent` calls")
    return (f"---\nname: {name}\ndescription: {json.dumps(meta.get('description', name))}\n---\n\n"
            f"{body.strip()}\n")


def package(profile: str, app_bundle: str, plugin_dir: Path) -> str:
    return json.dumps({
        "name": f"dsh-profile-{profile}", "private": True,
        "dependencies": {"dsh-pilot-secrets": f"link:{plugin_dir}"},
        "dsh": {"profile": {"bundles": ["@deepseek-ai/dsh-base", app_bundle, "dsh-pilot-secrets"]}},
    }, indent=2) + "\n"


def write(path: Path, text: str, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    tmp.chmod(mode)
    tmp.replace(path)


def main(kit: Path, home: Path):
    search_row = ""
    if env("SEARCH_ENABLED") == "1":
        search_row = (f"    - id: mcp-searxng\n      name: '@deepseek-ai/dsh-mcp-client'\n      config:\n"
                      f"        serverName: searxng\n        failOnStartupError: false\n"
                      f"        transport: streamable-http\n        url: http://127.0.0.1:{env('SEARCH_MCP_PORT')}/mcp\n"
                      f"        reconnect:\n          enabled: true\n")
    t = (kit / "dsh" / "cordis.patch.yml.tmpl").read_text()
    for k in ["LLM_PORT", "SERVED_NAME", "MAX_MODEL_LEN", "MAX_SEQS", "PILOT_LOGS", "PLAYWRIGHT_MODE"]:
        t = t.replace(f"@{k}@", env(k))
    t = t.replace("@MAX_OUTPUT@", env("OPENCODE_MAX_OUTPUT")).replace("@SEARCH_ROW@\n", search_row)
    if "@" in re.sub(r"'@deepseek-ai/[^']+'", "", t):
        sys.exit("render.py: a placeholder is left in cordis.patch.yml")
    write(home / "cordis.patch.yml", t)
    write(home / "AGENTS.md", (kit / "dsh" / "AGENTS.md").read_text())

    web = ("# The pilot's agent presets: one per role, the same roles and prompts as the opencode agents.\n"
           "# Written by phases/55-dsh.sh (dsh/render.py); edit the kit and rerun the phase.\n"
           "- id: agent-preset-registry\n  config:\n    default: lead\n- insert:\n"
           + "".join(preset(kit, r, i) for i, r in enumerate(ROLES)))
    write(home / "profiles" / "web" / "cordis.patch.yml", web)

    plugin_dir = home / "plugins" / "dsh-pilot-secrets"
    write(home / "profiles" / "web" / "package.json", package("web", "@deepseek-ai/dsh-web-app", plugin_dir))
    write(home / "profiles" / "headless" / "package.json", package("headless", "@deepseek-ai/dsh-headless", plugin_dir))
    for name in SKILLS:
        write(home / "skills" / name / "SKILL.md", skill(kit, name))
    print(f"{len(ROLES)} presets, {len(SKILLS)} skills, search {'on' if search_row else 'off'}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
