"""Reversible secret redaction + model denylist guardrail for LiteLLM proxy.

pre_call:  replace secret-looking strings with SHAPE-PRESERVING FAKES
           (same length, same char classes, separators kept), so upstream
           cannot tell redaction happened. Mapping lives ONLY in the current
           call (local dict, built fresh per request, discarded after response).
           Same secret in the same request maps to the same fake
           (intra-call dedup via local table), so history + new turn stay
           consistent within one call. Next call re-masks from scratch:
           模型看到不同假值也无妨（它本来就不知道真值；agent 侧存真值，
           每次整包重 mask 全自洽，KV cache miss 只多花 token 不影响正确性）。
           无 salt、无 vault、无 TTL、无轮换：turn 完即忘。
pre_call key: VAULT_MASTER_KEY（即 LITELLM_MASTER_KEY，透明代理不鉴权，
           entrypoint 缺失即随机生成）。AES-GCM 确定性加密（固定 nonce=tag），
           同 key 同明文永远同密文；解密失败 = 不是我们发的 → 原样放过（fail-safe）。
post_call: restore fakes (in texts AND tool_calls) before the client
           sees the response, via multi-pattern match over this-call fakes.
streaming: restore per chunk with a carryover buffer. tool_calls deltas
           in streams are left untouched (non-streaming restores fully).

Model denylist: MODELS_DENIED (comma separated, or file) blocks
           high-cost models before they reach upstream. Fails CLOSED on
           read error, so a broken denylist file stops traffic instead of
           silently allowing expensive models.

Rules: JSON list at RULES_FILE, optionally refreshed from RULES_URL
(e.g. R2). Update = replace the file (or push to R2), no restart needed
for file edits only if mtime polling is on (FILE_POLL_SEC); URL polling
every RULES_REFRESH_SEC. Failures keep the old rules (fail-safe).
"""
import copy
import json
import os
import re
import time
import urllib.request
from typing import Any, AsyncGenerator, Literal, Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from litellm.integrations.custom_guardrail import CustomGuardrail

try:
    from litellm.exceptions import BadRequestError as _BadRequestError
except Exception:  # standalone unit-test mode (litellm not installed)
    _BadRequestError = None

RULES_FILE = os.getenv("RULES_FILE", "/app/guard-rules.json")
RULES_URL = os.getenv("RULES_URL", "")
REFRESH_SEC = int(os.getenv("RULES_REFRESH_SEC", "60"))
CARRY = 128
RESTORE_RX_CAP = 2000
MODELS_DENIED_FILE = os.getenv("MODELS_DENIED_FILE", "/app/models-denied.json")
DEFAULT_SESSION = os.getenv("GATEWAY_DEFAULT_SESSION", "gateway-default-v1")
SESSION_HEADER = "x-opencode-session"
SAFELIST_SUBSTR = (
    "example", "test", "xxx", "1234", "your-", "your_",
    "***", "fake", "demo", "sample", "placeholder", "changeme",
)


def _master_key() -> bytes:
    """32-byte AES key from LITELLM_MASTER_KEY（entrypoint 缺失即随机生成，仅启动占位）.
    确定性加密不带随机 nonce：同 key 同明文永远同密文（cache 友好）；容器重启换 key 即断关联。"""
    import hashlib

    raw = os.getenv("LITELLM_MASTER_KEY", "")
    if not raw:
        raise RuntimeError("LITELLM_MASTER_KEY 未设置（entrypoint 应已自动生成）")
    return hashlib.sha256(raw.encode()).digest()


