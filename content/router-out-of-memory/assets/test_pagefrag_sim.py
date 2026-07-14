#!/usr/bin/env python3

import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from pagefrag_sim import (
    MECHANISM_WARNING,
    POLICIES,
    PAGE_FRAG_CACHE_BIAS,
    PAGE_FRAG_CACHE_MAX_SIZE,
    PAGE_SIZE,
    Event,
    PageFragCache,
    PhysicalAllocator,
    ScenarioReplay,
    SimulationConfig,
    event_stream_hash,
    generate_events,
    replay_all,
    write_outputs,
)


class PageFragCacheTests(unittest.TestCase):
    def test_exact_2560_offsets(self) -> None:
        cache = PageFragCache(PhysicalAllocator())
        fragments = [cache.allocate(2560) for _ in range(12)]
        self.assertTrue(all(fragments))
        self.assertEqual(
            [fragment.offset for fragment in fragments if fragment],
            [PAGE_FRAG_CACHE_MAX_SIZE - 2560 * i for i in range(1, 13)],
        )

    def test_exact_2432_offsets(self) -> None:
        cache = PageFragCache(PhysicalAllocator())
        fragments = [cache.allocate(2432) for _ in range(13)]
        self.assertTrue(all(fragments))
        self.assertEqual(
            [fragment.offset for fragment in fragments if fragment],
            [PAGE_FRAG_CACHE_MAX_SIZE - 2432 * i for i in range(1, 14)],
        )

    def test_rollover_with_survivor_detaches_old_page(self) -> None:
        allocator = PhysicalAllocator()
        cache = PageFragCache(allocator)
        fragments = [cache.allocate(2560) for _ in range(12)]
        old_page = cache.page
        replacement = cache.allocate(2560)
        self.assertIsNotNone(replacement)
        self.assertIsNot(cache.page, old_page)
        self.assertEqual(old_page.refcount, 12)
        for fragment in fragments:
            cache.free(fragment)
        self.assertTrue(old_page.freed)

    def test_all_free_rollover_reuses_same_page(self) -> None:
        allocator = PhysicalAllocator()
        cache = PageFragCache(allocator)
        fragments = [cache.allocate(2560) for _ in range(12)]
        old_page = cache.page
        for fragment in fragments:
            cache.free(fragment)
        replacement = cache.allocate(2560)
        self.assertEqual(replacement.page_id, old_page.page_id)
        self.assertEqual(replacement.offset, PAGE_FRAG_CACHE_MAX_SIZE - 2560)
        self.assertEqual(cache.reuses, 1)
        self.assertEqual(cache.refills, 1)
        self.assertEqual(cache.pagecnt_bias, PAGE_FRAG_CACHE_BIAS - 1)

    def test_pfmemalloc_page_is_not_reused(self) -> None:
        allocator = PhysicalAllocator(pfmemalloc_refills={1})
        cache = PageFragCache(allocator)
        fragments = [cache.allocate(2560) for _ in range(12)]
        old_page = cache.page
        for fragment in fragments:
            cache.free(fragment)
        replacement = cache.allocate(2560)
        self.assertNotEqual(replacement.page_id, old_page.page_id)
        self.assertTrue(old_page.freed)
        self.assertEqual(cache.reuses, 0)

    def test_drain_releases_bias_then_last_fragment_frees(self) -> None:
        allocator = PhysicalAllocator()
        cache = PageFragCache(allocator)
        first = cache.allocate(2560)
        page = cache.page
        cache.drain()
        self.assertIsNone(cache.page)
        self.assertEqual(page.refcount, 1)
        self.assertFalse(page.freed)
        cache.free(first)
        self.assertTrue(page.freed)

    def test_order_zero_fallback_and_oversized_failure(self) -> None:
        allocator = PhysicalAllocator(fallback_refills={1, 2})
        cache = PageFragCache(allocator)
        first = cache.allocate(2560)
        self.assertEqual(cache.page.size, PAGE_SIZE)
        self.assertEqual(first.offset, PAGE_SIZE - 2560)
        self.assertIsNone(cache.allocate(5000))
        self.assertEqual(cache.page.size, PAGE_SIZE)


def synthetic_mixing_events(*, one_ring: bool = False) -> tuple[Event, ...]:
    events = []
    seq = 0
    logical_id = 1
    for cycle in range(24):
        time_ns = cycle * 100
        events.append(
            Event(
                time_ns,
                seq,
                "post",
                logical_id,
                "data",
                "ring-a",
                "lane0",
                "long",
                2176,
                2560,
                cycle,
            )
        )
        seq += 1
        logical_id += 1
        short_ids = []
        for short_index in range(11):
            short_id = logical_id
            logical_id += 1
            short_ring = "ring-a" if one_ring else "ring-b"
            events.append(
                Event(
                    time_ns,
                    seq,
                    "alloc",
                    short_id,
                    "monitor_status",
                    short_ring,
                    "lane0",
                    "short",
                    2176,
                    2560,
                    short_index,
                )
            )
            seq += 1
            short_ids.append((short_id, short_ring))
        for short_id, short_ring in short_ids:
            events.append(
                Event(
                    time_ns,
                    seq,
                    "free",
                    short_id,
                    "monitor_status",
                    short_ring,
                    "lane0",
                    "short",
                    0,
                    0,
                    -1,
                )
            )
            seq += 1
    return tuple(events)


