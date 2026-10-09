"""
interlock_loop.py - reference implementation of the Volume 5 loop contract
(Section B) and teaching mechanics (Section D). Apache-2.0.

The loop runs AS THE PARTICIPANT: it connects with a login role that
holon_roles maps to the participant's holon (sql/10-interlock-schema.sql,
role loop_runner). Every read and write below therefore passes through the
one rule. Nothing in this file decides access; the store does.

Pluggable parts (any engine fits the slot):
  render(concept, strategy, level, modality, seed) -> Expression
  assess(expression, concept) -> Evidence            (items answered by the learner)
The diagnosis table, the strategy tally (bandit), the backtrack rule, the
stop rules and the help record are implemented here and are the contract.
"""
from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass, field
from typing import Callable, Protocol

# ---------------------------------------------------------------------------
# Constants of the contract
# ---------------------------------------------------------------------------
CAUSES = ("vocabulary_gap", "missing_prerequisite", "format_mismatch",
          "abstraction_level", "attention")

# strategy families per cause, in default order
STRATEGIES: dict[str, list[str]] = {
    "vocabulary_gap":       ["define_terms_first", "glossary_with_examples"],
    "missing_prerequisite": ["backtrack_prerequisite", "bridge_example"],
    "format_mismatch":      ["switch_modality", "interactive_steps"],
    "abstraction_level":    ["concrete_first", "lower_level"],
    "attention":            ["shorter_chunks", "single_item_checks"],
    "unknown":              ["alternative_framing", "lower_level", "concrete_first",
                             "switch_modality", "define_terms_first", "shorter_chunks"],
}
# order in which causes are tested (first match wins), Section D table
DIAGNOSIS_ORDER = ("attention", "missing_prerequisite", "vocabulary_gap",
                   "abstraction_level", "format_mismatch")

LEVELS = {0: "plain (about 4th-grade reading)", 1: "general public", 2: "secondary school",
          3: "undergraduate", 4: "practitioner", 5: "specialist", 6: "raw source"}
MODALITIES = ("text", "worked_example", "visual", "audio", "interactive")


# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------
@dataclass
class ItemResult:
    concept_key: str          # concept the item is tagged to
    correct: bool
    error_tags: list[str] = field(default_factory=list)   # e.g. ["term"], ["prereq:common_denom"]
    abstraction: str = "abstract"                          # "concrete" | "abstract"
    latency_s: float = 10.0
    blank: bool = False


@dataclass
class Evidence:
    items: list[ItemResult]
    modality: str
    best_other_modality_score: float | None = None   # learner's best score on this concept elsewhere
    learner_median_latency_s: float = 10.0


@dataclass
class Assessment:
    passed: bool
    score: float
    cause: str            # 'none' | one of CAUSES | 'unknown'
    cause_concept: str | None
    evidence: dict


@dataclass
class Expression:
    text: str
    model_id: str
    seed: int
    temperature: float

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Section D: cause diagnosis (decision table)
# ---------------------------------------------------------------------------
THRESH = {
    "attention_blank_rate": 0.30,       # share of blank / skipped items
    "attention_slow_factor": 3.0,       # latency vs the learner's own median
    "attention_slow_share": 0.30,
    "attention_fade": 0.30,             # first-half minus second-half accuracy
    "prereq_error_share": 0.40,         # share of errors tagged prereq:<k>
    "vocab_error_share": 0.40,          # share of errors tagged term
    "abstraction_gap": 0.30,            # concrete accuracy minus abstract accuracy
    "format_gap": 0.25,                 # best other modality minus this modality
}


def score_of(items: list[ItemResult]) -> float:
    return sum(i.correct for i in items) / len(items) if items else 0.0


