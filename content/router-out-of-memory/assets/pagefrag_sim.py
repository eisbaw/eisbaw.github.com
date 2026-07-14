#!/usr/bin/env python3
"""Deterministic Linux 6.12.87 page_frag_cache mechanism simulator.

This validates allocator and lifetime-mixing mechanisms only.  It cannot prove
live ath11k ownership or firmware behaviour.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Iterable, Sequence


PAGE_SIZE = 4096
PAGE_FRAG_CACHE_MAX_SIZE = 32768
PAGE_FRAG_CACHE_BIAS = PAGE_FRAG_CACHE_MAX_SIZE + 1


@dataclass
class Page:
    """One physical compound or order-0 allocation."""

    page_id: int
    size: int
    pfmemalloc: bool
    refcount: int = 1
    freed: bool = False
    ever_rings: set[str] = field(default_factory=set)
    ever_lifetimes: set[str] = field(default_factory=set)


@dataclass(frozen=True)
class Fragment:
    """A fragment reference returned by page_frag_alloc()."""

    fragment_id: int
    page_id: int
    offset: int
    size: int


class PhysicalAllocator:
    """Deterministic backing-page source with controllable refill properties."""

    def __init__(
        self,
        *,
        fallback_refills: set[int] | None = None,
        pfmemalloc_refills: set[int] | None = None,
    ) -> None:
        self.fallback_refills = fallback_refills or set()
        self.pfmemalloc_refills = pfmemalloc_refills or set()
        self.refill_attempts = 0
        self._next_page_id = 1
        self.pages: dict[int, Page] = {}
        self.frees = 0

    def allocate(self) -> Page:
        self.refill_attempts += 1
        size = (
            PAGE_SIZE
            if self.refill_attempts in self.fallback_refills
            else PAGE_FRAG_CACHE_MAX_SIZE
        )
        page = Page(
            page_id=self._next_page_id,
            size=size,
            pfmemalloc=self.refill_attempts in self.pfmemalloc_refills,
        )
        self._next_page_id += 1
        self.pages[page.page_id] = page
        return page

    def free_page(self, page: Page) -> None:
        if page.refcount != 0:
            raise AssertionError("freeing a page with live references")
        if page.freed:
            raise AssertionError("double page free")
        page.freed = True
        self.frees += 1


class PageFragCache:
    """Literal relevant state machine from Linux 6.12.87 page_alloc.c."""

    def __init__(self, allocator: PhysicalAllocator) -> None:
        self.allocator = allocator
        self.page: Page | None = None
        self.offset = 0
        self.pagecnt_bias = 0
        self.pfmemalloc = False
        self.refills = 0
        self.reuses = 0
        self._next_fragment_id = 1
        self._live: dict[int, Fragment] = {}

    def _refill(self) -> None:
        page = self.allocator.allocate()
        page.refcount += PAGE_FRAG_CACHE_MAX_SIZE
        self.page = page
        self.offset = page.size
        self.pagecnt_bias = PAGE_FRAG_CACHE_BIAS
        self.pfmemalloc = page.pfmemalloc
        self.refills += 1

    def allocate(self, size: int) -> Fragment | None:
        if size <= 0:
            raise ValueError("fragment size must be positive")
        if self.page is None:
            self._refill()

        assert self.page is not None
        offset = self.offset - size
        if offset < 0:
            old_page = self.page
            old_page.refcount -= self.pagecnt_bias
            if old_page.refcount < 0:
                raise AssertionError("page bias exceeded refcount")

            if old_page.refcount != 0:
                self._refill()
            elif self.pfmemalloc:
                self.allocator.free_page(old_page)
                self._refill()
            else:
                old_page.refcount = PAGE_FRAG_CACHE_BIAS
                self.pagecnt_bias = PAGE_FRAG_CACHE_BIAS
                self.reuses += 1

            assert self.page is not None
            offset = self.page.size - size if self.page is old_page else self.offset - size
            if offset < 0:
                # Kernel keeps this undersized cache page and returns NULL.
                return None

        self.pagecnt_bias -= 1
        self.offset = offset
        fragment = Fragment(
            fragment_id=self._next_fragment_id,
            page_id=self.page.page_id,
            offset=offset,
            size=size,
        )
        self._next_fragment_id += 1
        self._live[fragment.fragment_id] = fragment
        return fragment

    def free(self, fragment: Fragment) -> None:
        if self._live.pop(fragment.fragment_id, None) != fragment:
            raise AssertionError("unknown or already-freed fragment")
        page = self.allocator.pages[fragment.page_id]
        page.refcount -= 1
        if page.refcount < 0:
            raise AssertionError("negative page refcount")
        if page.refcount == 0:
            self.allocator.free_page(page)

    def drain(self) -> None:
        if self.page is None:
            return
        page = self.page
        page.refcount -= self.pagecnt_bias
        if page.refcount < 0:
            raise AssertionError("page bias exceeded refcount")
        if page.refcount == 0:
            self.allocator.free_page(page)
        self.page = None
        self.offset = 0
        self.pagecnt_bias = 0
        self.pfmemalloc = False


MECHANISM_WARNING = (
    "MECHANISM VALIDATION ONLY; not proof of live ath11k ownership or firmware behaviour"
)
SENSITIVITY_WARNING = (
    "SENSITIVITY ASSIGNMENT; owner ring and lifetime mapping is inferred from right-censored captures"
)

POLICIES = ("shared", "per_ring", "same_ring_only", "non_pagefrag")
POLICY_DESCRIPTIONS = {
    "shared": "one existing-style cache per CPU lane shared by every source and ring",
    "per_ring": "one private cache per RXDMA ring while CE stays on per-lane caches",
    "same_ring_only": "one isolated cache per owner and ring including CE independent of CPU lane",
    "non_pagefrag": "one independently freed page-rounded backing allocation per fragment",
}
LANE_WEIGHTS = (745, 468, 182, 130)


@dataclass(frozen=True, order=True)
class Event:
    """One policy-independent logical action in integer nanoseconds."""

    time_ns: int
    seq: int
    action: str
    logical_id: int
    source: str
    ring: str
    lane: str
    lifetime: str
    requested_bytes: int = 0
    aligned_bytes: int = 0
    slot: int = -1

    def row(self) -> dict[str, int | str]:
        return asdict(self)


EVENT_FIELDS = tuple(Event.__dataclass_fields__)


@dataclass(frozen=True)
class SimulationConfig:
    seed: int = 1
    duration_ns: int = 30_000_000_000
    sample_ns: int = 1_000_000_000
    radios: int = 3
    data_capacity: int = 4095
    monitor_capacity: int = 1024
    data_rate: Decimal = Decimal("25.3")
    monitor_rate: Decimal = Decimal("183.6")
    ce_rate: Decimal = Decimal("173.6")
    data_hold_ns: int = 12_000_000_000
    monitor_hold_ns: int = 20_000_000
    ce_hold_ns: int = 5_000_000
    lifetime_jitter_percent: int = 50
    burst_max: int = 8
    lane_weights: tuple[int, ...] = LANE_WEIGHTS

    def validate(self) -> None:
        if self.duration_ns <= 0:
            raise ValueError("duration must be positive")
        if self.sample_ns <= 0:
            raise ValueError("sample interval must be positive")
        if self.radios <= 0 or self.data_capacity <= 0 or self.monitor_capacity <= 0:
            raise ValueError("ring counts and capacities must be positive")
        if min(self.data_rate, self.monitor_rate, self.ce_rate) < 0:
            raise ValueError("rates cannot be negative")
        if min(self.data_hold_ns, self.monitor_hold_ns, self.ce_hold_ns) <= 0:
            raise ValueError("lifetimes must be positive")
        if not 0 <= self.lifetime_jitter_percent <= 100:
            raise ValueError("lifetime jitter must be between 0 and 100 percent")
        if self.burst_max <= 0:
            raise ValueError("burst-max must be positive")
        if not self.lane_weights or min(self.lane_weights) <= 0:
            raise ValueError("lane weights must all be positive")


class SplitMix64:
    """Small version-stable PRNG used only while freezing the event stream."""

    _MASK = (1 << 64) - 1

    def __init__(self, seed: int) -> None:
        self.state = seed & self._MASK

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self._MASK
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & self._MASK
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & self._MASK
        return value ^ (value >> 31)

    def below(self, bound: int) -> int:
        if bound <= 0:
            raise ValueError("bound must be positive")
        return self.next_u64() % bound

    def shuffle(self, values: list[object]) -> None:
        for index in range(len(values) - 1, 0, -1):
            other = self.below(index + 1)
            values[index], values[other] = values[other], values[index]


class EventBuilder:
    """Generates and then freezes logical traffic; replays never call this RNG."""

    def __init__(self, config: SimulationConfig) -> None:
        self.config = config
        self.rng = SplitMix64(config.seed)
        self.events: list[Event] = []
        self.next_seq = 0
        self.next_logical_id = 1
        self.slots: dict[str, list[int]] = {}

    def _add(self, time_ns: int, action: str, logical_id: int, **fields: object) -> None:
        if time_ns > self.config.duration_ns:
            return
        self.events.append(
            Event(
                time_ns=time_ns,
                seq=self.next_seq,
                action=action,
                logical_id=logical_id,
                **fields,
            )
        )
        self.next_seq += 1

    def _new_logical_id(self) -> int:
        logical_id = self.next_logical_id
        self.next_logical_id += 1
        return logical_id

    def _lane(self) -> str:
        roll = self.rng.below(sum(self.config.lane_weights))
        for index, weight in enumerate(self.config.lane_weights):
            if roll < weight:
                return f"lane{index}"
            roll -= weight
        raise AssertionError("unreachable weighted lane selection")

    def _lifetime(self, base_ns: int) -> int:
        spread = base_ns * self.config.lifetime_jitter_percent // 100
        if spread == 0:
            return base_ns
        return max(1, base_ns - spread + self.rng.below(2 * spread + 1))

    def _event_times(self, rate: Decimal) -> list[int]:
        exact = rate * Decimal(self.config.duration_ns) / Decimal(1_000_000_000)
        count = int(exact.to_integral_value(rounding=ROUND_HALF_UP))
        if count == 0:
            return []
        nominal_gap = max(1, self.config.duration_ns // (count + 1))
        times: list[int] = []
        emitted = 0
        while emitted < count:
            remaining = count - emitted
            burst = 1 + self.rng.below(min(self.config.burst_max, remaining))
            anchor = (emitted + 1) * self.config.duration_ns // (count + 1)
            jitter_span = nominal_gap // 3
            if jitter_span:
                anchor += self.rng.below(2 * jitter_span + 1) - jitter_span
            spacing = max(1, min(100_000, nominal_gap // 100))
            for within in range(burst):
                times.append(min(self.config.duration_ns, max(1, anchor + within * spacing)))
            emitted += burst
        return sorted(times)

    def _post(
        self,
        *,
        time_ns: int,
        source: str,
        ring: str,
        lifetime: str,
        requested: int,
        aligned: int,
        slot: int,
    ) -> int:
        logical_id = self._new_logical_id()
        self._add(
            time_ns,
            "post",
            logical_id,
            source=source,
            ring=ring,
            lane=self._lane(),
            lifetime=lifetime,
            requested_bytes=requested,
            aligned_bytes=aligned,
            slot=slot,
        )
        return logical_id

    def seed_rings(self) -> None:
        seeds: list[tuple[str, str, str, int, int, int]] = []
        for radio in range(self.config.radios):
            data_ring = f"data{radio}"
            monitor_ring = f"monitor{radio}"
            self.slots[data_ring] = [0] * self.config.data_capacity
            self.slots[monitor_ring] = [0] * self.config.monitor_capacity
            seeds.extend(
                ("data", data_ring, "long", 2176, 2560, slot)
                for slot in range(self.config.data_capacity)
            )
            seeds.extend(
                ("monitor_status", monitor_ring, "short", 2176, 2560, slot)
                for slot in range(self.config.monitor_capacity)
            )
        self.rng.shuffle(seeds)
        for source, ring, lifetime, requested, aligned, slot in seeds:
            logical_id = self._post(
                time_ns=0,
                source=source,
                ring=ring,
                lifetime=lifetime,
                requested=requested,
                aligned=aligned,
                slot=slot,
            )
            self.slots[ring][slot] = logical_id

    def add_ring_turnover(
        self,
        *,
        source: str,
        ring_prefix: str,
        lifetime: str,
        requested: int,
        aligned: int,
        rate: Decimal,
        hold_ns: int,
    ) -> None:
        for time_ns in self._event_times(rate):
            radio = self.rng.below(self.config.radios)
            ring = f"{ring_prefix}{radio}"
            slot = self.rng.below(len(self.slots[ring]))
            old_id = self.slots[ring][slot]
            common = dict(
                source=source,
                ring=ring,
                lane="",
                lifetime=lifetime,
                requested_bytes=0,
                aligned_bytes=0,
                slot=slot,
            )
            self._add(time_ns, "reap", old_id, **common)
            new_id = self._post(
                time_ns=time_ns,
                source=source,
                ring=ring,
                lifetime=lifetime,
                requested=requested,
                aligned=aligned,
                slot=slot,
            )
            self.slots[ring][slot] = new_id
            self._add(
                time_ns + self._lifetime(hold_ns),
                "free",
                old_id,
                **common,
            )

    def add_ce_transients(self) -> None:
        for time_ns in self._event_times(self.config.ce_rate):
            logical_id = self._new_logical_id()
            lane = self._lane()
            radio = self.rng.below(self.config.radios)
            common = dict(
                source="ce",
                ring=f"ce{radio}",
                lane=lane,
                lifetime="short",
                slot=-1,
            )
            self._add(
                time_ns,
                "alloc",
                logical_id,
                requested_bytes=2048,
                aligned_bytes=2432,
                **common,
            )
            self._add(
                time_ns + self._lifetime(self.config.ce_hold_ns),
                "free",
                logical_id,
                requested_bytes=0,
                aligned_bytes=0,
                **common,
            )

    def build(self) -> tuple[Event, ...]:
        self.seed_rings()
        self.add_ring_turnover(
            source="data",
            ring_prefix="data",
            lifetime="long",
            requested=2176,
            aligned=2560,
            rate=self.config.data_rate,
            hold_ns=self.config.data_hold_ns,
        )
        self.add_ring_turnover(
            source="monitor_status",
            ring_prefix="monitor",
            lifetime="short",
            requested=2176,
            aligned=2560,
            rate=self.config.monitor_rate,
            hold_ns=self.config.monitor_hold_ns,
        )
        self.add_ce_transients()
        return tuple(sorted(self.events))


def generate_events(config: SimulationConfig) -> tuple[Event, ...]:
    config.validate()
    return EventBuilder(config).build()


def normalized_event_bytes(events: Sequence[Event]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=EVENT_FIELDS, lineterminator="\n")
    writer.writeheader()
    for event in events:
        writer.writerow(event.row())
    return stream.getvalue().encode("utf-8")


def event_stream_hash(events: Sequence[Event]) -> str:
    return hashlib.sha256(normalized_event_bytes(events)).hexdigest()


@dataclass
class PageUsage:
    requested_bytes: int = 0
    aligned_bytes: int = 0
    fragments: int = 0
    rings: Counter[str] = field(default_factory=Counter)
    lifetimes: Counter[str] = field(default_factory=Counter)


@dataclass
class Aggregate:
    unique_pages: int = 0
    requested_bytes: int = 0
    aligned_bytes: int = 0
    backing_bytes: int = 0
    slack_bytes: int = 0
    current_mixed_pages: int = 0
    historical_cross_lifetime_pages: int = 0
    same_ring_only_pages: int = 0
    historical_cross_lifetime_slack_bytes: int = 0
    same_ring_only_slack_bytes: int = 0

    def add(self, other: "Aggregate", sign: int = 1) -> None:
        for name in self.__dataclass_fields__:
            setattr(self, name, getattr(self, name) + sign * getattr(other, name))


@dataclass
class LiveRecord:
    fragment: Fragment
    cache: PageFragCache | None
    source: str
    ring: str
    lifetime: str
    requested_bytes: int
    aligned_bytes: int
    state: str


@dataclass(frozen=True)
class ScenarioResult:
    policy: str
    timeline: tuple[dict[str, int | str], ...]
    summary: dict[str, int | str]


class ScenarioReplay:
    """Randomness-free replay of one already-frozen logical event stream."""

    def __init__(self, policy: str, config: SimulationConfig, event_hash: str) -> None:
        if policy not in POLICIES:
            raise ValueError(f"unknown policy: {policy}")
        self.policy = policy
        self.config = config
        self.event_hash = event_hash
        self.allocator = PhysicalAllocator()
        self.caches: dict[tuple[str, ...], PageFragCache] = {}
        self.direct_pages: dict[int, Page] = {}
        self.next_direct_page = 1
        self.live: dict[int, LiveRecord] = {}
        self.usage: dict[int, PageUsage] = {}
        self.aggregate = Aggregate()
        self.posted = 0
        self.reaped = 0
        self.allocations = 0
        self.direct_frees = 0
        self.last_integrated_ns = 0
        self.backing_byte_ns = 0
        self.slack_byte_ns = 0
        self.cross_lifetime_slack_byte_ns = 0
        self.same_ring_only_slack_byte_ns = 0

    @property
    def pages(self) -> dict[int, Page]:
        return self.direct_pages if self.policy == "non_pagefrag" else self.allocator.pages

    def _cache_key(self, event: Event) -> tuple[str, ...]:
        if self.policy == "shared":
            return ("lane", event.lane)
        if self.policy == "per_ring":
            if event.source == "ce":
                return ("ce-lane", event.lane)
            return ("ring", event.ring)
        if self.policy == "same_ring_only":
            return ("owner-ring", event.source, event.ring)
        raise AssertionError("non-page-frag has no cache")

    def _contribution(self, page_id: int) -> Aggregate:
        page = self.pages[page_id]
        if page.freed:
            return Aggregate()
        usage = self.usage.get(page_id, PageUsage())
        slack = page.size - usage.aligned_bytes
        if slack < 0:
            raise AssertionError("live fragments exceed backing page")
        current_mixed = usage.fragments > 0 and (
            len(usage.rings) > 1 or len(usage.lifetimes) > 1
        )
        historical_cross = usage.fragments > 0 and len(page.ever_lifetimes) > 1
        same_ring_only = usage.fragments > 0 and len(page.ever_rings) == 1
        return Aggregate(
            unique_pages=1,
            requested_bytes=usage.requested_bytes,
            aligned_bytes=usage.aligned_bytes,
            backing_bytes=page.size,
            slack_bytes=slack,
            current_mixed_pages=int(current_mixed),
            historical_cross_lifetime_pages=int(historical_cross),
            same_ring_only_pages=int(same_ring_only),
            historical_cross_lifetime_slack_bytes=slack if historical_cross else 0,
            same_ring_only_slack_bytes=slack if same_ring_only else 0,
        )

    def _remove_contribution(self, page_id: int) -> None:
        self.aggregate.add(self._contribution(page_id), -1)

    def _add_contribution(self, page_id: int) -> None:
        self.aggregate.add(self._contribution(page_id), 1)

    def _usage_add(self, page_id: int, event: Event) -> None:
        usage = self.usage.setdefault(page_id, PageUsage())
        usage.requested_bytes += event.requested_bytes
        usage.aligned_bytes += event.aligned_bytes
        usage.fragments += 1
        usage.rings[event.ring] += 1
        usage.lifetimes[event.lifetime] += 1
        page = self.pages[page_id]
        page.ever_rings.add(event.ring)
        page.ever_lifetimes.add(event.lifetime)

    def _usage_remove(self, record: LiveRecord) -> None:
        page_id = record.fragment.page_id
        usage = self.usage[page_id]
        usage.requested_bytes -= record.requested_bytes
        usage.aligned_bytes -= record.aligned_bytes
        usage.fragments -= 1
        usage.rings[record.ring] -= 1
        usage.lifetimes[record.lifetime] -= 1
        if usage.rings[record.ring] == 0:
            del usage.rings[record.ring]
        if usage.lifetimes[record.lifetime] == 0:
            del usage.lifetimes[record.lifetime]
        if usage.fragments == 0:
            if usage.requested_bytes or usage.aligned_bytes or usage.rings or usage.lifetimes:
                raise AssertionError("empty page usage retains accounting")

    def _allocate_pagefrag(self, event: Event) -> tuple[PageFragCache, Fragment]:
        key = self._cache_key(event)
        cache = self.caches.setdefault(key, PageFragCache(self.allocator))
        old_page_id = cache.page.page_id if cache.page else None
        if old_page_id is not None:
            self._remove_contribution(old_page_id)
        fragment = cache.allocate(event.aligned_bytes)
        affected = {page_id for page_id in (old_page_id, cache.page.page_id) if page_id}
        if fragment is None:
            for page_id in affected:
                self._add_contribution(page_id)
            raise MemoryError("capture-sized allocation unexpectedly failed")
        self._usage_add(fragment.page_id, event)
        for page_id in affected:
            self._add_contribution(page_id)
        return cache, fragment

    def _allocate_direct(self, event: Event) -> tuple[None, Fragment]:
        page_id = self.next_direct_page
        self.next_direct_page += 1
        backing = ((event.aligned_bytes + PAGE_SIZE - 1) // PAGE_SIZE) * PAGE_SIZE
        page = Page(page_id=page_id, size=backing, pfmemalloc=False)
        self.direct_pages[page_id] = page
        fragment = Fragment(
            fragment_id=event.logical_id,
            page_id=page_id,
            offset=0,
            size=event.aligned_bytes,
        )
        self._usage_add(page_id, event)
        self._add_contribution(page_id)
        return None, fragment

    def _allocate(self, event: Event, state: str) -> None:
        if event.logical_id in self.live:
            raise AssertionError("logical allocation ID reused")
        cache, fragment = (
            self._allocate_direct(event)
            if self.policy == "non_pagefrag"
            else self._allocate_pagefrag(event)
        )
        self.live[event.logical_id] = LiveRecord(
            fragment=fragment,
            cache=cache,
            source=event.source,
            ring=event.ring,
            lifetime=event.lifetime,
            requested_bytes=event.requested_bytes,
            aligned_bytes=event.aligned_bytes,
            state=state,
        )
        self.allocations += 1
        if state == "posted":
            self.posted += 1
        else:
            self.reaped += 1

    def _reap(self, event: Event) -> None:
        record = self.live[event.logical_id]
        if record.state != "posted":
            raise AssertionError("reap did not target a posted buffer")
        record.state = "reaped"
        self.posted -= 1
        self.reaped += 1

    def _free(self, event: Event) -> None:
        record = self.live.pop(event.logical_id)
        if record.state != "reaped":
            raise AssertionError("free did not follow reap/allocation")
        page_id = record.fragment.page_id
        self._remove_contribution(page_id)
        self._usage_remove(record)
        if record.cache is None:
            page = self.direct_pages[page_id]
            page.refcount = 0
            page.freed = True
            self.direct_frees += 1
        else:
            record.cache.free(record.fragment)
        self._add_contribution(page_id)
        self.reaped -= 1

    def _process(self, event: Event) -> None:
        if event.action == "post":
            self._allocate(event, "posted")
        elif event.action == "alloc":
            self._allocate(event, "reaped")
        elif event.action == "reap":
            self._reap(event)
        elif event.action == "free":
            self._free(event)
        else:
            raise AssertionError(f"unknown event action {event.action}")

    def _integrate_to(self, time_ns: int) -> None:
        delta = time_ns - self.last_integrated_ns
        if delta < 0:
            raise AssertionError("event time moved backwards")
        self.backing_byte_ns += self.aggregate.backing_bytes * delta
        self.slack_byte_ns += self.aggregate.slack_bytes * delta
        self.cross_lifetime_slack_byte_ns += (
            self.aggregate.historical_cross_lifetime_slack_bytes * delta
        )
        self.same_ring_only_slack_byte_ns += self.aggregate.same_ring_only_slack_bytes * delta
        self.last_integrated_ns = time_ns

    def _stats(self, time_ns: int) -> dict[str, int | str]:
        refills = sum(cache.refills for cache in self.caches.values())
        reuses = sum(cache.reuses for cache in self.caches.values())
        frees = self.direct_frees if self.policy == "non_pagefrag" else self.allocator.frees
        return {
            "policy": self.policy,
            "time_ns": time_ns,
            "live_fragments": len(self.live),
            "posted_fragments": self.posted,
            "reaped_fragments": self.reaped,
            "global_unique_pages": self.aggregate.unique_pages,
            "requested_bytes": self.aggregate.requested_bytes,
            "aligned_bytes": self.aggregate.aligned_bytes,
            "backing_bytes": self.aggregate.backing_bytes,
            "slack_bytes": self.aggregate.slack_bytes,
            "current_mixed_pages": self.aggregate.current_mixed_pages,
            "historical_cross_lifetime_pages": self.aggregate.historical_cross_lifetime_pages,
            "same_ring_only_pages": self.aggregate.same_ring_only_pages,
            "historical_cross_lifetime_slack_bytes": self.aggregate.historical_cross_lifetime_slack_bytes,
            "same_ring_only_slack_bytes": self.aggregate.same_ring_only_slack_bytes,
            "refills": refills,
            "reuses": reuses,
            "frees": frees,
            "warning": MECHANISM_WARNING,
            "sensitivity": SENSITIVITY_WARNING,
            "event_sha256": self.event_hash,
        }

    def replay(self, events: Sequence[Event]) -> ScenarioResult:
        timeline: list[dict[str, int | str]] = []
        next_sample = 0
        index = 0
        while index < len(events):
            time_ns = events[index].time_ns
            while next_sample < time_ns and next_sample <= self.config.duration_ns:
                timeline.append(self._stats(next_sample))
                next_sample += self.config.sample_ns
            self._integrate_to(time_ns)
            while index < len(events) and events[index].time_ns == time_ns:
                self._process(events[index])
                index += 1
            if next_sample == time_ns:
                timeline.append(self._stats(next_sample))
                next_sample += self.config.sample_ns

        self._integrate_to(self.config.duration_ns)
        while next_sample <= self.config.duration_ns:
            timeline.append(self._stats(next_sample))
            next_sample += self.config.sample_ns

        summary = self._stats(self.config.duration_ns)
        summary.update(
            {
                "seed": self.config.seed,
                "duration_ns": self.config.duration_ns,
                "events": len(events),
                "allocations": self.allocations,
                "backing_byte_ns": self.backing_byte_ns,
                "slack_byte_ns": self.slack_byte_ns,
                "historical_cross_lifetime_slack_byte_ns": self.cross_lifetime_slack_byte_ns,
                "same_ring_only_slack_byte_ns": self.same_ring_only_slack_byte_ns,
                "data_rate_per_second": str(self.config.data_rate),
                "monitor_rate_per_second": str(self.config.monitor_rate),
                "ce_rate_per_second": str(self.config.ce_rate),
                "data_capacity_total": self.config.data_capacity * self.config.radios,
                "monitor_capacity_total": self.config.monitor_capacity * self.config.radios,
                "lane_weights": ":".join(str(weight) for weight in self.config.lane_weights),
                "burst_max": self.config.burst_max,
                "data_hold_ns": self.config.data_hold_ns,
                "monitor_hold_ns": self.config.monitor_hold_ns,
                "ce_hold_ns": self.config.ce_hold_ns,
                "lifetime_jitter_percent": self.config.lifetime_jitter_percent,
                "policy_cache_scope": POLICY_DESCRIPTIONS[self.policy],
            }
        )
        return ScenarioResult(self.policy, tuple(timeline), summary)


def replay_all(config: SimulationConfig, events: Sequence[Event]) -> tuple[ScenarioResult, ...]:
    digest = event_stream_hash(events)
    return tuple(ScenarioReplay(policy, config, digest).replay(events) for policy in POLICIES)


def _write_dict_csv(path: Path, rows: Iterable[dict[str, int | str]]) -> None:
    rows = list(rows)
    if not rows:
        raise ValueError(f"refusing to write empty CSV: {path}")
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=tuple(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_outputs(
    output: Path,
    events: Sequence[Event],
    results: Sequence[ScenarioResult],
) -> None:
    output.mkdir(parents=True, exist_ok=True)
    (output / "events.csv").write_bytes(normalized_event_bytes(events))
    _write_dict_csv(output / "summary.csv", (result.summary for result in results))
    _write_dict_csv(
        output / "timeline.csv",
        (row for result in results for row in result.timeline),
    )


def _seconds_ns(value: str, name: str) -> int:
    try:
        seconds = Decimal(value)
    except InvalidOperation as error:
        raise argparse.ArgumentTypeError(f"{name} must be decimal seconds") from error
    if not seconds.is_finite():
        raise argparse.ArgumentTypeError(f"{name} must be finite")
    nanoseconds = int((seconds * Decimal(1_000_000_000)).to_integral_value(ROUND_HALF_UP))
    if nanoseconds <= 0:
        raise argparse.ArgumentTypeError(f"{name} must be positive")
    return nanoseconds


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Replay one deterministic traffic stream through page-frag cache policies. "
            + MECHANISM_WARNING
        ),
        epilog="; ".join(f"{policy}: {POLICY_DESCRIPTIONS[policy]}" for policy in POLICIES),
    )
    parser.add_argument("--seed", type=int, default=1, help="deterministic event-stream seed")
    parser.add_argument("--duration", default="30", help="simulated seconds")
    parser.add_argument("--sample", default="1", help="timeline sample interval in seconds")
    parser.add_argument("--output", type=Path, default=Path("pagefrag-sim-output"))
    parser.add_argument("--burst-max", type=int, default=8, help="maximum uniform burst size")
    parser.add_argument("--data-hold-ms", type=int, default=12_000)
    parser.add_argument("--monitor-hold-ms", type=int, default=20)
    parser.add_argument("--ce-hold-ms", type=int, default=5)
    parser.add_argument(
        "--lifetime-jitter-percent",
        type=int,
        default=50,
        help="uniform symmetric lifetime jitter percentage",
    )
    return parser.parse_args(argv)


def config_from_args(args: argparse.Namespace) -> SimulationConfig:
    return SimulationConfig(
        seed=args.seed,
        duration_ns=_seconds_ns(args.duration, "duration"),
        sample_ns=_seconds_ns(args.sample, "sample"),
        data_hold_ns=args.data_hold_ms * 1_000_000,
        monitor_hold_ns=args.monitor_hold_ms * 1_000_000,
        ce_hold_ns=args.ce_hold_ms * 1_000_000,
        lifetime_jitter_percent=args.lifetime_jitter_percent,
        burst_max=args.burst_max,
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = config_from_args(args)
        events = generate_events(config)
        results = replay_all(config, events)
        write_outputs(args.output, events, results)
    except (argparse.ArgumentTypeError, AssertionError, MemoryError, ValueError) as error:
        print(f"pagefrag-sim: {error}", file=sys.stderr)
        return 2

    digest = event_stream_hash(events)
    print(MECHANISM_WARNING, file=sys.stderr)
    print(SENSITIVITY_WARNING, file=sys.stderr)
    print(f"event_sha256={digest}")
    print(f"events={len(events)} output={args.output}")
    for result in results:
        summary = result.summary
        print(
            f"policy={result.policy} pages={summary['global_unique_pages']} "
            f"backing={summary['backing_bytes']} slack={summary['slack_bytes']} "
            f"live={summary['live_fragments']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
