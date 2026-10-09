"""
modem_gate.py - the translating modem contract (Volume 5, Section C). Apache-2.0.

Four pieces, each a plain function so any engine fits the slot:
  * NODE_SCHEMA + validate_node(): one idea per node, provenance to a corpus span
  * LEVELS: the dial, L0 (about 4th-grade) .. L6 (raw source), with checkable limits
  * gate(node, expression, level, judge) -> {p, verdict, drift_span}
  * regenerate_until_pass(): regeneration aimed at the drift span
  * Extractor: content-addressed cache so a nondeterministic model still yields a
    re-derivable graph (corpus hash + prompt hash + model id + params -> output)

The gate has no parameter for a desired conclusion. It scores whether the
node's propositions can be recovered from the expression, and nothing else.
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

# ---------------------------------------------------------------------------
# Node schema (JSON). Kept dependency-free: validate_node() checks it by hand.
# ---------------------------------------------------------------------------
NODE_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "modem node",
    "type": "object",
    "required": ["id", "title", "summary", "propositions", "provenance", "parent",
                 "children", "lane", "depth", "derivation"],
    "properties": {
        "id": {"type": "string", "pattern": "^[0-9a-f]{16}$"},
        "title": {"type": "string", "maxLength": 120},
        "summary": {"type": "string", "description": "one sentence: the idea"},
        "propositions": {"type": "array", "minItems": 1, "items": {
            "type": "object", "required": ["id", "text", "key_terms"],
            "properties": {"id": {"type": "string"}, "text": {"type": "string"},
                           "key_terms": {"type": "array", "items": {"type": "string"}}}}},
        "provenance": {"type": "object", "required": ["doc_id", "doc_sha256", "start", "end"],
                       "properties": {"doc_id": {"type": "string"},
                                      "doc_sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
                                      "start": {"type": "integer", "minimum": 0},
                                      "end": {"type": "integer", "minimum": 0}}},
        "parent": {"type": ["string", "null"]},
        "children": {"type": "array", "items": {"type": "string"}},
        "lane": {"type": "string", "description": "audience door"},
        "depth": {"type": "integer", "minimum": 0},
        "status": {"enum": ["fog", "filled", "passing"]},
        "derivation": {"type": "object", "required": ["cache_key", "extractor", "prompt_sha256"]},
    },
}


def validate_node(n: dict) -> list[str]:
    errs = [f"missing {k}" for k in NODE_SCHEMA["required"] if k not in n]
    if errs:
        return errs
    if not re.fullmatch(r"[0-9a-f]{16}", n["id"]):
        errs.append("id must be 16 hex chars")
    p = n["provenance"]
    if not (0 <= p["start"] < p["end"]):
        errs.append("provenance span must satisfy 0 <= start < end")
    if not re.fullmatch(r"[0-9a-f]{64}", p["doc_sha256"]):
        errs.append("doc_sha256 must be a sha256 hex digest")
    if not n["propositions"]:
        errs.append("at least one proposition")
    return errs


def node_id(doc_id: str, start: int, end: int, title: str) -> str:
    """Deterministic: same span + same title -> same id, across re-extractions."""
    norm = re.sub(r"\s+", " ", title.strip().lower())
    return hashlib.sha256(f"{doc_id}|{start}|{end}|{norm}".encode()).hexdigest()[:16]


# ---------------------------------------------------------------------------
# The dial: comprehension levels with checkable limits
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Level:
    code: int
    name: str
    max_grade: float | None          # Flesch-Kincaid grade ceiling (None = no ceiling)
    max_avg_sentence_words: int | None
    undefined_terms_allowed: bool    # may technical terms appear without a definition?
    requires_example: bool


LEVELS = {
    0: Level(0, "plain (about 4th-grade)", 5.0, 12, False, True),
    1: Level(1, "general public (about 6th-grade)", 7.0, 15, False, True),
    2: Level(2, "secondary school", 10.0, 20, False, False),
    3: Level(3, "undergraduate", 14.0, 25, False, False),
    4: Level(4, "practitioner", None, None, True, False),
    5: Level(5, "specialist", None, None, True, False),
    6: Level(6, "raw source", None, None, True, False),   # the corpus span itself
}

_SENT = re.compile(r"[^.!?]+[.!?]*")


def sentences(text: str) -> list[tuple[int, int, str]]:
    return [(m.start(), m.end(), m.group().strip()) for m in _SENT.finditer(text) if m.group().strip()]


def _syllables(word: str) -> int:
    w = word.lower().strip(".,;:!?\"'()")
    if not w:
        return 0
    groups = re.findall(r"[aeiouy]+", w)
    n = len(groups) - (1 if w.endswith("e") and len(groups) > 1 else 0)
    return max(1, n)


def fk_grade(text: str) -> float:
    sents = sentences(text)
    words = re.findall(r"[A-Za-z']+", text)
    if not sents or not words:
        return 0.0
    syl = sum(_syllables(w) for w in words)
    return 0.39 * len(words) / len(sents) + 11.8 * syl / len(words) - 15.59


# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------
PASS_P = 0.80          # verdict pass at or above this probability
REVIEW_BAND = 0.05     # within this distance of PASS_P with low judge confidence -> review
MAX_REGEN = 4          # after this many failed regenerations -> review (a human seat)


@dataclass
class GateResult:
    p: float
    verdict: str                      # pass | fail | review
    drift_span: tuple[int, int] | None
    missing: list[str] = field(default_factory=list)   # proposition ids not recovered
    reason: str = ""

    def as_dict(self) -> dict:
        return {"p": self.p, "verdict": self.verdict, "drift_span": self.drift_span,
                "missing": self.missing, "reason": self.reason}


# A judge maps (proposition, expression, level) -> (recovered: bool, confidence: float,
# carrier_span: (start, end) | None). Any engine fits: a small judgment model on
# your own box, or the keyword judge below used in tests.
Judge = Callable[[dict, str, Level], tuple[bool, float, tuple[int, int] | None]]


def keyword_judge(prop: dict, expression: str, level: Level):
    """Deterministic stand-in: a proposition is recovered when every key term
    (or a listed synonym, 'term|synonym') appears; the carrier is the sentence
    with the most hits."""
    low = expression.lower()
    hits = [any(alt in low for alt in t.lower().split("|")) for t in prop["key_terms"]]
    sents = sentences(expression)
    best, best_n = None, 0
    for s, e, txt in sents:
        n = sum(any(alt in txt.lower() for alt in t.lower().split("|")) for t in prop["key_terms"])
        if n > best_n:
            best, best_n = (s, e), n
    if best is None and sents:          # nothing carries it: the idea was lost at the end
        best = (sents[-1][0], sents[-1][1])
    return all(hits), 0.9, best


def gate(node: dict, expression: str, level: int, judge: Judge = keyword_judge) -> GateResult:
    """Input {node, expression, level}; output {p, verdict, drift_span}."""
    lv = LEVELS[level]
    if lv.code == 6:   # raw source: must be the span itself; meaning is trivially conserved
        return GateResult(1.0, "pass", None, reason="raw source")
    # 1) form limits for the level (deterministic, cheap, run first)
    for s, e, txt in sentences(expression):
        nwords = len(txt.split())
        if lv.max_avg_sentence_words and nwords > 2 * lv.max_avg_sentence_words:
            return GateResult(0.0, "fail", (s, e), reason=f"sentence too long for L{level}")
    if lv.max_grade is not None and fk_grade(expression) > lv.max_grade:
        worst = max(sentences(expression), key=lambda x: fk_grade(x[2]))
        return GateResult(0.0, "fail", (worst[0], worst[1]), reason=f"reading grade above L{level}")
    # 2) meaning: recover each proposition
    results = [(pr["id"], *judge(pr, expression, lv)) for pr in node["propositions"]]
    recovered = [r for r in results if r[1]]
    p = round(len(recovered) / len(results), 3)
    conf = min(r[2] for r in results)
    missing = [r[0] for r in results if not r[1]]
    drift = next((r[3] for r in results if not r[1]), None)
    if p >= PASS_P:
        verdict = "pass"
    elif abs(p - PASS_P) <= REVIEW_BAND and conf < 0.6:
        verdict = "review"
    else:
        verdict = "fail"
    return GateResult(p, verdict, drift, missing, reason="meaning")


Renderer = Callable[[dict, int, dict | None], str]


def regenerate_until_pass(node: dict, level: int, render: Renderer,
                          judge: Judge = keyword_judge) -> tuple[str, GateResult, int]:
    """Render, gate, and on failure re-render with a repair brief aimed at the
    drift span: {previous, drift_span, drift_text, missing, reason, attempt,
    escalate_form}. escalate_form is set when the same span fails twice, telling
    the renderer to change form (split, example, analogy, other modality) rather
    than reword. After MAX_REGEN failures the verdict becomes review."""
    brief, last_span = None, None
    expr = render(node, level, None)
    for attempt in range(MAX_REGEN + 1):
        g = gate(node, expr, level, judge)
        if g.verdict == "pass":
            return expr, g, attempt
        if g.verdict == "review" or attempt == MAX_REGEN:
            g.verdict = "review"
            return expr, g, attempt
        span = g.drift_span
        brief = {"previous": expr, "drift_span": span,
                 "drift_text": expr[span[0]:span[1]] if span else "",
                 "missing": [p for p in node["propositions"] if p["id"] in g.missing],
                 "reason": g.reason, "attempt": attempt + 1,
                 "escalate_form": span is not None and span == last_span}
        last_span = span
        expr = render(node, level, brief)
    raise AssertionError("unreachable")


# ---------------------------------------------------------------------------
# Re-derivable extraction over a nondeterministic model
# ---------------------------------------------------------------------------
def sha256(b: bytes | str) -> str:
    return hashlib.sha256(b.encode() if isinstance(b, str) else b).hexdigest()


class Extractor:
    """cache_key = sha256(doc_sha256 | prompt_sha256 | model_id | json(params)).
    The cache stores the raw model output and its hash. Re-running extraction on
    the same corpus with the same recorded parameters returns the cached output,
    so the graph is re-derivable even when the model is not deterministic.
    Changing the corpus, prompt, model or params changes the key and yields a
    new, versioned derivation; nodes whose span and title did not change keep
    their ids, so a diff shows exactly what moved."""

    def __init__(self, cache_dir: Path, model_id: str, prompt: str,
                 call: Callable[[str, str, dict], str], params: dict | None = None):
        self.dir, self.model_id, self.prompt, self.call = Path(cache_dir), model_id, prompt, call
        self.params = params or {"temperature": 0.0, "seed": 1}
        self.dir.mkdir(parents=True, exist_ok=True)

    def extract(self, doc_id: str, text: str) -> list[dict]:
        doc_sha = sha256(text)
        prompt_sha = sha256(self.prompt)
        key = sha256(f"{doc_sha}|{prompt_sha}|{self.model_id}|{json.dumps(self.params, sort_keys=True)}")
        path = self.dir / f"{key}.json"
        if path.exists():
            rec = json.loads(path.read_text(encoding="utf-8"))
            assert sha256(rec["output"]) == rec["output_sha256"], "cache tampered"
        else:
            out = self.call(self.prompt, text, self.params)
            rec = {"cache_key": key, "doc_id": doc_id, "doc_sha256": doc_sha, "prompt_sha256": prompt_sha,
                   "model_id": self.model_id, "params": self.params, "output": out,
                   "output_sha256": sha256(out)}
            path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
        raw = json.loads(rec["output"])
        nodes = []
        for r in raw:
            start, end = int(r["start"]), int(r["end"])
            if text[start:end].strip() == "":
                raise ValueError("provenance span points at nothing")
            n = {"id": node_id(doc_id, start, end, r["title"]), "title": r["title"],
                 "summary": r["summary"], "propositions": r["propositions"],
                 "provenance": {"doc_id": doc_id, "doc_sha256": doc_sha, "start": start, "end": end},
                 "parent": r.get("parent"), "children": r.get("children", []),
                 "lane": r.get("lane", "general"), "depth": int(r.get("depth", 0)), "status": "fog",
                 "derivation": {"cache_key": key, "extractor": self.model_id, "prompt_sha256": prompt_sha}}
            errs = validate_node(n)
            if errs:
                raise ValueError(errs)
            nodes.append(n)
        return nodes