def diagnose(ev: Evidence) -> tuple[str, str | None, dict]:
    """Return (cause, cause_concept, signature). First rule that fires wins."""
    items = ev.items
    errors = [i for i in items if not i.correct]
    n, ne = len(items), max(len(errors), 1)
    sig: dict = {}

    blank_rate = sum(i.blank for i in items) / n if n else 0
    slow_share = sum(i.latency_s > THRESH["attention_slow_factor"] * ev.learner_median_latency_s
                     for i in items) / n if n else 0
    half = n // 2
    fade = (score_of(items[:half]) - score_of(items[half:])) if half else 0.0
    sig.update(blank_rate=round(blank_rate, 3), slow_share=round(slow_share, 3), fade=round(fade, 3))

    prereq_counts: dict[str, int] = {}
    for e in errors:
        for t in e.error_tags:
            if t.startswith("prereq:"):
                prereq_counts[t[7:]] = prereq_counts.get(t[7:], 0) + 1
    top_prereq = max(prereq_counts, key=prereq_counts.get) if prereq_counts else None
    prereq_share = (prereq_counts[top_prereq] / ne) if top_prereq else 0.0
    vocab_share = sum("term" in e.error_tags for e in errors) / ne if errors else 0.0
    conc = [i for i in items if i.abstraction == "concrete"]
    abst = [i for i in items if i.abstraction == "abstract"]
    abstraction_gap = (score_of(conc) - score_of(abst)) if conc and abst else 0.0
    format_gap = ((ev.best_other_modality_score - score_of(items))
                  if ev.best_other_modality_score is not None else 0.0)
    sig.update(prereq_share=round(prereq_share, 3), top_prereq=top_prereq,
               vocab_share=round(vocab_share, 3), abstraction_gap=round(abstraction_gap, 3),
               format_gap=round(format_gap, 3))

    fired = {
        "attention": (blank_rate >= THRESH["attention_blank_rate"]
                      or slow_share >= THRESH["attention_slow_share"]
                      or fade >= THRESH["attention_fade"]),
        "missing_prerequisite": prereq_share >= THRESH["prereq_error_share"],
        "vocabulary_gap": vocab_share >= THRESH["vocab_error_share"],
        "abstraction_level": abstraction_gap >= THRESH["abstraction_gap"],
        "format_mismatch": format_gap >= THRESH["format_gap"],
    }
    for cause in DIAGNOSIS_ORDER:
        if fired[cause]:
            return cause, (top_prereq if cause == "missing_prerequisite" else None), sig
    return "unknown", None, sig


def assess(ev: Evidence, threshold: float) -> Assessment:
    """The assessment contract: {pass, score, cause}."""
    s = round(score_of(ev.items), 3)
    if s >= threshold:
        return Assessment(True, s, "none", None, {"n": len(ev.items)})
    cause, concept, sig = diagnose(ev)
    return Assessment(False, s, cause, concept, sig)


# ---------------------------------------------------------------------------
# Section D: the meta-learning rule (per-learner strategy tally, simple bandit)
# ---------------------------------------------------------------------------
def choose_strategy(cause: str, tally: dict[tuple[str, str], tuple[int, int]],
                    exclude: set[str] = frozenset()) -> str:
    """Untried strategies first (in family order); then highest Laplace-smoothed
    success rate (s+1)/(t+2), plus a UCB bonus sqrt(2 ln N / t). Deterministic."""
    family = [s for s in STRATEGIES.get(cause, STRATEGIES["unknown"]) if s not in exclude] \
        or STRATEGIES["unknown"]
    for s in family:
        if tally.get((cause, s), (0, 0))[0] == 0:
            return s
    total = sum(tally.get((cause, s), (0, 0))[0] for s in family)

    def value(s: str) -> float:
        t, w = tally[(cause, s)]
        return (w + 1) / (t + 2) + math.sqrt(2 * math.log(max(total, 1)) / t)
    return max(family, key=value)


# ---------------------------------------------------------------------------
# Section D: presentation precedence
# ---------------------------------------------------------------------------
def presentation(skill_params: dict, profile_signals: dict, course_default_level: int,
                 cause: str | None, strategy: str, last_level: int | None) -> tuple[int, str]:
    """Order of precedence for (level, modality) on one attempt:
       1. a diagnosed cause overrides its own dimension for THIS attempt only
          (abstraction_level -> level-1; format_mismatch -> next modality);
       2. the user-held skill file (what the person said);
       3. the derived learner profile (what the system observed, consent-gated);
       4. the course default."""
    level = skill_params.get("default_level", profile_signals.get("level", course_default_level))
    modality = skill_params.get("modality", profile_signals.get("modality", "text"))
    if cause == "abstraction_level" or strategy == "lower_level":
        level = max(0, (last_level if last_level is not None else level) - 1)
    if cause == "format_mismatch" or strategy == "switch_modality":
        modality = MODALITIES[(MODALITIES.index(modality) + 1) % len(MODALITIES)] \
            if modality in MODALITIES else "visual"
    return int(level), modality


