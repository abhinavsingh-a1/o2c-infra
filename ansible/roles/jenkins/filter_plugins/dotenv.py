"""Filters for o2c-app/.env, read the way platform/kind/secrets.sh reads it: KEY=value,
optional `export`, optional single or double quotes around the whole value, no
interpolation, comments and blank lines ignored."""

import re

_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
_QUOTED = re.compile(r"""^\s*(['"])(.*)\1\s*$""", re.DOTALL)


def _value(raw):
    """A value without trailing CRs and one pair of surrounding quotes."""
    value = raw.rstrip("\r")
    quoted = _QUOTED.match(value)
    return quoted.group(2) if quoted else value


def dotenv(text):
    """{KEY: value} of a .env file's text."""
    values = {}
    for line in text.split("\n"):
        line = line.rstrip("\r")
        match = _LINE.match(line)
        if not match or line.lstrip().startswith("#"):
            continue
        values[match.group(1)] = _value(match.group(2))
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