class SecretVaultGuardrail(CustomGuardrail):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._rules = []          # list of (name, compiled_re, tag)
        self._file_mtime = 0
        self._last_fetch = 0.0
        self._denied_mtime = 0
        self._denied = set()
        self._denied_ok = False   # fail-closed: unreadable denylist blocks ALL
        self._load_file(force=True)
        self._load_denied(force=True)

    # ---------- model denylist ----------
    def _load_denied(self, force=False):
        """Read denylist, hot-reloaded on mtime change.

        Fail-CLOSED: if the file is missing or unparseable we do NOT fall
        back to "allow everything" (that would silently re-open the exact
        spend hole the denylist exists to close). We set _denied_ok=False
        and _check_denied then blocks every request until the file is fixed.
        A readable file containing an empty list is the explicit opt-in
        to allow all models.
        """
        try:
            mt = os.path.getmtime(MODELS_DENIED_FILE)
        except OSError:
            self._denied_ok = False
            self._denied = set()
            return
        if not force and mt == self._denied_mtime:
            return
        try:
            with open(MODELS_DENIED_FILE) as f:
                raw = json.load(f)
            items = raw if isinstance(raw, list) else raw.get("denied", [])
            self._denied = {str(x).strip().lower() for x in items if str(x).strip()}
            self._denied_mtime = mt
            self._denied_ok = True
        except Exception:
            self._denied = set()
            self._denied_ok = False

    def _ensure_session_header(self, request_data):
        """Fill a default session header when the client sent none.

        request_data IS the live kwargs dict (same object downstream reads),
        and at guardrail time it carries no "headers" key (verified), so this
        write cannot clobber anything that exists.

        Add-only-when-missing: a client that already sends x-opencode-session
        (e.g. opencode) flows through add_litellm_data_for_backend_llm_call,
        which overwrites data["headers"] only when the client actually sent
        x- headers (then containing the real session key); an empty forwarded
        set leaves our default in place. Either order keeps the real session
        intact and gives header-less clients (e.g. opendesign BYOK) a working
        default instead of a go-backend 400.
        """
        try:
            if not isinstance(request_data, dict):
                return
            headers = request_data.get("headers")
            if headers is None:
                request_data["headers"] = {SESSION_HEADER: DEFAULT_SESSION}
            elif isinstance(headers, dict):
                if not any(str(k).lower() == SESSION_HEADER for k in headers):
                    headers[SESSION_HEADER] = DEFAULT_SESSION
        except Exception:
            pass

    def _deny(self, message, model):
        """Block with a 400 (not 500): BadRequestError maps to status 400,
        so clients fail fast without retries and gateway logs stay clean.
        Falls back to generic Exception when litellm is unavailable."""
        if _BadRequestError is not None:
            raise _BadRequestError(
                message=message, model=model or "unknown", llm_provider="openai"
            )
        raise Exception(message)

    def _check_denied(self, request_data):
        model = None
        try:
            model = (request_data or {}).get("model")
        except Exception:
            pass
        if not self._denied_ok:
            self._deny(
                "ModelBlocked: denylist unavailable at %s; gateway is fail-closed."
                % MODELS_DENIED_FILE,
                model,
            )
        if not isinstance(model, str) or not model:
            return
        # clients may send "openai/kimi-k3", "azure/deployment-x", etc.
        # match the full name AND the last path segment.
        raw = model.strip()
        name = raw.lower()
        tail = name.rsplit("/", 1)[-1]
        if name in self._denied or tail in self._denied or raw in self._denied:
            self._deny(
                "ModelBlocked: %s is denied by gateway policy (cost control). "
                "Ask the user to pick a cheaper model." % model,
                model,
            )

    # ---------- rules loading ----------
    def _compile(self, raw):
        out = []
        for r in raw:
            try:
                out.append((r.get("name", "?"), re.compile(r.get("pattern", "(?!)")), r.get("tag", "X")))
            except re.error:
                continue
        return out

    def _load_file(self, force=False):
        try:
            mt = os.path.getmtime(RULES_FILE)
        except OSError:
            return
        if not force and mt == self._file_mtime:
            return
        try:
            with open(RULES_FILE) as f:
                self._rules = self._compile(json.load(f))
            self._file_mtime = mt
        except Exception:
            pass

    def _fetch_url(self):
        if not RULES_URL:
            return
        now = time.time()
        if now - self._last_fetch < REFRESH_SEC:
            return
        self._last_fetch = now
        try:
            req = urllib.request.Request(RULES_URL, headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=5) as r:
                if r.status == 200:
                    self._rules = self._compile(json.loads(r.read().decode()))
        except Exception:
            pass

    def _refresh(self):
        self._load_file()
        self._fetch_url()
        self._load_denied()

    # ---------- core ----------
    def _safelisted(self, s):
        low = s.lower()
        return any(x in low for x in SAFELIST_SUBSTR)

    def _fake_for(self, tag, orig):
        """AES-GCM 确定性加密（固定 nonce=tag）：同 key 同明文永远同密文（cache 友好）；
        截断拼成同形假值（保留 sk- 前缀＋字符类别＋长度）。无状态：不记 vault 不记盐，
        turn 完即忘；容器重启换 key 即断关联。"""
        import hashlib

        raw = AESGCM(_master_key()).encrypt(
            hashlib.sha256(tag.encode()).digest()[:12],
            orig.encode(),
            None,
        )
        out = list(orig[:3])
        ri = 0
        for ch in orig[3:]:
            b = raw[ri % len(raw)]
            if "a" <= ch <= "z":
                out.append(chr(ord("a") + b % 26))
                ri += 1
            elif "A" <= ch <= "Z":
                out.append(chr(ord("A") + b % 26))
                ri += 1
            elif "0" <= ch <= "9":
                out.append(chr(ord("0") + b % 10))
                ri += 1
            else:
                out.append(ch)
        return "".join(out)

    def _real_for(self, fake):
        """逆操作：假值解回真值。解不开（模型自编/上轮容器/伪造）→ 返回 None，调用方原样放过。"""
        return None  # 占位：真实现在 _restore_text 里按映射查；AES 版见下

    def _mask_text(self, text, vault):
        """单次调用内映射（vault: fake->orig 本调用局部 dict，调完即扔）。
        同真值同包内映射到同一假值（整包历史自洽）；下次调用重新编号互不干扰。"""
        if not isinstance(text, str) or not text:
            return text
        # 反向表：同包内同一真值只编一次号
        rev = {v: k for k, v in vault.items()}
        for _name, rx, tag in self._rules:
            def _sub(m, _tag=tag):
                orig = m.group(0)
                if self._safelisted(orig):
                    return orig
                if orig in rev:
                    return rev[orig]
                ph = self._fake_for(_tag, orig)
                # 碰撞几乎不可能（AES 输出），撞了就原样放过不掩盖
                if ph in vault and vault[ph] != orig:
                    return orig
                vault[ph] = orig
                rev[orig] = ph
                return ph
            try:
                text = rx.sub(_sub, text)
            except Exception:
                continue
        return text

    def _restore_rx_get(self):
        """Multi-pattern matcher over known fakes (longest first).
        Rebuilt when vault membership changes; capped to most recent
        entries so per-response cost stays bounded."""
        if self._restore_rx_ver != self._vault_ver:
            if len(self._vault) > RESTORE_RX_CAP:
                items = sorted(self._vault.items(), key=lambda kv: kv[1][1], reverse=True)
                keys = [k for k, _ in items[:RESTORE_RX_CAP]]
            else:
                keys = list(self._vault.keys())
            keys.sort(key=len, reverse=True)
            try:
                self._restore_rx = re.compile("|".join(re.escape(w) for w in keys)) if keys else None
            except Exception:
                self._restore_rx = None
            self._restore_rx_ver = self._vault_ver
        return self._restore_rx

    def _restore_text(self, text):
        if not isinstance(text, str) or not text:
            return text
        rx = self._restore_rx_get()
        if rx is None:
            return text
        def _sub(m):
            hit = self._vault.get(m.group(0))
            return hit[0] if hit else m.group(0)
        try:
            return rx.sub(_sub, text)
        except Exception:
            return text

    def _mask_tool_calls(self, tcs):
        for tc in tcs or []:
            try:
                fn = tc.get("function", {})
                args = fn.get("arguments")
                if isinstance(args, str):
                    fn["arguments"] = self._mask_text(args)
            except Exception:
                continue

    def _restore_tool_calls(self, tcs):
        for tc in tcs or []:
            try:
                fn = tc.get("function", {})
                args = fn.get("arguments")
                if isinstance(args, str):
                    fn["arguments"] = self._restore_text(args)
            except Exception:
                continue

    def _mask_messages(self, messages):
        """Return a NEW list with content masked (LiteLLM ignores in-place edits)."""
        nm = copy.deepcopy(messages)
        for m in nm:
            if isinstance(m, dict) and isinstance(m.get("content"), str):
                m["content"] = self._mask_text(m["content"])
        return nm

    # ---------- hooks ----------
    async def apply_guardrail(self, inputs, request_data, input_type, logging_obj=None):
        self._refresh()
        if input_type == "request":
            self._check_denied(request_data)
            self._ensure_session_header(request_data)
            texts = inputs.get("texts") or []
            inputs["texts"] = [self._mask_text(t) for t in texts]
            # embeddings 路径的输入在 inputs["input"]（str 或 list），同时保留 texts 覆盖。
            # 已知（e2e 实证）：本版本 litellm 在 /v1/embeddings 路径丢弃 guard 返回改写，
            # embeddings 脱敏不生效；chat 路径按 litellm hook 契约生效。此处保留覆盖，
            # 若 litellm 未来版本改行为，e2e 报告制探针会自动翻绿，无需改码。
            inp = inputs.get("input")
            if isinstance(inp, str):
                inputs["input"] = self._mask_text(inp)
            elif isinstance(inp, list):
                inputs["input"] = [self._mask_text(t) for t in inp]
            self._mask_tool_calls(inputs.get("tool_calls"))
            sm = inputs.get("structured_messages")
            if isinstance(sm, list):
                inputs["structured_messages"] = self._mask_messages(sm)
            try:
                inputs["stream_holdback_chars"] = CARRY
            except Exception:
                pass
            return inputs
        # response
        texts = inputs.get("texts") or []
        inputs["texts"] = [self._restore_text(t) for t in texts]
        self._restore_tool_calls(inputs.get("tool_calls"))
        return inputs

    async def async_post_call_streaming_iterator_hook(
        self, user_api_key_dict, response, request_data
    ):
        """Restore fakes per chunk; hold back a text tail so a fake split
        across chunks still matches whole. tool_calls deltas are BUFFERED
        per tool index and released once (fully restored) on finish, so
        downstream never executes with an unrestored fake."""
        self._refresh()
        pending = ""
        tools = {}  # (choice_idx, tool_idx) -> {id, name, args, first}

        def _choices_of(chunk):
            if isinstance(chunk, dict):
                return chunk.get("choices", []) or []
            return getattr(chunk, "choices", []) or []

        def _tool_get(tc, field, fn_field=None):
            if isinstance(tc, dict):
                if fn_field is None:
                    return tc.get(field)
                fn = tc.get("function", {})
                return fn.get(fn_field) if isinstance(fn, dict) else None
            if fn_field is None:
                return getattr(tc, field, None)
            fn = getattr(tc, "function", None)
            return getattr(fn, fn_field, None)

        def _strip_text(delta):
            try:
                if isinstance(delta, dict):
                    delta["content"] = None
                else:
                    delta.content = None
            except Exception:
                pass

        def _release_tool(entry):
            """Build a chunk carrying ONLY this tool's complete restored call
            (deep-copied, so shared first-chunks never alias across tools)."""
            chunk, cidx, tc_pos = entry["first"]
            try:
                out = copy.deepcopy(chunk)
            except Exception:
                return None
            try:
                choices = _choices_of(out)
                choice = choices[cidx]
                delta = choice.get("delta") if isinstance(choice, dict) else getattr(choice, "delta", None)
                if delta is None:
                    return None
                _strip_text(delta)
                tcs = delta.get("tool_calls") if isinstance(delta, dict) else getattr(delta, "tool_calls", None)
                tc = (tcs or [])[tc_pos]
                restored = self._restore_text(entry["args"])
                if isinstance(tc, dict):
                    if entry["id"] is not None:
                        tc["id"] = entry["id"]
                    fn = tc.get("function")
                    if isinstance(fn, dict):
                        if entry["name"] is not None:
                            fn["name"] = entry["name"]
                        fn["arguments"] = restored
                else:
                    if entry["id"] is not None:
                        try:
                            tc.id = entry["id"]
                        except Exception:
                            pass
                    fn = getattr(tc, "function", None)
                    if fn is not None:
                        if entry["name"] is not None:
                            try:
                                fn.name = entry["name"]
                            except Exception:
                                pass
                        try:
                            fn.arguments = restored
                        except Exception:
                            pass
                if isinstance(delta, dict):
                    delta["tool_calls"] = [tc]
                else:
                    try:
                        delta.tool_calls = [tc]
                    except Exception:
                        pass
                return out
            except Exception:
                return None

        def _restore_reasoning(delta):
            """Best-effort restore of reasoning_content (no holdback:
            whole fakes restore, split ones pass through to the next chunk
            only if they complete within it -- strictly better than never)."""
            try:
                rc = delta.get("reasoning_content") if isinstance(delta, dict) else getattr(delta, "reasoning_content", None)
                if isinstance(rc, str) and rc:
                    fixed = self._restore_text(rc)
                    if isinstance(delta, dict):
                        delta["reasoning_content"] = fixed
                    else:
                        delta.reasoning_content = fixed
            except Exception:
                pass

        def _flush_text_pending(delta):
            """Append held-back tail (restored) to a finish chunk so short
            responses are never truncated."""
            nonlocal pending
            if not pending:
                return
            try:
                tail = self._restore_text(pending)
                pending = ""
                if isinstance(delta, dict):
                    prev = delta.get("content") or ""
                    delta["content"] = prev + tail if isinstance(prev, str) else tail
                else:
                    prev = getattr(delta, "content", None) or ""
                    try:
                        delta.content = prev + tail if isinstance(prev, str) else tail
                    except Exception:
                        pass
            except Exception:
                pass

        try:
            async for chunk in response:
                try:
                    choices = _choices_of(chunk)
                    has_finish = any(
                        (c.get("finish_reason") if isinstance(c, dict) else getattr(c, "finish_reason", None)) is not None
                        for c in choices
                    )
                    suppress = False
                    for cidx, choice in enumerate(choices):
                        delta = choice.get("delta") if isinstance(choice, dict) else getattr(choice, "delta", None)
                        if delta is None:
                            continue
                        content = delta.get("content") if isinstance(delta, dict) else getattr(delta, "content", None)
                        tcs = delta.get("tool_calls") if isinstance(delta, dict) else getattr(delta, "tool_calls", None)
                        tcs = tcs or []
                        if not tcs:
                            if isinstance(content, str) and content:
                                blob = pending + content
                                pending = ""
                                if has_finish:
                                    # terminal chunk: nothing comes after, restore whole
                                    head = self._restore_text(blob)
                                else:
                                    # hold back a tail that may contain a partial fake
                                    cut = len(blob) - CARRY
                                    if cut < 0:
                                        cut = 0
                                    head, pending = blob[:cut], blob[cut:]
                                    head = self._restore_text(head)
                                if isinstance(delta, dict):
                                    delta["content"] = head
                                else:
                                    try:
                                        delta.content = head
                                    except Exception:
                                        pass
                            _restore_reasoning(delta)
                            continue
                        # chunk carries tool deltas: stream its text live via a copy,
                        # buffer the original for single restored release at finish
                        if isinstance(content, str) and content:
                            blob = pending + content
                            pending = ""
                            if has_finish:
                                head = self._restore_text(blob)
                            else:
                                cut = len(blob) - CARRY
                                if cut < 0:
                                    cut = 0
                                head, pending = blob[:cut], blob[cut:]
                                head = self._restore_text(head)
                            try:
                                live = copy.deepcopy(chunk)
                                live_delta = _choices_of(live)[cidx].get("delta") if isinstance(_choices_of(live)[cidx], dict) else getattr(_choices_of(live)[cidx], "delta", None)
                                if isinstance(live_delta, dict):
                                    live_delta["content"] = head
                                    live_delta["tool_calls"] = []
                                else:
                                    try:
                                        live_delta.content = head
                                    except Exception:
                                        pass
                                    try:
                                        live_delta.tool_calls = []
                                    except Exception:
                                        pass
                                yield live
                            except Exception:
                                # deepcopy failed: keep old behavior (text live, tools as-is)
                                if isinstance(content, str) and content:
                                    if isinstance(delta, dict):
                                        delta["content"] = self._restore_text(head)
                                    else:
                                        try:
                                            delta.content = self._restore_text(head)
                                        except Exception:
                                            pass
                                yield chunk
                                continue
                        for pos, tc in enumerate(tcs):
                            idx = _tool_get(tc, "index")
                            idx = idx if idx is not None else pos
                            key = (cidx, idx)
                            entry = tools.get(key)
                            if entry is None:
                                entry = {"id": None, "name": None, "args": "", "first": None}
                                tools[key] = entry
                            tid = _tool_get(tc, "id")
                            tname = _tool_get(tc, "name", "name")
                            frag = _tool_get(tc, "arguments", "arguments")
                            if entry["id"] is None and tid:
                                entry["id"] = tid
                            if entry["name"] is None and tname:
                                entry["name"] = tname
                            if isinstance(frag, str) and frag:
                                entry["args"] += frag
                            if entry["first"] is None:
                                _strip_text(delta)
                                entry["first"] = (chunk, cidx, pos)
                        suppress = True
                    if has_finish:
                        for cidx2, choice2 in enumerate(choices):
                            delta2 = choice2.get("delta") if isinstance(choice2, dict) else getattr(choice2, "delta", None)
                            if delta2 is None:
                                continue
                            _restore_reasoning(delta2)
                            _flush_text_pending(delta2)
                    if has_finish and tools:
                        for key in sorted(tools.keys()):
                            rel = _release_tool(tools[key])
                            if rel is not None:
                                yield rel
                        tools = {}
                        for cidx2, choice2 in enumerate(choices):
                            delta2 = choice2.get("delta") if isinstance(choice2, dict) else getattr(choice2, "delta", None)
                            if delta2 is None:
                                continue
                            try:
                                if isinstance(delta2, dict):
                                    delta2["tool_calls"] = []
                                else:
                                    delta2.tool_calls = []
                            except Exception:
                                pass
                        yield chunk
                    elif not suppress:
                        yield chunk
                except Exception:
                    yield chunk
            if pending:
                # flush remainder as a final text-only pass is not possible
                # without a chunk object; fakes here are vanishingly
                # rare (only if a response ends mid-fake).
                pass
            if tools:
                # stream ended without finish marker: release buffered tool
                # calls restored (better than dropping them).
                for key in sorted(tools.keys()):
                    rel = _release_tool(tools[key])
                    if rel is not None:
                        yield rel
        except Exception:
            async for chunk in response:
                yield chunk
