**Algorithms outlive the hardware they run on, yet every time we must port or
performance tune.** A signal-processing kernel stays stable for years. The chips
under it come and go.

So the same computation has to be ported. From CPU threads on a laptop, to a
message-passing cluster, to firmware in a microcontroller in an embedded device.
Hardware comes and goes. The algorithm stays.

![One algorithm, many hardware generations](assets/algorithm-outlives-hardware.svg)

This is for **systems code**: firmware and high-performance signal and data
processing.

## The problem

Moving an algorithm to new hardware means **rewriting it**.

The arithmetic is the cheap part. The glue around it is expensive. How data is
split across workers. How workers exchange results. Which **IO semantics** govern
the exchange: blocking vs async, polled vs event-driven, shared memory vs DMA.

That glue is large and platform-specific. It is where deadlocks and buffer
overruns hide. So the threads version, the cluster version, and the firmware
version become **three separate programs** that compute the same function. They
drift apart with every change.

## The idea: two files

Nucleus splits the program in two.

- The **algorithm** says *what* to compute. It names no workers, no buffers, no
  transports, no sync barriers.
- The **schedule** says *where, when, and how*. How many workers. How the data is
  partitioned. Which IO mechanism to use. This is the space and time
  decomposition.

![One algorithm composes with many schedules and targets](assets/one-algorithm-many-schedules.svg)

**You change the schedule, not the algorithm.** The compiler writes the data
transfers for you. It works out the **halo regions** a stencil needs from its
neighbours.

## Why this matters

Decomposition and IO are **decisions you make up front**. What runs where. What
runs when. How deep to **pipeline**. Which **IO mechanism** to pick on each link.

These are expensive bets. In hand-written code they are baked into the source.
Changing one after the app ships is painful.

Nucleus makes them **dials**. To explore performance, edit a small file. Balance
the pipeline. Try a different decomposition. Swap a transport. Re-measure.

**Porting is then free.** To a new platform, if supported by nucleus-rs. Or to
the same platform with different performance characteristics.

## How it stays honest

A cheap port is worthless if it changes the result. Nucleus checks this on every
build.

- **Compile-time soundness.** Buffer overflows and deadlocks are caught at
  compile time, not in the field. For firmware with no OS to catch a fault, this
  matters.
- **A byte-identical test.** The same algorithm, under every schedule and
  backend, must produce the same bytes against an independent reference. One
  differing byte fails the build. It names the backend that disagreed.

Nucleus is a **clean-room Rust reimplementation** of the author's 2013 Intel MSc
work on compiling one source for multi-ASIP VLIW chips, now carried across ten
backends instead of one.

Source: [github.com/eisbaw/nucleus-rs](https://github.com/eisbaw/nucleus-rs)