def update_profile(signals: dict, consent: dict, obs: dict, alpha: float = 0.3) -> dict:
    """Exponential moving average per consented signal class. Decay toward
    neutral (0.5) is applied by the caller per elapsed day (half-life 30 days)."""
    out = dict(signals)
    for k, v in obs.items():
        if not consent.get(k, False):
            continue                                 # no consent, no signal
        out[k] = round((1 - alpha) * out.get(k, 0.5) + alpha * v, 4)
    return out


def decay(signals: dict, days: float, half_life_days: float = 30.0) -> dict:
    f = 0.5 ** (days / half_life_days)
    return {k: round(0.5 + (v - 0.5) * f, 4) if isinstance(v, (int, float)) else v
            for k, v in signals.items()}


# ---------------------------------------------------------------------------
# The store (Postgres, as the participant's loop role)
# ---------------------------------------------------------------------------
class Store(Protocol):
    def q(self, sql: str, args: tuple = ()) -> list[dict]: ...


class PgStore:
    def __init__(self, conn):
        self.c = conn

    def q(self, sql: str, args: tuple = ()) -> list[dict]:
        with self.c.cursor() as cur:
            cur.execute(sql, args)
            rows = cur.fetchall() if cur.description else []
            cols = [d.name for d in cur.description] if cur.description else []
        self.c.commit()
        return [dict(zip(cols, r)) for r in rows]


# ---------------------------------------------------------------------------
# Section B: the loop contract
# ---------------------------------------------------------------------------
@dataclass
class LoopResult:
    status: str               # mastered | active (the goal persists; nothing parks it but the learner)
    iterations: int
    path: list[tuple[str, str, float]]   # (concept, strategy, score)
    help_id: int | None = None
    help_offered: int = 0


# Defaults used when there is no course (section A.9). Tune locally.
NO_COURSE_DEFAULTS = {"no_gain_window": 3, "min_gain": 0.02}

# every strategy, in the order the loop rotates through families of approaches
ROTATION = list(dict.fromkeys(
    STRATEGIES["unknown"] + [s for fam in ("format_mismatch", "abstraction_level", "vocabulary_gap",
                                           "attention", "missing_prerequisite")
                             for s in STRATEGIES[fam]]))


def next_approach(cause: str | None, tally: dict, tried: set[str]) -> str:
    """No gain: come back around with something DIFFERENT. First an untried
    strategy from the diagnosed cause's family, then an untried strategy from any
    other family (other modality, analogy, framing, pacing); when every approach
    has been tried for this concept, the one that has worked best for this
    learner (the tally), rendered fresh."""
    fam = STRATEGIES.get(cause or "unknown", STRATEGIES["unknown"])
    for s in fam + ROTATION:
        if s not in tried:
            return s
    return choose_strategy(cause or "unknown", tally)


