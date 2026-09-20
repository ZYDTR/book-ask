#!/usr/bin/env python3
"""Opt-in real paid API probe, separate from the Apple Books UI acceptance."""
import json
import time
import urllib.request
from pathlib import Path

config = json.loads((Path.home() / ".config/book-ask/config.json").read_text())
key = json.loads(Path(config["authFile"]).read_text())[config["authProvider"]]["key"]
payload = {"model": config["model"], "stream": True, "max_tokens": 1800, "messages": [
    {"role": "user", "content": "请用中文简短解释英语 you're liable to 的常见意思，并给一个例句。"}]}
request = urllib.request.Request(config["baseURL"] + "/chat/completions", method="POST",
    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    data=json.dumps(payload).encode())
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
started = time.monotonic()
answer = ""
first = None
done = False
with opener.open(request, timeout=90) as response:
    for line in response:
        text = line.decode().strip()
        if not text.startswith("data:"):
            continue
        text = text[5:].strip()
        if text == "[DONE]":
            done = True
            break
        item = json.loads(text)
        if "error" in item:
            raise RuntimeError("Upstream stream returned an error")
        delta = (item.get("choices") or [{}])[0].get("delta", {}).get("content", "") or ""
        if delta and first is None:
            first = time.monotonic() - started
        answer += delta
result = {"test": "api_smoke_only_not_ui_e2e", "model": config["model"], "firstContentSeconds": first,
          "elapsedSeconds": time.monotonic() - started, "done": done, "answer": answer}
output = Path(__file__).parents[1] / "evidence/api_smoke.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
if not answer or not done:
    raise SystemExit("No complete content stream was returned")
print(json.dumps(result, ensure_ascii=False, indent=2))
