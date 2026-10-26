"""Filters for o2c-app/.env, read the way platform/kind/secrets.sh reads it: KEY=value,
optional `export`, optional single or double quotes around the whole value, no
interpolation, comments and blank lines ignored."""

import re

_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
_QUOTED = re.compile(r"""^(['"])(.*)\1\s*$""")


def dotenv(text):
    """{KEY: value} of a .env file's text."""
    values = {}
    for line in text.splitlines():
        match = _LINE.match(line.rstrip("\r"))
        if not match or line.lstrip().startswith("#"):
            continue
        value = match.group(2)
        quoted = _QUOTED.match(value)
        values[match.group(1)] = quoted.group(2) if quoted else value
    return values


def dotenv_without(text, prefix):
    """The .env text without the lines of keys that start with `prefix`."""
    kept = [
        line
        for line in text.splitlines()
        if not ((m := _LINE.match(line.rstrip("\r"))) and m.group(1).startswith(prefix))
    ]
    return "\n".join(kept) + "\n"


class FilterModule:
    def filters(self):
        return {"dotenv": dotenv, "dotenv_without": dotenv_without}