def run_goal(store: Store, course_key: str | None,
             render: Callable[[str, str, int, str, int], Expression],
             learner: Callable[[Expression, str, str, str], Evidence],
             target_concept: str, seed: int = 7, *, goal_text: str | None = None,
             goal_source: str = "self", plan: dict | None = None,
             helpers: list[str] | None = None, session_attempts: int = 24,
             accept_help: Callable[[str], bool] | None = None) -> LoopResult:
    """Run one sitting of the loop for a new goal.

    With a course_key the authority's course drives the goal. With course_key
    None (no institution at all) the learner's skill file plus a self-set or
    open-corpus goal drive it; `plan` carries the concept graph
    {"concepts": {key: [prereqs]}} and monitoring and help go only to `helpers`,
    which the store checks against helpers named in the learner's skill file.

    The goal persists. Nothing here stops, parks or declares it stuck. No gain
    means a different approach next time, never the same content again. Every
    `rotate_every` attempts without mastery, help from a person is OFFERED;
    `accept_help(concept)` is the learner's answer. The sitting ends after
    `session_attempts` (the learner's session length), with the goal still active."""
    skill = (store.q("SELECT params FROM skill_file") or [{"params": {}}])[0]["params"]
    prof = (store.q("SELECT signals FROM learner_profile") or [{"signals": {}}])[0]["signals"]
    if course_key is not None:
        course = store.q("SELECT * FROM course_context WHERE course_key = %s", (course_key,))[0]
        concepts = {r["concept_key"]: r for r in
                    store.q("SELECT concept_key, prereqs FROM course_concept WHERE course_id = %s", (course["id"],))}
        goal = store.q("INSERT INTO loop_goal (course_id) VALUES (%s)"
                       " RETURNING id, mastery_threshold, rotate_every, help_seats", (course["id"],))[0]
        window, min_gain = course["no_gain_window"], float(course["min_gain"])
    else:
        concepts = {k: {"prereqs": v} for k, v in (plan or {}).get("concepts", {}).items()}
        hs = list(helpers or [])
        goal = store.q("INSERT INTO loop_goal (goal_text, goal_source, plan, monitor_to, help_seats)"
                       " VALUES (%s, %s, %s::jsonb, %s::text[], %s::text[])"
                       " RETURNING id, mastery_threshold, rotate_every, help_seats",
                       (goal_text, goal_source, json.dumps(plan or {}), hs, hs))[0]
        window, min_gain = NO_COURSE_DEFAULTS["no_gain_window"], NO_COURSE_DEFAULTS["min_gain"]
    gid, thr, rotate = goal["id"], float(goal["mastery_threshold"]), goal["rotate_every"]
    seats = goal["help_seats"]

    tally = {(r["cause"], r["strategy"]): (r["tries"], r["successes"])
             for r in store.q("SELECT cause, strategy, tries, successes FROM strategy_tally")}

    stack = [target_concept]          # backtrack stack; top = concept being taught
    cause, strategy, level = None, "baseline", None
    scores: list[float] = []
    path: list[tuple[str, str, float]] = []
    causes_tried: list[str] = []
    tried: dict[str, set[str]] = {}   # concept -> strategies tried
    used_hashes: set[str] = set()     # never deliver identical content twice
    prev_score = None
    since_mastery, offers, help_id = 0, 0, None

    for it in range(1, session_attempts + 1):
        concept = stack[-1]
        level, modality = presentation(skill, prof, 2, cause, strategy, level)
        # never deliver identical content twice: if this rendering was already shown,
        # ask the generator for a new variant (new seed); if it cannot vary, change approach
        variant = 0
        expr = render(concept, strategy, level, modality, seed)
        while expr.sha256 in used_hashes:
            variant += 1
            if variant > 5:
                strategy = next_approach("unknown", tally, tried.get(concept, set()) | {strategy})
                level, modality = presentation(skill, prof, 2, cause, strategy, level)
                variant = 0
            expr = render(concept, strategy, level, modality, seed + 1000 * variant)
        used_hashes.add(expr.sha256)
        tried.setdefault(concept, set()).add(strategy)
        att = store.q(
            "INSERT INTO loop_attempt (goal_id, iteration, concept_key, strategy, cause_targeted, level, modality,"
            " expression_sha256, model_id, seed, temperature) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",
            (gid, it, concept, strategy, cause, level, modality, expr.sha256, expr.model_id,
             expr.seed, expr.temperature))[0]["id"]
        ev = learner(expr, concept, strategy, modality)
        a = assess(ev, thr)
        store.q("INSERT INTO assessment (attempt_id, pass, score, cause, cause_concept, evidence) "
                "VALUES (%s,%s,%s,%s,%s,%s)",
                (att, a.passed, a.score, a.cause, a.cause_concept, json.dumps(a.evidence)))
        path.append((concept, strategy, a.score))
        since_mastery += 1

        # credit the strategy used on this attempt (success = pass, or gain >= min_gain)
        if cause is not None:
            success = a.passed or (prev_score is not None and a.score - prev_score >= min_gain)
            t, w = tally.get((cause, strategy), (0, 0))
            tally[(cause, strategy)] = (t + 1, w + int(success))
            store.q("INSERT INTO strategy_tally (cause, strategy, tries, successes) VALUES (%s,%s,1,%s) "
                    "ON CONFLICT (holon, cause, strategy) DO UPDATE SET tries = strategy_tally.tries + 1,"
                    " successes = strategy_tally.successes + EXCLUDED.successes",
                    (cause, strategy, int(success)))
        before, prev_score = prev_score, a.score

        if a.passed:
            # remediation evidence (section E.3): enumerated fields only
            rem = {"strategy": strategy, "level": level, "modality": modality,
                   "remediated": cause is not None,
                   "gain": round(max(-1.0, min(1.0, a.score - before)), 3) if before is not None else None}
            if len(stack) == 1:                                   # target mastered
                _monitor(store, gid, a.score, True, "ready_to_advance", concept, it, **rem)
                store.q("UPDATE skill_file SET achievements = achievements || %s::jsonb",
                        (json.dumps([{"course": course_key or goal_text, "concept": concept,
                                      "score": a.score}]),))
                store.q("UPDATE loop_goal SET status = 'mastered' WHERE id = %s", (gid,))
                return LoopResult("mastered", it, path, help_id, offers)
            _monitor(store, gid, a.score, False, "in_progress", concept, it, **rem)
            stack.pop()                                           # prerequisite rebuilt: forward one edge
            cause, strategy, scores, since_mastery = None, "baseline", [], 0
            continue

        # backtrack rule: prerequisite error share over threshold -> back ONE edge
        if a.cause == "missing_prerequisite" and a.cause_concept in concepts.get(concept, {}).get("prereqs", []):
            stack.append(a.cause_concept)
            _monitor(store, gid, a.score, False, "prereq_gap", a.cause_concept, it)
            cause, strategy, scores = a.cause, "backtrack_prerequisite", []
            causes_tried.append(a.cause)
            continue

        cause = a.cause
        causes_tried.append(cause)
        strategy = next_approach(cause, tally, tried.get(concept, set()))
        scores.append(a.score)
        # no gain over the window: come back around from a different family of approaches
        if len(scores) > window and max(scores[-window:]) - max(scores[:-window]) < min_gain:
            strategy = next_approach("unknown", tally, tried.get(concept, set()))
            _monitor(store, gid, a.score, False, "new_approach", concept, it)
            scores = []
        # every `rotate` attempts without mastery: OFFER a person's help (never a hand-off)
        if since_mastery % rotate == 0 and seats:
            offers += 1
            _monitor(store, gid, a.score, False, "help_offered", concept, it)
            if help_id is None and accept_help is not None and accept_help(concept):
                help_id = _ask_help(store, gid, concept, "offer_accepted", it, causes_tried)

    return LoopResult("active", session_attempts, path, help_id, offers)