class ScenarioTests(unittest.TestCase):
    def test_capture_calibration_maps_sizes_rates_and_ring_inventory(self) -> None:
        config = SimulationConfig(
            seed=17,
            duration_ns=1_000_000_000,
            sample_ns=250_000_000,
        )
        events = generate_events(config)
        allocations = [event for event in events if event.action in ("post", "alloc")]
        data = [event for event in allocations if event.source == "data"]
        monitor = [event for event in allocations if event.source == "monitor_status"]
        ce = [event for event in allocations if event.source == "ce"]

        self.assertEqual(len(data), 4095 * 3 + 25)
        self.assertEqual(len(monitor), 1024 * 3 + 184)
        self.assertEqual(len(ce), 174)
        self.assertEqual(
            {(event.requested_bytes, event.aligned_bytes) for event in data},
            {(2176, 2560)},
        )
        self.assertEqual(
            {(event.requested_bytes, event.aligned_bytes) for event in monitor},
            {(2176, 2560)},
        )
        self.assertEqual(
            {(event.requested_bytes, event.aligned_bytes) for event in ce},
            {(2048, 2432)},
        )

    def test_identical_events_produce_identical_logical_live_counts(self) -> None:
        config = SimulationConfig(
            seed=17,
            duration_ns=1_000_000_000,
            sample_ns=250_000_000,
        )
        events = generate_events(config)
        results = replay_all(config, events)
        logical = {
            (
                result.summary["live_fragments"],
                result.summary["posted_fragments"],
                result.summary["reaped_fragments"],
                result.summary["events"],
                result.summary["event_sha256"],
            )
            for result in results
        }
        self.assertEqual(len(logical), 1)
        self.assertEqual({result.policy for result in results}, set(POLICIES))
        self.assertEqual(results[0].summary["posted_fragments"], 4095 * 3 + 1024 * 3)

    def test_shared_retains_more_pages_for_alternating_long_short_rings(self) -> None:
        events = synthetic_mixing_events()
        config = SimulationConfig(
            duration_ns=10_000,
            sample_ns=10_000,
            radios=1,
            data_capacity=1,
            monitor_capacity=1,
            data_rate=Decimal(0),
            monitor_rate=Decimal(0),
            ce_rate=Decimal(0),
        )
        digest = event_stream_hash(events)
        shared = ScenarioReplay("shared", config, digest).replay(events)
        per_ring = ScenarioReplay("per_ring", config, digest).replay(events)
        self.assertGreater(
            shared.summary["global_unique_pages"],
            per_ring.summary["global_unique_pages"],
        )
        self.assertGreater(shared.summary["historical_cross_lifetime_pages"], 0)
        self.assertEqual(per_ring.summary["historical_cross_lifetime_pages"], 0)

    def test_one_ring_shared_and_per_ring_are_physically_identical(self) -> None:
        events = synthetic_mixing_events(one_ring=True)
        config = SimulationConfig(
            duration_ns=10_000,
            sample_ns=10_000,
            radios=1,
            data_capacity=1,
            monitor_capacity=1,
            data_rate=Decimal(0),
            monitor_rate=Decimal(0),
            ce_rate=Decimal(0),
        )
        digest = event_stream_hash(events)
        shared = ScenarioReplay("shared", config, digest).replay(events)
        per_ring = ScenarioReplay("per_ring", config, digest).replay(events)
        fields = (
            "global_unique_pages",
            "requested_bytes",
            "aligned_bytes",
            "backing_bytes",
            "slack_bytes",
            "refills",
            "reuses",
            "frees",
        )
        self.assertEqual(
            tuple(shared.summary[field] for field in fields),
            tuple(per_ring.summary[field] for field in fields),
        )

    def test_same_ring_only_does_not_subdivide_ce_by_lane(self) -> None:
        events = (
            Event(0, 0, "alloc", 1, "ce", "ce0", "lane0", "short", 2048, 2432, -1),
            Event(0, 1, "alloc", 2, "ce", "ce0", "lane1", "short", 2048, 2432, -1),
        )
        config = SimulationConfig(
            duration_ns=1,
            sample_ns=1,
            radios=1,
            data_capacity=1,
            monitor_capacity=1,
            data_rate=Decimal(0),
            monitor_rate=Decimal(0),
            ce_rate=Decimal(0),
        )
        digest = event_stream_hash(events)
        per_ring_replay = ScenarioReplay("per_ring", config, digest)
        same_ring_replay = ScenarioReplay("same_ring_only", config, digest)
        per_ring = per_ring_replay.replay(events)
        same_ring = same_ring_replay.replay(events)
        self.assertEqual(len(per_ring_replay.caches), 2)
        self.assertEqual(len(same_ring_replay.caches), 1)
        self.assertEqual(per_ring.summary["global_unique_pages"], 2)
        self.assertEqual(same_ring.summary["global_unique_pages"], 1)

    def test_capture_calibration_is_bounded_and_reproducible(self) -> None:
        config = SimulationConfig(
            seed=17,
            duration_ns=1_000_000_000,
            sample_ns=250_000_000,
        )
        first = generate_events(config)
        second = generate_events(config)
        self.assertEqual(first, second)
        self.assertEqual(
            event_stream_hash(first),
            "af422464713c88c5d7ce0ef0e36a05d2fc26138d4444a17a2cc935795ccece9c",
        )
        self.assertLess(len(first), 20_000)

    def test_csv_outputs_include_warning_and_normalized_event_export(self) -> None:
        config = SimulationConfig(
            seed=2,
            duration_ns=100_000_000,
            sample_ns=50_000_000,
            radios=1,
            data_capacity=4,
            monitor_capacity=2,
        )
        events = generate_events(config)
        results = replay_all(config, events)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            write_outputs(output, events, results)
            self.assertTrue((output / "events.csv").read_text().startswith("time_ns,seq,"))
            self.assertIn(MECHANISM_WARNING, (output / "summary.csv").read_text())
            self.assertIn(MECHANISM_WARNING, (output / "timeline.csv").read_text())


if __name__ == "__main__":
    unittest.main()
