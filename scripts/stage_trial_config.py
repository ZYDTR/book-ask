#!/usr/bin/env python3
"""Stage only an explicitly supplied trial profile, never local user credentials."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit


def validate(value):
    if not isinstance(value, dict) or set(value) - {"baseURL", "model", "apiKey", "thinkingLevel"}:
        raise ValueError("Trial profile accepts only baseURL, model, apiKey and thinkingLevel; private file locators are forbidden.")
    if any(not isinstance(item, str) for item in value.values()):
        raise ValueError("Trial profile values must be strings.")
    result = {"baseURL": value.get("baseURL", ""), "model": value.get("model", "")}
    if value.get("apiKey"):
        result["apiKey"] = value["apiKey"]
    if "thinkingLevel" in value:
        if value["thinkingLevel"] not in {"minimal", "low", "medium", "high"}:
            raise ValueError("Invalid Gemini thinking level.")
        result["thinkingLevel"] = value["thinkingLevel"]
    if any(result.values()):
        url = urlsplit(result["baseURL"])
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or url.query or url.fragment or not result["model"] or not result.get("apiKey")):
            raise ValueError("Configured trial profiles require an HTTPS URL, model and dedicated trial key.")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        profile = validate(json.loads(args.source.read_text()))
    except (OSError, ValueError):
        raise SystemExit("Cannot stage trial profile. Use an empty profile or HTTPS baseURL/model/apiKey only; no private file paths.")
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n")
    # This is an intentionally distributed, restricted trial token. App bundle
    # resources must be readable by the user who installs the DMG on another Mac.
    # The developer's original private source file keeps its own permissions.
    args.destination.chmod(0o644)
    print("Trial profile staged: " + ("configured" if profile.get("apiKey") else "service not configured"))


if __name__ == "__main__":
    main()