def _monitor(store, gid, score, mastery, code, concept, iterations, strategy=None, level=None,
             modality=None, remediated=False, gain=None):
    store.q("INSERT INTO monitoring (goal_id, course_id, score, mastery, guidance_code, concept_key, iterations,"
            " strategy, level, modality, remediated, gain)"
            " VALUES (%s, NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (gid, score, mastery, code, concept, iterations, strategy, level, modality, remediated, gain))


def _ask_help(store, gid, concept, reason, attempted, causes_tried) -> int | None:
    """The learner took up the offer (or asked): open a help record to the first
    help seat of the goal. The goal stays active; the loop keeps going."""
    seats = store.q("SELECT help_seats FROM loop_goal WHERE id = %s", (gid,))[0]["help_seats"]
    if not seats:
        return None
    return store.q("INSERT INTO help_record (addressed_to, goal_id, concept_key, reason, attempted,"
                   " causes_tried) VALUES (%s,%s,%s,%s,%s,%s::text[]) RETURNING id",
                   (seats[0], gid, concept, reason, attempted, sorted(set(causes_tried))))[0]["id"]


def skill_context_for_engine(store: Store, engine_id: str) -> dict:
    """What the loop may pass to a model engine (section A.8, statement 83).
    The narrative goes only to an engine the holder listed in readable_by_engines;
    any other engine gets presentation parameters only."""
    rows = store.q("SELECT body, params, readable_by_engines FROM skill_file WHERE holon = current_holon()")
    if not rows:
        return {"params": {}}
    r = rows[0]
    out = {"params": {k: r["params"][k] for k in ("default_level", "modality", "session_minutes",
                                                  "accessibility") if k in r["params"]}}
    if engine_id in (r["readable_by_engines"] or []):
        out["narrative"] = r["body"]
    return out


def readdress(store: Store, help_id: int) -> str:
    """Run by the loop when a help record is back at needs_help with nobody
    addressed (a decline re-opened it). Next seat from the course roster that
    has not declined; park with a reason when the roster or pass limit runs out."""
    h = store.q("SELECT h.*, g.help_seats, g.max_help_passes FROM help_record h"
                " JOIN loop_goal g ON g.id = h.goal_id WHERE h.id = %s", (help_id,))[0]
    if h["status"] != "needs_help" or h["addressed_to"]:
        return "unchanged"
    remaining = [s for s in h["help_seats"] if s not in h["declined_by"]]
    if not remaining or h["passes"] >= h["max_help_passes"]:
        code = "pass_limit" if h["passes"] >= h["max_help_passes"] else "no_seat_accepted"
        store.q("UPDATE help_record SET status = 'parked', park_reason = %s WHERE id = %s", (code, help_id))
        return "parked"
    store.q("UPDATE help_record SET addressed_to = %s WHERE id = %s", (remaining[0], help_id))
    return remaining[0]
