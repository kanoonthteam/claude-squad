---
name: rust-async
description: Async Rust with Tokio — runtime configuration, task spawning, channels, select!, async I/O, cancellation, concurrency primitives, async traits, streams, and production patterns
---

# Async Rust with Tokio

Production-ready async patterns for Rust using Tokio 1.x. Covers runtime configuration, task spawning and structured concurrency, channel-based communication (mpsc, oneshot, broadcast, watch), the select! macro, async I/O with TCP/UDP, task cancellation and graceful shutdown, concurrency limiting with Semaphore, async-aware Mutex and RwLock, async traits, Pin and Future, async streams with tokio-stream, error propagation, tower Service trait, retry patterns, connection pooling, and async testing.

## Table of Contents

1. [Tokio Runtime Configuration](#tokio-runtime-configuration)
2. [Spawning Tasks and JoinHandle](#spawning-tasks-and-joinhandle)
3. [Channels: mpsc, oneshot, broadcast, watch](#channels-mpsc-oneshot-broadcast-watch)
4. [The select! Macro](#the-select-macro)
5. [Timeouts and Intervals](#timeouts-and-intervals)
6. [Async I/O: TCP, UDP, and Unix Sockets](#async-io-tcp-udp-and-unix-sockets)
7. [Task Cancellation and Graceful Shutdown](#task-cancellation-and-graceful-shutdown)
8. [Concurrency Primitives: Semaphore, Mutex, RwLock](#concurrency-primitives-semaphore-mutex-rwlock)
9. [Async Traits, Pin, and Future](#async-traits-pin-and-future)
10. [Async Streams with tokio-stream](#async-streams-with-tokio-stream)
11. [Error Propagation in Async Contexts](#error-propagation-in-async-contexts)
12. [Structured Concurrency and Backpressure](#structured-concurrency-and-backpressure)
13. [Tower Service Trait and Middleware](#tower-service-trait-and-middleware)
14. [Retry Patterns and Exponential Backoff](#retry-patterns-and-exponential-backoff)
15. [Connection Pooling: deadpool and bb8](#connection-pooling-deadpool-and-bb8)
16. [Async Testing with tokio::test](#async-testing-with-tokiotest)
17. [Best Practices](#best-practices)
18. [Anti-Patterns](#anti-patterns)
19. [Sources & References](#sources--references)

---

## Tokio Runtime Configuration

Tokio provides two runtime flavors that determine how async tasks are scheduled.

**Multi-threaded runtime (default):** Uses a work-stealing scheduler across multiple OS threads. Best for servers and CPU-bound hybrid workloads.

```rust
// Using the macro (most common)
#[tokio::main]
async fn main() {
    // Runs on multi-threaded runtime with default thread count (num_cpus)
    run_server().await;
}

// Manual configuration for fine-grained control
fn main() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)               // Number of worker threads
        .max_blocking_threads(64)         // Threads for blocking operations
        .thread_name("my-app-worker")
        .enable_all()                     // Enable I/O and time drivers
        .build()
        .expect("Failed to build Tokio runtime");

    runtime.block_on(async {
        run_server().await;
    });
}
```

**Current-thread runtime:** Runs all tasks on a single thread. Lower overhead, useful for lightweight tools, CLI applications, or when you need deterministic execution order.

```rust
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Single-threaded — no Send requirement on spawned futures
    run_lightweight_task().await;
}

// Manual equivalent
fn main() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("Failed to build runtime");

    runtime.block_on(async {
        run_lightweight_task().await;
    });
}
```

**Key considerations:**
- Multi-threaded runtime requires spawned futures to be `Send + 'static`.
- Current-thread runtime allows `!Send` futures but cannot parallelize across cores.
- Use `runtime.spawn_blocking()` or `tokio::task::spawn_blocking()` for CPU-heavy or synchronous work to avoid starving the async executor.
- The `enter()` guard lets you set the runtime context without blocking on a future.

---

## Spawning Tasks and JoinHandle

`tokio::spawn` creates a new asynchronous task that runs concurrently. It returns a `JoinHandle` for awaiting the result.

```rust
use tokio::task::JoinHandle;

async fn process_items(items: Vec<String>) -> Vec<usize> {
    let mut handles: Vec<JoinHandle<usize>> = Vec::new();

    for item in items {
        // Each task runs concurrently on the runtime
        let handle = tokio::spawn(async move {
            // Simulate async work
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            item.len()
        });
        handles.push(handle);
    }

    // Collect results — JoinError occurs if a task panics
    let mut results = Vec::new();
    for handle in handles {
        match handle.await {
            Ok(len) => results.push(len),
            Err(e) => eprintln!("Task failed: {e}"),
        }
    }
    results
}
```

**JoinSet for managing groups of tasks:**

```rust
use tokio::task::JoinSet;

async fn process_with_joinset(urls: Vec<String>) -> Vec<String> {
    let mut set = JoinSet::new();

    for url in urls {
        set.spawn(async move {
            // Simulated HTTP fetch
            fetch_url(&url).await
        });
    }

    let mut results = Vec::new();
    while let Some(res) = set.join_next().await {
        match res {
            Ok(body) => results.push(body),
            Err(e) => eprintln!("Task panicked: {e}"),
        }
    }
    results
}
```

**spawn_blocking for CPU-bound work:**

```rust
async fn compute_hash(data: Vec<u8>) -> String {
    // Offload to the blocking thread pool
    tokio::task::spawn_blocking(move || {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(&data);
        format!("{:x}", hasher.finalize())
    })
    .await
    .expect("Blocking task panicked")
}
```

**Key rules:**
- Spawned futures must be `Send + 'static` on the multi-threaded runtime.
- Use `tokio::task::spawn_local` for `!Send` futures on a `LocalSet`.
- Dropping a `JoinHandle` does NOT cancel the task; call `handle.abort()` to cancel.

---

## Channels: mpsc, oneshot, broadcast, watch

Tokio provides four channel types for inter-task communication.

**mpsc (multi-producer, single-consumer):** The workhorse channel for task communication. Bounded channels provide backpressure.

```rust
use tokio::sync::mpsc;

async fn mpsc_example() {
    // Bounded channel — sender blocks when buffer is full (backpressure)
    let (tx, mut rx) = mpsc::channel::<String>(100);

    // Clone for multiple producers
    let tx2 = tx.clone();

    tokio::spawn(async move {
        tx.send("from task 1".to_string()).await.unwrap();
    });

    tokio::spawn(async move {
        tx2.send("from task 2".to_string()).await.unwrap();
    });

    // Receiver loop — returns None when all senders are dropped
    while let Some(msg) = rx.recv().await {
        println!("Received: {msg}");
    }
}
```

**oneshot (single-producer, single-consumer, single-value):** Perfect for request-response patterns.

```rust
use tokio::sync::oneshot;

async fn request_response() {
    let (tx, rx) = oneshot::channel::<u64>();

    tokio::spawn(async move {
        let result = expensive_computation().await;
        let _ = tx.send(result); // Fails if receiver dropped
    });

    match rx.await {
        Ok(value) => println!("Got result: {value}"),
        Err(_) => println!("Sender dropped without sending"),
    }
}
```

**broadcast (multi-producer, multi-consumer):** Every receiver gets every message. Useful for event fanout.

```rust
use tokio::sync::broadcast;

async fn broadcast_example() {
    let (tx, _) = broadcast::channel::<String>(16);

    let mut rx1 = tx.subscribe();
    let mut rx2 = tx.subscribe();

    tx.send("event happened".to_string()).unwrap();

    // Both receivers get the message
    let msg1 = rx1.recv().await.unwrap();
    let msg2 = rx2.recv().await.unwrap();
    assert_eq!(msg1, msg2);
}
```

**watch (single-producer, multi-consumer, latest-value):** Receivers always see the most recent value. Good for configuration or state updates.

```rust
use tokio::sync::watch;

async fn watch_example() {
    let (tx, mut rx) = watch::channel("initial".to_string());

    tokio::spawn(async move {
        loop {
            // changed() waits until a new value is sent
            if rx.changed().await.is_err() {
                break; // Sender dropped
            }
            let value = rx.borrow().clone();
            println!("Config updated: {value}");
        }
    });

    tx.send("updated config".to_string()).unwrap();
}
```

**Channel selection guide:**
- `mpsc` — Task queues, work distribution, command patterns. Use bounded for backpressure.
- `oneshot` — Single response, request-response, signaling completion.
- `broadcast` — Event fanout, pub/sub within a process.
- `watch` — Configuration changes, latest-state sharing.

---

## The select! Macro

`tokio::select!` waits on multiple async operations simultaneously and executes the branch that completes first. Unselected branches are cancelled.

```rust
use tokio::sync::mpsc;
use tokio::time::{self, Duration};

async fn select_example(
    mut cmd_rx: mpsc::Receiver<String>,
    mut shutdown_rx: tokio::sync::broadcast::Receiver<()>,
) {
    let mut interval = time::interval(Duration::from_secs(5));

    loop {
        tokio::select! {
            // Receive a command
            Some(cmd) = cmd_rx.recv() => {
                println!("Command: {cmd}");
                handle_command(&cmd).await;
            }

            // Periodic tick
            _ = interval.tick() => {
                println!("Heartbeat");
            }

            // Shutdown signal
            _ = shutdown_rx.recv() => {
                println!("Shutting down");
                break;
            }
        }
    }
}
```

**select! rules and behaviors:**
- All branches are polled concurrently; the first to complete wins.
- Unselected branches are dropped (cancelled) — their futures are not polled further.
- Use `biased;` at the start of `select!` to poll branches in order (priority-based selection).
- Pattern matching on the result controls whether the branch fires (`Some(x)` vs `None`).
- Adding a precondition: `branch, if condition => { ... }` disables the branch when the condition is false.

```rust
// Biased select — always check shutdown first
tokio::select! {
    biased;

    _ = shutdown_rx.recv() => {
        return;
    }
    msg = data_rx.recv() => {
        if let Some(m) = msg {
            process(m).await;
        }
    }
}
```

---

## Timeouts and Intervals

**Timeouts wrap any future with a deadline:**

```rust
use tokio::time::{timeout, Duration};

async fn fetch_with_timeout(url: &str) -> Result<String, Box<dyn std::error::Error>> {
    match timeout(Duration::from_secs(10), fetch_url(url)).await {
        Ok(Ok(body)) => Ok(body),
        Ok(Err(e)) => Err(e.into()),
        Err(_elapsed) => Err("Request timed out".into()),
    }
}
```

**Intervals for periodic work:**

```rust
use tokio::time::{self, Duration, MissedTickBehavior};

async fn periodic_cleanup() {
    let mut interval = time::interval(Duration::from_secs(60));
    // Skip missed ticks if processing takes longer than the interval
    interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

    loop {
        interval.tick().await;
        cleanup_expired_sessions().await;
    }
}
```

**sleep vs sleep_until:**

```rust
use tokio::time::{sleep, sleep_until, Instant, Duration};

async fn delay_example() {
    // Relative delay
    sleep(Duration::from_millis(500)).await;

    // Absolute deadline
    let deadline = Instant::now() + Duration::from_secs(5);
    sleep_until(deadline).await;
}
```

**MissedTickBehavior options:**
- `Burst` (default) — fire immediately for each missed tick.
- `Delay` — reset the interval from the current time.
- `Skip` — skip missed ticks entirely, resume on the next aligned tick.

---

## Async I/O: TCP, UDP, and Unix Sockets

**TCP server with TcpListener:**

```rust
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn run_tcp_server() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:8080").await?;
    println!("Listening on 127.0.0.1:8080");

    loop {
        let (socket, addr) = listener.accept().await?;
        println!("New connection from {addr}");

        // Spawn a task per connection
        tokio::spawn(async move {
            if let Err(e) = handle_connection(socket).await {
                eprintln!("Connection error: {e}");
            }
        });
    }
}

async fn handle_connection(mut socket: TcpStream) -> std::io::Result<()> {
    let mut buf = vec![0u8; 4096];

    loop {
        let n = socket.read(&mut buf).await?;
        if n == 0 {
            return Ok(()); // Connection closed
        }
        // Echo back
        socket.write_all(&buf[..n]).await?;
    }
}
```

**TCP client with TcpStream:**

```rust
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn tcp_client() -> std::io::Result<()> {
    let mut stream = TcpStream::connect("127.0.0.1:8080").await?;

    stream.write_all(b"Hello, server!").await?;

    let mut buf = vec![0u8; 1024];
    let n = stream.read(&mut buf).await?;
    println!("Response: {}", String::from_utf8_lossy(&buf[..n]));

    Ok(())
}
```

**UDP socket:**

```rust
use tokio::net::UdpSocket;

async fn udp_echo_server() -> std::io::Result<()> {
    let socket = UdpSocket::bind("127.0.0.1:9000").await?;
    let mut buf = vec![0u8; 1500];

    loop {
        let (len, addr) = socket.recv_from(&mut buf).await?;
        socket.send_to(&buf[..len], addr).await?;
    }
}
```

**Splitting streams for concurrent read/write:**

```rust
use tokio::net::TcpStream;
use tokio::io::{self, AsyncBufReadExt, AsyncWriteExt, BufReader};

async fn split_example(stream: TcpStream) {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    tokio::spawn(async move {
        while let Ok(Some(line)) = lines.next_line().await {
            println!("Received: {line}");
        }
    });

    writer.write_all(b"outgoing data\n").await.unwrap();
}
```

---

## Task Cancellation and Graceful Shutdown

Tokio supports cooperative cancellation — dropping a future at any `.await` point cancels it.

**CancellationToken pattern (recommended):**

```rust
use tokio_util::sync::CancellationToken;
use tokio::time::{sleep, Duration};

async fn graceful_shutdown() {
    let token = CancellationToken::new();

    // Spawn workers with cloned tokens
    let worker_token = token.clone();
    let worker = tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = worker_token.cancelled() => {
                    println!("Worker shutting down gracefully");
                    // Perform cleanup
                    return;
                }
                _ = do_work() => {}
            }
        }
    });

    // Listen for Ctrl+C
    tokio::signal::ctrl_c().await.unwrap();
    println!("Shutdown signal received");

    // Signal all tasks to stop
    token.cancel();

    // Wait for tasks to finish with a timeout
    let shutdown_timeout = Duration::from_secs(30);
    if tokio::time::timeout(shutdown_timeout, worker).await.is_err() {
        eprintln!("Worker did not finish in time, forcing shutdown");
    }
}
```

**Abort-based cancellation:**

```rust
let handle = tokio::spawn(async {
    loop {
        work().await;
    }
});

// Force-cancel the task — the future is dropped at its current .await point
handle.abort();

// JoinError with is_cancelled() == true
match handle.await {
    Ok(_) => unreachable!(),
    Err(e) if e.is_cancelled() => println!("Task was cancelled"),
    Err(e) => println!("Task panicked: {e}"),
}
```

**Async drop pitfalls:**
- Rust does not support async `Drop`. Cleanup that requires `.await` must be done explicitly before dropping.
- Use an explicit `shutdown()` async method or a dedicated cleanup task.
- The `tokio::sync::mpsc::Sender` dropping signals the receiver, which is a useful pattern for coordinating shutdown.

```rust
struct Connection {
    // ...
}

impl Connection {
    /// Explicit async cleanup — call before dropping
    async fn shutdown(self) -> std::io::Result<()> {
        // Flush buffers, send goodbye message, etc.
        self.flush().await?;
        self.close().await?;
        Ok(())
    }
}
```

---

## Concurrency Primitives: Semaphore, Mutex, RwLock

**Semaphore for concurrency limiting:**

```rust
use std::sync::Arc;
use tokio::sync::Semaphore;

async fn rate_limited_fetcher(urls: Vec<String>) {
    // Allow at most 10 concurrent fetches
    let semaphore = Arc::new(Semaphore::new(10));
    let mut handles = Vec::new();

    for url in urls {
        let permit = semaphore.clone().acquire_owned().await.unwrap();
        handles.push(tokio::spawn(async move {
            let result = fetch_url(&url).await;
            drop(permit); // Release when done
            result
        }));
    }

    for handle in handles {
        let _ = handle.await;
    }
}
```

**tokio::sync::Mutex vs std::sync::Mutex:**

Use `tokio::sync::Mutex` when you need to hold the lock across `.await` points. Use `std::sync::Mutex` for short, synchronous critical sections even in async code (it is faster when no `.await` is needed inside the lock).

```rust
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Clone)]
struct SharedState {
    inner: Arc<Mutex<StateInner>>,
}

struct StateInner {
    counter: u64,
    data: Vec<String>,
}

impl SharedState {
    async fn increment_and_fetch(&self) -> u64 {
        let mut state = self.inner.lock().await;
        state.counter += 1;
        // Safe to .await while holding the lock (tokio Mutex)
        log_counter(state.counter).await;
        state.counter
    }
}
```

**RwLock for read-heavy workloads:**

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

struct ConfigStore {
    config: Arc<RwLock<HashMap<String, String>>>,
}

impl ConfigStore {
    async fn get(&self, key: &str) -> Option<String> {
        let guard = self.config.read().await;
        guard.get(key).cloned()
    }

    async fn set(&self, key: String, value: String) {
        let mut guard = self.config.write().await;
        guard.insert(key, value);
    }
}
```

**Guideline for choosing:**
- `std::sync::Mutex` — Lock held briefly, no `.await` inside the critical section. Lower overhead.
- `tokio::sync::Mutex` — Lock held across `.await` points. Does not block the OS thread.
- `tokio::sync::RwLock` — Many concurrent readers, infrequent writers, and lock held across `.await`.
- `tokio::sync::Semaphore` — Limit concurrency to N tasks. Use `acquire_owned` for `'static` permits.

---

## Async Traits, Pin, and Future

**Async traits (stable since Rust 1.75):**

```rust
trait DataStore {
    async fn get(&self, key: &str) -> Option<String>;
    async fn set(&self, key: &str, value: &str) -> Result<(), StoreError>;
}

struct RedisStore {
    client: redis::Client,
}

impl DataStore for RedisStore {
    async fn get(&self, key: &str) -> Option<String> {
        let mut conn = self.client.get_async_connection().await.ok()?;
        redis::cmd("GET").arg(key).query_async(&mut conn).await.ok()
    }

    async fn set(&self, key: &str, value: &str) -> Result<(), StoreError> {
        let mut conn = self.client.get_async_connection().await?;
        redis::cmd("SET").arg(key).arg(value).query_async(&mut conn).await?;
        Ok(())
    }
}
```

**Limitation:** Native async trait methods return `impl Future` which is not `dyn`-compatible. If you need `dyn Trait`, use the `async_trait` crate or return `Box<dyn Future>` manually.

```rust
// Using async_trait for dynamic dispatch
use async_trait::async_trait;

#[async_trait]
trait Handler: Send + Sync {
    async fn handle(&self, request: Request) -> Response;
}
```

**Pin and Future fundamentals:**

`Future` is the core trait for async in Rust. Async functions return types implementing `Future`. `Pin<&mut F>` guarantees the future is not moved in memory, which is required because many futures are self-referential.

```rust
use std::future::Future;
use std::pin::Pin;

// Returning a boxed future for dynamic dispatch
fn make_handler() -> Box<dyn Fn() -> Pin<Box<dyn Future<Output = String> + Send>> + Send + Sync> {
    Box::new(|| {
        Box::pin(async {
            "hello from dynamic future".to_string()
        })
    })
}

// Manual Future implementation (rarely needed)
use std::task::{Context, Poll};

struct Delay {
    when: tokio::time::Instant,
    sleep: Pin<Box<tokio::time::Sleep>>,
}

impl Future for Delay {
    type Output = ();

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
        self.sleep.as_mut().poll(cx)
    }
}
```

**When you encounter `Pin`:**
- Most of the time, use `Box::pin(async { ... })` to create a pinned future.
- `pin!()` macro (from `tokio` or `std`) pins a future on the stack.
- You need `Pin` when storing futures in structs or returning them from trait methods.

---

## Async Streams with tokio-stream

Async streams produce a sequence of values over time, analogous to `Iterator` but asynchronous.

```rust
use tokio_stream::{StreamExt, wrappers::ReceiverStream};
use tokio::sync::mpsc;

async fn stream_processing() {
    let (tx, rx) = mpsc::channel::<i32>(100);

    // Produce values
    tokio::spawn(async move {
        for i in 0..100 {
            tx.send(i).await.unwrap();
        }
    });

    // Wrap receiver as a stream and process with combinators
    let stream = ReceiverStream::new(rx);

    let results: Vec<i32> = stream
        .filter(|x| x % 2 == 0)       // Keep even numbers
        .map(|x| x * 10)               // Transform
        .take(10)                       // Limit
        .collect()
        .await;

    println!("Results: {results:?}");
}
```

**Creating streams from iterators and intervals:**

```rust
use tokio_stream::{self as stream, StreamExt};
use tokio::time::{interval, Duration};
use tokio_stream::wrappers::IntervalStream;

async fn interval_stream() {
    let stream = IntervalStream::new(interval(Duration::from_secs(1)))
        .take(5)
        .enumerate();

    tokio::pin!(stream);

    while let Some((i, _instant)) = stream.next().await {
        println!("Tick {i}");
    }
}
```

**Merging and chaining streams:**

```rust
use tokio_stream::{StreamExt, StreamMap};

async fn merged_streams() {
    let mut map = StreamMap::new();
    map.insert("source_a", tokio_stream::iter(vec![1, 2, 3]));
    map.insert("source_b", tokio_stream::iter(vec![4, 5, 6]));

    while let Some((key, value)) = map.next().await {
        println!("{key}: {value}");
    }
}
```

---

## Error Propagation in Async Contexts

**Using `anyhow` for application-level error handling:**

```rust
use anyhow::{Context, Result};

async fn load_config(path: &str) -> Result<Config> {
    let content = tokio::fs::read_to_string(path)
        .await
        .context("Failed to read config file")?;

    let config: Config = serde_json::from_str(&content)
        .context("Failed to parse config JSON")?;

    Ok(config)
}
```

**Using `thiserror` for library error types:**

```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum ServiceError {
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("request timeout after {0:?}")]
    Timeout(std::time::Duration),

    #[error("not found: {entity} with id {id}")]
    NotFound { entity: String, id: String },

    #[error("channel closed")]
    ChannelClosed,
}

async fn get_user(id: &str) -> Result<User, ServiceError> {
    let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(&pool)
        .await?  // sqlx::Error auto-converts via #[from]
        .ok_or_else(|| ServiceError::NotFound {
            entity: "User".into(),
            id: id.into(),
        })?;

    Ok(user)
}
```

**Handling errors from spawned tasks:**

```rust
// JoinHandle returns Result<T, JoinError>
// JoinError occurs when a task panics or is cancelled
let handle = tokio::spawn(async {
    might_fail().await
});

match handle.await {
    Ok(Ok(value)) => println!("Success: {value}"),
    Ok(Err(app_err)) => println!("Application error: {app_err}"),
    Err(join_err) => {
        if join_err.is_cancelled() {
            println!("Task was cancelled");
        } else {
            println!("Task panicked: {join_err}");
        }
    }
}
```

**Pattern: Map channel send errors to application errors:**

```rust
use tokio::sync::mpsc;

async fn send_event(tx: &mpsc::Sender<Event>, event: Event) -> Result<(), ServiceError> {
    tx.send(event)
        .await
        .map_err(|_| ServiceError::ChannelClosed)
}
```

---

## Structured Concurrency and Backpressure

**Structured concurrency with JoinSet:**

```rust
use tokio::task::JoinSet;

async fn process_batch(items: Vec<Item>) -> Vec<Result<Output, ProcessError>> {
    let mut set = JoinSet::new();
    let mut results = Vec::with_capacity(items.len());

    for item in items {
        set.spawn(async move {
            process_item(item).await
        });
    }

    while let Some(res) = set.join_next().await {
        match res {
            Ok(output) => results.push(output),
            Err(join_err) => {
                eprintln!("Task panicked: {join_err}");
            }
        }
    }

    results
}
```

**Backpressure with bounded channels:**

When producers are faster than consumers, bounded channels create natural backpressure. The sender blocks (asynchronously) when the buffer is full.

```rust
use tokio::sync::mpsc;

async fn pipeline() {
    // Small buffer = strong backpressure
    let (tx, mut rx) = mpsc::channel::<WorkItem>(32);

    // Producer — slows down when channel is full
    let producer = tokio::spawn(async move {
        for i in 0..10_000 {
            let item = generate_work(i).await;
            // This .await suspends when the channel buffer is full
            if tx.send(item).await.is_err() {
                break; // Receiver dropped
            }
        }
    });

    // Consumer — processes at its own pace
    let consumer = tokio::spawn(async move {
        while let Some(item) = rx.recv().await {
            process_slowly(item).await;
        }
    });

    let _ = tokio::join!(producer, consumer);
}
```

**Fan-out / fan-in with concurrency limit:**

```rust
use std::sync::Arc;
use tokio::sync::{mpsc, Semaphore};

async fn fan_out_fan_in(
    inputs: Vec<Input>,
    max_concurrency: usize,
) -> Vec<Output> {
    let (result_tx, mut result_rx) = mpsc::channel(inputs.len());
    let semaphore = Arc::new(Semaphore::new(max_concurrency));

    for input in inputs {
        let permit = semaphore.clone().acquire_owned().await.unwrap();
        let tx = result_tx.clone();

        tokio::spawn(async move {
            let output = process(input).await;
            let _ = tx.send(output).await;
            drop(permit);
        });
    }

    // Drop the original sender so the receiver knows when all tasks are done
    drop(result_tx);

    let mut results = Vec::new();
    while let Some(output) = result_rx.recv().await {
        results.push(output);
    }
    results
}
```

---

## Tower Service Trait and Middleware

The `tower::Service` trait provides a standard abstraction for request/response processing, enabling composable middleware.

```rust
use tower::{Service, ServiceBuilder, ServiceExt};
use tower::timeout::TimeoutLayer;
use tower::limit::ConcurrencyLimitLayer;
use tower::retry::RetryLayer;
use std::time::Duration;

// Define a service
#[derive(Clone)]
struct MyService;

impl Service<Request> for MyService {
    type Response = Response;
    type Error = ServiceError;
    type Future = Pin<Box<dyn Future<Output = Result<Response, ServiceError>> + Send>>;

    fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, req: Request) -> Self::Future {
        Box::pin(async move {
            // Handle the request
            Ok(Response::new(req))
        })
    }
}

// Compose middleware layers
async fn build_service() {
    let service = ServiceBuilder::new()
        .layer(TimeoutLayer::new(Duration::from_secs(30)))
        .layer(ConcurrencyLimitLayer::new(64))
        .service(MyService);

    // Use the service
    let response = service.clone().oneshot(request).await;
}
```

**Tower layers commonly used in production:**
- `TimeoutLayer` — Fail requests that take too long.
- `ConcurrencyLimitLayer` — Limit in-flight requests.
- `RateLimitLayer` — Limit requests per time window.
- `RetryLayer` — Retry failed requests with a policy.
- `BufferLayer` — Add a channel buffer in front of a service for `Clone + Send`.

---

## Retry Patterns and Exponential Backoff

**Manual retry with exponential backoff:**

```rust
use tokio::time::{sleep, Duration};
use rand::Rng;

async fn retry_with_backoff<F, Fut, T, E>(
    mut operation: F,
    max_retries: u32,
    base_delay: Duration,
) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, E>>,
    E: std::fmt::Display,
{
    let mut attempt = 0;

    loop {
        match operation().await {
            Ok(value) => return Ok(value),
            Err(e) if attempt < max_retries => {
                attempt += 1;
                let jitter = rand::thread_rng().gen_range(0..100);
                let delay = base_delay * 2u32.pow(attempt - 1)
                    + Duration::from_millis(jitter);
                eprintln!(
                    "Attempt {attempt} failed: {e}. Retrying in {delay:?}"
                );
                sleep(delay).await;
            }
            Err(e) => return Err(e),
        }
    }
}

// Usage
async fn fetch_with_retry(url: &str) -> Result<String, reqwest::Error> {
    retry_with_backoff(
        || reqwest::get(url).and_then(|r| r.text()),
        3,
        Duration::from_millis(200),
    )
    .await
}
```

**Using the `backon` crate for declarative retries:**

```rust
use backon::{ExponentialBuilder, Retryable};

async fn fetch_data(url: &str) -> Result<String, reqwest::Error> {
    let body = (|| async {
        reqwest::get(url).await?.text().await
    })
    .retry(ExponentialBuilder::default()
        .with_min_delay(Duration::from_millis(100))
        .with_max_delay(Duration::from_secs(10))
        .with_max_times(5))
    .await?;

    Ok(body)
}
```

**Retry considerations:**
- Always add jitter to avoid thundering herd.
- Set a maximum retry count and a maximum total timeout.
- Only retry on transient errors (network timeout, 503, 429) — not on 400/401/404.
- Use circuit breakers for sustained failures to avoid cascading overload.

---

## Connection Pooling: deadpool and bb8

**deadpool — simple, ergonomic connection pooling:**

```rust
use deadpool_postgres::{Config, Pool, Runtime};
use tokio_postgres::NoTls;

async fn create_pool() -> Pool {
    let mut cfg = Config::new();
    cfg.host = Some("localhost".to_string());
    cfg.port = Some(5432);
    cfg.dbname = Some("mydb".to_string());
    cfg.user = Some("postgres".to_string());
    cfg.password = Some("secret".to_string());

    cfg.create_pool(Some(Runtime::Tokio1), NoTls)
        .expect("Failed to create pool")
}

async fn query_with_pool(pool: &Pool) -> Result<Vec<User>, Box<dyn std::error::Error>> {
    let client = pool.get().await?;
    let rows = client
        .query("SELECT id, name, email FROM users WHERE active = $1", &[&true])
        .await?;

    let users = rows
        .iter()
        .map(|row| User {
            id: row.get(0),
            name: row.get(1),
            email: row.get(2),
        })
        .collect();

    Ok(users)
    // Connection is returned to the pool when `client` is dropped
}
```

**bb8 — another popular pool manager:**

```rust
use bb8::Pool;
use bb8_postgres::PostgresConnectionManager;
use tokio_postgres::NoTls;

async fn create_bb8_pool() -> Pool<PostgresConnectionManager<NoTls>> {
    let manager = PostgresConnectionManager::new_from_stringlike(
        "host=localhost port=5432 dbname=mydb user=postgres password=secret",
        NoTls,
    )
    .unwrap();

    Pool::builder()
        .max_size(20)
        .min_idle(Some(5))
        .connection_timeout(Duration::from_secs(5))
        .build(manager)
        .await
        .expect("Failed to create pool")
}
```

**Choosing between deadpool and bb8:**
- `deadpool` — Simpler API, supports managed and unmanaged pools. Good default choice.
- `bb8` — More mature, closer to Java's HikariCP in API design. Slightly more configuration options.
- Both work well with Tokio. Use whichever has a maintained adapter for your database driver.

---

## Async Testing with tokio::test

**Basic async test:**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_basic_async() {
        let result = fetch_data("test-key").await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "expected-value");
    }

    // Use current_thread flavor for deterministic tests
    #[tokio::test(flavor = "current_thread")]
    async fn test_single_threaded() {
        let counter = std::rc::Rc::new(std::cell::Cell::new(0));
        // Rc is !Send but works on current_thread runtime
        counter.set(counter.get() + 1);
        assert_eq!(counter.get(), 1);
    }

    // Multi-threaded test with specific thread count
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn test_multi_threaded() {
        let (tx, mut rx) = tokio::sync::mpsc::channel(1);
        tokio::spawn(async move {
            tx.send(42).await.unwrap();
        });
        assert_eq!(rx.recv().await, Some(42));
    }
}
```

**Testing with time control (pause/advance):**

```rust
#[cfg(test)]
mod tests {
    use tokio::time::{self, Duration, Instant};

    #[tokio::test]
    async fn test_timeout_behavior() {
        // Pause time so sleep completes instantly
        time::pause();

        let start = Instant::now();
        time::sleep(Duration::from_secs(3600)).await;
        // With paused time, this completes instantly
        assert!(start.elapsed() >= Duration::from_secs(3600));
    }

    #[tokio::test]
    async fn test_interval_fires_correctly() {
        time::pause();

        let mut interval = time::interval(Duration::from_secs(10));
        interval.tick().await; // First tick is immediate

        time::advance(Duration::from_secs(10)).await;
        interval.tick().await; // Second tick

        time::advance(Duration::from_secs(10)).await;
        interval.tick().await; // Third tick
        // Test passes instantly despite "30 seconds" of logical time
    }
}
```

**Mocking with trait objects:**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    struct MockStore {
        data: Arc<Mutex<HashMap<String, String>>>,
    }

    impl MockStore {
        fn new() -> Self {
            Self {
                data: Arc::new(Mutex::new(HashMap::new())),
            }
        }
    }

    impl DataStore for MockStore {
        async fn get(&self, key: &str) -> Option<String> {
            self.data.lock().await.get(key).cloned()
        }

        async fn set(&self, key: &str, value: &str) -> Result<(), StoreError> {
            self.data.lock().await.insert(key.to_string(), value.to_string());
            Ok(())
        }
    }

    #[tokio::test]
    async fn test_with_mock_store() {
        let store = MockStore::new();
        store.set("key1", "value1").await.unwrap();

        let result = store.get("key1").await;
        assert_eq!(result, Some("value1".to_string()));
    }
}
```

---

## Best Practices

1. **Choose bounded channels by default** — Unbounded channels (`mpsc::unbounded_channel`) remove backpressure and can lead to unbounded memory growth under load. Always prefer bounded channels and size the buffer based on expected throughput.

2. **Use `spawn_blocking` for CPU-heavy work** — Never run synchronous CPU-intensive code directly in an async task. Use `tokio::task::spawn_blocking` to offload to a dedicated thread pool.

3. **Prefer `std::sync::Mutex` for short critical sections** — If you do not `.await` while holding the lock, `std::sync::Mutex` is faster and has less overhead than `tokio::sync::Mutex`.

4. **Use `CancellationToken` for graceful shutdown** — It composes better than ad-hoc broadcast channels and integrates cleanly with `select!`.

5. **Always handle `JoinError`** — Spawned tasks can panic. Ignoring the `JoinHandle` silently loses panics. At minimum, log errors from `handle.await`.

6. **Avoid holding locks across `.await` with std Mutex** — `std::sync::MutexGuard` is `!Send` and will cause compilation errors on multi-threaded runtimes if held across await points. Use `tokio::sync::Mutex` when you need to hold a lock across `.await`.

7. **Set timeouts on all external calls** — Network requests, database queries, and RPC calls should always have a timeout using `tokio::time::timeout` or the library's built-in timeout setting.

8. **Leverage `JoinSet` over manual `Vec<JoinHandle>`** — `JoinSet` provides built-in abort-on-drop semantics and cleaner task group management.

9. **Use `biased` in `select!` when ordering matters** — Without `biased`, branch selection is random when multiple branches are ready. Use `biased;` to prioritize shutdown signals over work.

10. **Profile with `tokio-console`** — The `tokio-console` tool provides real-time visibility into task states, poll durations, and resource usage. Instrument your runtime with `console-subscriber` during development.

---

## Anti-Patterns

**Blocking the async runtime:**

```rust
// BAD: Blocking call inside an async task starves the executor
async fn bad_example() {
    std::thread::sleep(Duration::from_secs(5)); // Blocks the entire worker thread!
    std::fs::read_to_string("file.txt");         // Blocking I/O
}

// GOOD: Use async equivalents or spawn_blocking
async fn good_example() {
    tokio::time::sleep(Duration::from_secs(5)).await;
    tokio::fs::read_to_string("file.txt").await.unwrap();

    // For libraries that only offer sync APIs:
    let content = tokio::task::spawn_blocking(|| {
        std::fs::read_to_string("file.txt")
    }).await.unwrap().unwrap();
}
```

**Unbounded growth from ignoring backpressure:**

```rust
// BAD: Unbounded channel with fast producer, slow consumer
let (tx, mut rx) = mpsc::unbounded_channel();
// If the consumer is slow, memory grows without bound

// GOOD: Bounded channel forces the producer to wait
let (tx, mut rx) = mpsc::channel(64);
```

**Holding std::sync::Mutex across await:**

```rust
// BAD: Will not compile on multi-threaded runtime (MutexGuard is !Send)
async fn bad_lock(data: Arc<std::sync::Mutex<Vec<String>>>) {
    let mut guard = data.lock().unwrap();
    some_async_operation().await; // ERROR: guard held across await
    guard.push("value".into());
}

// GOOD: Scope the lock so it is dropped before the await
async fn good_lock(data: Arc<std::sync::Mutex<Vec<String>>>) {
    {
        let mut guard = data.lock().unwrap();
        guard.push("value".into());
    } // guard dropped here
    some_async_operation().await;
}

// ALSO GOOD: Use tokio::sync::Mutex if you need the lock across await
async fn also_good(data: Arc<tokio::sync::Mutex<Vec<String>>>) {
    let mut guard = data.lock().await;
    some_async_operation().await;
    guard.push("value".into());
}
```

**Spawning tasks without tracking them:**

```rust
// BAD: Fire-and-forget tasks — panics are silently lost
tokio::spawn(async { might_panic().await });

// GOOD: Track the handle, at least log errors
let handle = tokio::spawn(async { might_panic().await });
if let Err(e) = handle.await {
    tracing::error!("Task failed: {e}");
}
```

**Attempting async Drop:**

```rust
// BAD: Drop trait cannot call async functions
impl Drop for MyConnection {
    fn drop(&mut self) {
        // Cannot .await here — this will not compile or will block
        // self.close().await; // ERROR
    }
}

// GOOD: Provide an explicit async shutdown method
impl MyConnection {
    async fn shutdown(self) -> Result<()> {
        self.flush().await?;
        self.inner.close().await?;
        Ok(())
    }
}
```

---

## Sources & References

- [Tokio Tutorial — Official Guide](https://tokio.rs/tokio/tutorial)
- [Tokio API Documentation](https://docs.rs/tokio/latest/tokio/)
- [Async Rust Book](https://rust-lang.github.io/async-book/)
- [Tower — Middleware Framework for Rust](https://docs.rs/tower/latest/tower/)
- [tokio-stream Crate Documentation](https://docs.rs/tokio-stream/latest/tokio_stream/)
- [deadpool — Async Connection Pool](https://docs.rs/deadpool/latest/deadpool/)
- [bb8 — Async Connection Pool](https://docs.rs/bb8/latest/bb8/)
- [Alice Ryhl — Async Rust in Practice (Tokio Blog)](https://tokio.rs/blog/2021-07-tokio-tips)
- [Tokio Console — Debugging Tool for Async Rust](https://github.com/tokio-rs/console)
- [backon — Declarative Retry with Backoff](https://docs.rs/backon/latest/backon/)
