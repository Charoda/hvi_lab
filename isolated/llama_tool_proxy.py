#!/usr/bin/env python3
# Прокси-переводчик между Qwen Code CLI и локальным llama-server.
#
# Провайдер OpenAI в Qwen Code исполняет инструменты ТОЛЬКО из
# структурированных `tool_calls` (finish_reason == "tool_calls"). Локальная
# модель, следуя текстовой инструкции системного промпта CLI, отвечает
# вызовами инструментов в ТЕКСТОВОМ формате (открывающий тег с именем
# инструмента, вложенные теги параметров, закрывающий парный тег — см.
# константы ниже). Без перевода провайдер считает такой ответ финальным
# текстом, и сессия агента обрывается после первого «хода».
#
# Прокси слушает порт агента (11434), проксирует всё на внутренний
# llama-server (11435) и для /v1/chat/completions переписывает ответ:
# найденные текстовые блоки вызовов превращаются в нативные OpenAI
# tool_calls. Понимает и запасной формат модели — JSON-объект вызова
# в блоке кода. Ответ полностью буферизуется (инференс на CPU и так
# медленный, дополнительной задержкой можно пренебречь), клиенту во время
# буферизации шлются SSE-комментарии-пинги, чтобы соединение не умирало.
#
# Запуск:  python3 llama_tool_proxy.py [--listen 11434] [--upstream 11435]
# Только стандартная библиотека.
import argparse
import http.client
import json
import queue
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# Текстовый формат инструментов из системного промпта Qwen Code.
# Собраны через \x3c («<»), чтобы файл не содержал «живых» тегов.
_FUNC_OPEN = re.compile(
    r"\x3cfunction=([A-Za-z_][\w.-]*)>(.*?)\x3c/function>", re.S)
_PARAM = re.compile(
    r"\x3cparameter=([A-Za-z_][\w.-]*)>(.*?)\x3c/parameter>", re.S)
# Запасные варианты, которые модель выдаёт вместо основного формата:
# JSON-объект вызова в блоке кода (```json ... ```) или прямо в тексте.
_JSON_FENCE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.S)
_JSON_CALL = re.compile(
    r'\{\s*"name"\s*:\s*"([\w.-]+)"\s*,\s*"(?:arguments|parameters)"\s*:\s*'
    r'(\{.*?\})\s*\}', re.S)

_PASS_HEADERS = ("content-type", "accept", "authorization")
_LOG_FH = sys.stderr


def log(msg):
    _LOG_FH.write("[toolproxy] %s\n" % msg)
    _LOG_FH.flush()


def _parse_value(raw):
    raw = raw.strip()
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        return raw


def parse_text_tool_calls(text):
    """Список вызовов [(имя, {параметр: значение}, весь блок)].

    Понимает основной формат (теги с именем инструмента и параметрами) и
    запасной — JSON-объект вызова в блоке кода или прямо в тексте.
    """
    calls = []
    for m in _FUNC_OPEN.finditer(text):
        name, body = m.group(1), m.group(2)
        args = {}
        for pm in _PARAM.finditer(body):
            args[pm.group(1)] = _parse_value(pm.group(2))
        calls.append((name, args, m.group(0)))
    if calls:
        return calls
    candidates = [m.group(1) for m in _JSON_FENCE.finditer(text)]
    candidates.append(text)  # вызов без блока кода
    for blob in candidates:
        for m in _JSON_CALL.finditer(blob):
            try:
                args = json.loads(m.group(2))
            except ValueError:
                continue
            if isinstance(args, dict):
                calls.append((m.group(1), args, m.group(0)))
        if calls:
            break
    return calls


