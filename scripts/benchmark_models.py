#!/usr/bin/env python3
"""Explicitly paid, sequential model comparison using the app's real prompt/context.

Not a Books UI test. Credentials stay in memory. One call per model per case;
no retries, warmups, temperature overrides or reasoning overrides.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MODELS = ["gemini-3.7-flash", "gemini-3.5-flash", "deepseek-v4-flash"]
CASES = [
    {"id": "word_bulldozer", "kind": "word", "selection": "bulldozer"},
    {"id": "word_fragile", "kind": "word", "selection": "fragile"},
    {"id": "phrase_liable", "kind": "phrase", "selection": "you’re liable to"},
    {"id": "sentence_truth", "kind": "sentence", "selection": "The truth is down there somewhere, but it’s fragile."},
    {"id": "sentence_run_by", "kind": "sentence", "selection": "can I run it by you?"},
]


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    path.chmod(0o600)


def production_inputs(config):
    """Compile the actual Swift matcher/system prompt, outside timed requests."""
    helper = r'''
import Foundation
let paragraphs = try JSONDecoder().decode([BookParagraph].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: String]]
let matches: [[String: Any]] = cases.map { item in
    let match = ReadingContext.match(item["selection"]!, in: paragraphs)
    return ["id": item["id"]!, "status": match.status, "paragraphs": match.paragraphs.map { ["id": $0.id, "text": $0.text] }]
}
let output: [String: Any] = ["systemPrompt": ReadingPreferences.systemPrompt, "matches": matches]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
'''
    with tempfile.TemporaryDirectory(prefix="bookask-benchmark-") as temporary:
        folder = Path(temporary)
        (folder / "main.swift").write_text(helper)
        write_json(folder / "cases.json", CASES)
        binary = folder / "inputs"
        subprocess.run(["swiftc", str(ROOT / "src/ReadingContext.swift"),
                        str(ROOT / "src/ReadingPreferences.swift"), str(folder / "main.swift"),
                        "-o", str(binary)], check=True, capture_output=True)
        return json.loads(subprocess.check_output([str(binary), config["contextFile"], str(folder / "cases.json")]))


def run_call(opener, config, key, payload, stream_path):
    result = {"answer": "", "reasoning": "", "first_content_s": None,
              "first_reasoning_s": None, "done": False, "finish_reason": None,
              "response_models": [], "status": "failed"}
    started = time.perf_counter()
    def deadline(_sig, _frame):
        raise TimeoutError("Benchmark wall-clock deadline (90 s)")
    prior = signal.signal(signal.SIGALRM, deadline)
    signal.setitimer(signal.ITIMER_REAL, 90)
    try:
        request = urllib.request.Request(config["baseURL"].rstrip("/") + "/chat/completions",
            method="POST", headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
            data=json.dumps(payload, ensure_ascii=False).encode())
        with stream_path.open("w") as trace, opener.open(request, timeout=90) as response:
            result["http_status"] = response.status
            result["headers_s"] = time.perf_counter() - started
            for raw in response:
                elapsed = time.perf_counter() - started
                line = raw.decode("utf-8").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                trace.write(json.dumps({"elapsed_s": elapsed, "data": data.replace(key, "[REDACTED]")}, ensure_ascii=False) + "\n")
                trace.flush()
                if data == "[DONE]":
                    result["done"] = True
                    break
                item = json.loads(data)
                if "error" in item:
                    raise RuntimeError(json.dumps(item["error"], ensure_ascii=False))
                model = item.get("model")
                if model and model not in result["response_models"]:
                    result["response_models"].append(model)
                if item.get("usage"):
                    result["usage"] = item["usage"]
                choice = (item.get("choices") or [{}])[0]
                if choice.get("finish_reason"):
                    result["finish_reason"] = choice["finish_reason"]
                delta = choice.get("delta", {})
                content = delta.get("content") or ""
                reasoning = delta.get("reasoning_content") or delta.get("reasoning") or ""
                if content:
                    if result["first_content_s"] is None and content.strip():
                        result["first_content_s"] = elapsed
                    result["answer"] += content
                    result["last_content_s"] = elapsed
                if reasoning:
                    if result["first_reasoning_s"] is None:
                        result["first_reasoning_s"] = elapsed
                    result["reasoning"] += reasoning
            if not result["done"] or not result["answer"].strip() or result["finish_reason"] == "length":
                raise RuntimeError("Missing complete answer, DONE, or truncated by token limit")
            result["status"] = "complete"
    except Exception as error:
        result["error"] = str(error).replace(key, "[REDACTED]")
        if isinstance(error, urllib.error.HTTPError):
            result["http_status"] = error.code
    finally:
        result["total_s"] = time.perf_counter() - started
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, prior)
    result["answer_words"] = len(result["answer"].split())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True, help="Authorize 15 paid API calls")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=False)
    config = json.loads((Path.home() / ".config/book-ask/config.json").read_text())
    key = json.loads(Path(config["authFile"]).read_text())[config["authProvider"]]["key"]
    preferences = plistlib.loads(subprocess.check_output(["defaults", "export", "com.zydtr.book-ask", "-"]))
    prompt = preferences["explanationPrompt"]
    inputs = production_inputs(config)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(config["baseURL"].rstrip("/") + "/models", headers={"Authorization": "Bearer " + key})
    with opener.open(request, timeout=30) as response:
        available = [x["id"] for x in json.load(response)["data"]]
    missing = set(MODELS) - set(available)
    if missing:
        raise RuntimeError("Missing models: " + str(sorted(missing)))
    fixture = []
    for case, match in zip(CASES, inputs["matches"]):
        assert case["id"] == match["id"]
        context = "\n\n".join(p["text"] for p in match["paragraphs"])
        initial = f'书名：{config["bookTitle"]}\n选中文字：\n<selection>\n{case["selection"]}\n</selection>\n上下文匹配状态：{match["status"]}\n<book_context>\n{context}\n</book_context>'
        fixture.append({**case, "match": match, "messages": [
            {"role": "system", "content": inputs["systemPrompt"]},
            {"role": "user", "content": initial}, {"role": "user", "content": prompt}]})
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT / "src/main.swift", ROOT / "src/ReadingContext.swift", ROOT / "src/ReadingPreferences.swift", Path(__file__)]}
    write_json(args.output / "inputs.json", {
        "started_at": datetime.datetime.now().astimezone().isoformat(),
        "gateway": config["baseURL"], "models": MODELS, "available_models": available,
        "saved_prompt": prompt, "fixtures": fixture, "source_hashes": hashes,
        "method": "15 sequential calls, rotated model order per case; no retries/warmups; stream=true, max_tokens=1800; no temperature or reasoning override; 90 s wall deadline; direct LAN HTTP, Python urllib streaming; not UI E2E"})
    for group, case in enumerate(fixture):
        order = MODELS[group % len(MODELS):] + MODELS[:group % len(MODELS)]
        for position, model in enumerate(order):
            call_id = f'{group + 1:02d}-{position + 1:02d}-{model}'
            print(json.dumps({"event": "start", "case": case["id"], "model": model}), flush=True)
            payload = {"model": model, "messages": case["messages"], "stream": True, "max_tokens": 1800}
            result = {"call_id": call_id, "case_id": case["id"], "model": model,
                      "started_at": datetime.datetime.now().astimezone().isoformat(),
                      **run_call(opener, config, key, payload, args.output / (call_id + ".sse.jsonl"))}
            write_json(args.output / (call_id + ".json"), result)
            with (args.output / "results.jsonl").open("a") as output:
                output.write(json.dumps(result, ensure_ascii=False) + "\n")
            print(json.dumps({k: result[k] for k in ["call_id", "status", "first_content_s", "total_s", "answer_words"]}), flush=True)


if __name__ == "__main__":
    main()