def _read_upstream(resp, q):
    """Читает тело ответа в отдельном потоке: сокет-таймауты на основном
    потоке ломали недопустимое для повторного чтения состояние http.client,
    а потоку-читателю таймауты не нужны (общий потолок — на соединении)."""
    try:
        while True:
            piece = resp.read(65536)
            if not piece:
                break
            q.put(piece)
    except Exception as e:  # noqa: BLE001 — любую ошибку чтения — в очередь
        q.put(e)
    q.put(None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = ("127.0.0.1", 11435)

    def log_message(self, *args):  # http.server шумит в тот же лог
        pass

    def _read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _upstream(self, body):
        host, port = self.upstream
        req = Request("http://%s:%d%s" % (host, port, self.path),
                      data=body or None, method=self.command)
        for k, v in self.headers.items():
            if k.lower() in _PASS_HEADERS:
                req.add_header(k, v)
        return urlopen(req, timeout=7200)

    def _send_all(self, status, content_type, payload):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _forward(self, body):
        """Прозрачный проход для не-чат-эндпоинтов."""
        try:
            r = self._upstream(body)
            data = r.read()
            self._send_all(r.status, r.headers.get("Content-Type",
                           "application/json"), data)
        except HTTPError as e:
            self._send_all(e.code, "application/json",
                           e.read() or b'{"error":"upstream"}')
        except (URLError, socket.timeout, ConnectionError) as e:
            log("upstream error: %s" % e)
            self._send_all(502, "application/json",
                           b'{"error":"upstream unavailable"}')

    def _send_bad_gateway(self):
        self._send_all(502, "application/json",
                       b'{"error":"upstream unavailable"}')

    def _handle_chat(self, body):
        """Чат-запрос: буферизуем ответ, текстовые вызовы -> tool_calls."""
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            payload = {}
        stream = bool(payload.get("stream"))
        if stream:
            # Стриминг обрабатывается отдельно: нужны немедленные заголовки
            # и keep-alive, пока ответ буферизуется ради возможной перезаписи.
            self._rewrite_stream(body)
            return
        try:
            resp = self._upstream(body)
        except (HTTPError, URLError, socket.timeout, ConnectionError) as e:
            log("chat upstream error: %s" % e)
            self._send_bad_gateway()
            return
        if not stream:
            data = resp.read()
            try:
                obj = json.loads(data.decode("utf-8"))
                self._rewrite_nonstream(obj)
                data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            except (ValueError, UnicodeDecodeError):
                pass
            self._send_all(resp.status, "application/json", data)
            return
        try:
            self._rewrite_stream(body)
        except (BrokenPipeError, ConnectionResetError):
            log("client disconnected mid-stream")

    # --- переписывание ответа -------------------------------------------

    def _rewrite_nonstream(self, obj):
        try:
            msg = obj["choices"][0]["message"]
        except (KeyError, IndexError, TypeError):
            return
        text = msg.get("content") or ""
        calls = parse_text_tool_calls(text)
        if not calls:
            return
        log("rewriting non-stream answer: %d tool call(s)" % len(calls))
        prefix = text[:text.find(calls[0][2])].strip()
        if prefix:
            msg["content"] = prefix
        else:
            msg["content"] = None
        msg["tool_calls"] = [{
            "id": "call_local_%d" % i,
            "type": "function",
            "function": {"name": name,
                         "arguments": json.dumps(args, ensure_ascii=False)},
        } for i, (name, args, _block) in enumerate(calls)]
        obj["choices"][0]["finish_reason"] = "tool_calls"

    def _rewrite_stream(self, body):
        host, port = self.upstream
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() in _PASS_HEADERS}
        try:
            conn = http.client.HTTPConnection(host, port, timeout=7200)
            conn.request(self.command, self.path, body=body or None,
                         headers=headers)
            resp = conn.getresponse()
        except (OSError, http.client.HTTPException) as e:
            log("chat upstream connect error: %s" % e)
            self._send_bad_gateway()
            return
        if resp.status != 200:
            data = resp.read()
            conn.close()
            self._send_all(resp.status,
                           resp.getheader("Content-Type", "application/json"),
                           data or b'{"error":"upstream"}')
            return

        # Отвечаем клиенту СРАЗУ: пока ответ буферизуется ради возможной
        # перезаписи, соединение не должно умирать от тишины — при буферизации
        # шлём SSE-комментарии (см. ниже).
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b": proxy buffering\n\n")
        self.wfile.flush()

        q = queue.Queue()
        threading.Thread(target=_read_upstream, args=(resp, q),
                         daemon=True).start()
        pieces = []
        while True:
            try:
                item = q.get(timeout=5.0)
            except queue.Empty:
                try:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    log("client gone while buffering")
                    conn.close()
                    return
                continue
            if item is None:
                break
            if isinstance(item, Exception):
                log("upstream read error: %s" % item)
                break
            pieces.append(item)
        conn.close()

        sse = b"".join(pieces).decode("utf-8", "replace")
        chunks = []
        for line in sse.splitlines():
            line = line.strip()
            if line.startswith("data:") and line[5:].strip() != "[DONE]":
                try:
                    chunks.append(json.loads(line[5:]))
                except ValueError:
                    pass
        text = "".join(
            (delta.get("content") or "")
            for c in chunks
            for delta in [((c.get("choices") or [{}])[0]).get("delta", {})]
        )
        calls = parse_text_tool_calls(text)
        rid = None
        model = None
        for c in chunks:
            rid = c.get("id") or rid
            model = c.get("model") or model

        def out(obj):
            self.wfile.write(
                ("data: %s\n\n" % json.dumps(obj, ensure_ascii=False))
                .encode("utf-8"))

        if not calls:
            # Ничего переводить: отдаём накопленное как есть.
            for c in chunks:
                out(c)
            self.wfile.write(b"data: [DONE]\n\n")
            return

        log("rewriting streamed answer: %d tool call(s): %s"
            % (len(calls), ", ".join(name for name, _a, _b in calls)))
        prefix = text[:text.find(calls[0][2])].strip()
        if prefix:
            out({"id": rid, "model": model, "object": "chat.completion.chunk",
                 "choices": [{"index": 0, "finish_reason": None,
                              "delta": {"role": "assistant",
                                        "content": prefix}}]})
        for i, (name, args, _block) in enumerate(calls):
            out({"id": rid, "model": model, "object": "chat.completion.chunk",
                 "choices": [{"index": 0, "finish_reason": None,
                              "delta": {"tool_calls": [{
                                  "index": i,
                                  "id": "call_local_%d" % i,
                                  "type": "function",
                                  "function": {
                                      "name": name,
                                      "arguments": json.dumps(
                                          args, ensure_ascii=False)},
                              }]}}]})
        out({"id": rid, "model": model, "object": "chat.completion.chunk",
             "choices": [{"index": 0, "finish_reason": "tool_calls",
                          "delta": {}}]})
        self.wfile.write(b"data: [DONE]\n\n")

    # --- маршрутизация ----------------------------------------------------

    def do_POST(self):
        body = self._read_body()
        if self.path.rstrip("/").endswith("/v1/chat/completions"):
            self._handle_chat(body)
        else:
            self._forward(body)

    def do_GET(self):
        self._forward(b"")


def wait_upstream(host, port, timeout_s=180):
    end = time.time() + timeout_s
    while time.time() < end:
        try:
            with socket.create_connection((host, port), timeout=2):
                return True
        except OSError:
            time.sleep(1)
    return False


def main():
    global _LOG_FH
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--listen", type=int, default=11434)
    ap.add_argument("--upstream", type=int, default=11435)
    ap.add_argument("--log", default=None,
                    help="файл лога (по умолчанию stderr)")
    args = ap.parse_args()
    if args.log:
        _LOG_FH = open(args.log, "a", buffering=1)
    Handler.upstream = ("127.0.0.1", args.upstream)
    if not wait_upstream("127.0.0.1", args.upstream):
        log("upstream port %d не поднялся" % args.upstream)
        return 1
    log("forwarding 127.0.0.1:%d -> 127.0.0.1:%d"
        % (args.listen, args.upstream))
    ThreadingHTTPServer(("127.0.0.1", args.listen), Handler).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
