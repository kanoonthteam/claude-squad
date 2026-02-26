---
name: rust-testing
description: Rust testing patterns — cargo test, #[test] and #[tokio::test], unit/integration tests, mockall, proptest, insta snapshots, cargo-tarpaulin coverage, criterion benchmarks, Axum handler testing, and CI integration
---

# Rust Testing Patterns

Production-ready testing patterns for Rust applications. Covers cargo test basics, unit tests in `#[cfg(test)]` modules, integration tests in `tests/` directory, assertion macros, custom assertions, test fixtures, mockall trait mocking, manual test doubles, property-based testing with proptest, snapshot testing with insta, coverage with cargo-tarpaulin, benchmarking with criterion, doc tests, Axum handler testing, database testing with transaction rollbacks, async test patterns, and CI integration.

## Table of Contents

1. [Cargo Test Basics](#cargo-test-basics)
2. [Unit Tests in cfg(test) Modules](#unit-tests-in-cfgtest-modules)
3. [Integration Tests](#integration-tests)
4. [Assertion Macros and Custom Assertions](#assertion-macros-and-custom-assertions)
5. [Test Fixtures and Setup/Teardown](#test-fixtures-and-setupteardown)
6. [Mockall for Trait Mocking](#mockall-for-trait-mocking)
7. [Manual Test Doubles](#manual-test-doubles)
8. [Testing Async Code and Tokio](#testing-async-code-and-tokio)
9. [Axum Handler Testing](#axum-handler-testing)
10. [Database Testing with Transactions](#database-testing-with-transactions)
11. [Property-Based Testing with Proptest](#property-based-testing-with-proptest)
12. [Snapshot Testing with Insta](#snapshot-testing-with-insta)
13. [Doc Tests](#doc-tests)
14. [Test Coverage with Cargo-Tarpaulin](#test-coverage-with-cargo-tarpaulin)
15. [Benchmarking with Criterion](#benchmarking-with-criterion)
16. [Test Filtering, Ordering, and Feature Flags](#test-filtering-ordering-and-feature-flags)
17. [CI Integration](#ci-integration)
18. [Best Practices](#best-practices)
19. [Anti-Patterns](#anti-patterns)
20. [Sources & References](#sources--references)

---

## Cargo Test Basics

The `cargo test` command compiles and runs all tests in the project. Tests are functions annotated with `#[test]` that panic on failure.

```rust
// Run all tests
// $ cargo test

// Run tests matching a name pattern
// $ cargo test test_parse

// Run tests in a specific module
// $ cargo test parser::tests

// Run a single integration test file
// $ cargo test --test integration_api

// Show stdout from passing tests (suppressed by default)
// $ cargo test -- --nocapture

// Run tests on a single thread (useful for shared resources)
// $ cargo test -- --test-threads=1

// List all tests without running them
// $ cargo test -- --list

// Run ignored tests only
// $ cargo test -- --ignored

// Run all tests including ignored
// $ cargo test -- --include-ignored
```

Key flags for `cargo test`:

- `--release` — run tests with optimizations (used in CI for performance tests)
- `--workspace` — run tests across all workspace members
- `--no-fail-fast` — continue running tests even after a failure
- `--lib` — only run unit tests in `src/`
- `--test <name>` — run a specific integration test file
- `--doc` — only run doc tests
- `-p <crate>` — run tests for a specific workspace crate

---

## Unit Tests in cfg(test) Modules

Unit tests live alongside the code they test, inside a `#[cfg(test)]` module. This module is only compiled when running tests, so test-only dependencies and helpers do not affect the production binary.

```rust
// src/parser.rs
use std::collections::HashMap;

#[derive(Debug, PartialEq)]
pub struct Config {
    pub entries: HashMap<String, String>,
}

pub fn parse_config(input: &str) -> Result<Config, ParseError> {
    let mut entries = HashMap::new();
    for (line_num, line) in input.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (key, value) = line
            .split_once('=')
            .ok_or(ParseError::MissingSeparator { line: line_num + 1 })?;
        entries.insert(key.trim().to_string(), value.trim().to_string());
    }
    Ok(Config { entries })
}

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum ParseError {
    #[error("missing '=' separator on line {line}")]
    MissingSeparator { line: usize },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_valid_config() {
        let input = "host = localhost\nport = 8080";
        let config = parse_config(input).unwrap();
        assert_eq!(config.entries.get("host").unwrap(), "localhost");
        assert_eq!(config.entries.get("port").unwrap(), "8080");
    }

    #[test]
    fn test_parse_skips_comments_and_blanks() {
        let input = "# comment\n\nkey = value\n";
        let config = parse_config(input).unwrap();
        assert_eq!(config.entries.len(), 1);
        assert_eq!(config.entries.get("key").unwrap(), "value");
    }

    #[test]
    fn test_parse_missing_separator() {
        let input = "no_equals_here";
        let err = parse_config(input).unwrap_err();
        assert_eq!(err, ParseError::MissingSeparator { line: 1 });
    }

    #[test]
    #[should_panic(expected = "MissingSeparator")]
    fn test_parse_panics_on_invalid() {
        parse_config("bad line").unwrap();
    }

    #[test]
    fn test_empty_input_returns_empty_config() {
        let config = parse_config("").unwrap();
        assert!(config.entries.is_empty());
    }
}
```

Key points:

- `#[cfg(test)]` ensures the module is stripped from release builds
- `use super::*` imports everything from the parent module, including private items
- Unit tests can test private functions since they live inside the same module
- `#[should_panic]` verifies that a test panics with an expected message substring

---

## Integration Tests

Integration tests live in the `tests/` directory at the crate root. Each file in `tests/` is compiled as a separate crate and can only access the public API.

```
my_crate/
  src/
    lib.rs
    parser.rs
  tests/
    common/
      mod.rs        # shared test helpers (not run as a test file)
    test_api.rs     # integration test file
    test_parser.rs  # integration test file
```

```rust
// tests/common/mod.rs — shared helpers
use my_crate::Config;

pub fn sample_config() -> Config {
    my_crate::parse_config("host = 127.0.0.1\nport = 3000").unwrap()
}

pub struct TestContext {
    pub temp_dir: tempfile::TempDir,
}

impl TestContext {
    pub fn new() -> Self {
        Self {
            temp_dir: tempfile::tempdir().unwrap(),
        }
    }
}

// tests/test_parser.rs
mod common;

use my_crate::{parse_config, ParseError};

#[test]
fn test_round_trip_config() {
    let config = common::sample_config();
    assert_eq!(config.entries.get("host").unwrap(), "127.0.0.1");
    assert_eq!(config.entries.get("port").unwrap(), "3000");
}

#[test]
fn test_error_display() {
    let err = parse_config("bad").unwrap_err();
    assert_eq!(err.to_string(), "missing '=' separator on line 1");
}

#[test]
fn test_large_config() {
    let input: String = (0..1000)
        .map(|i| format!("key{i} = value{i}"))
        .collect::<Vec<_>>()
        .join("\n");
    let config = parse_config(&input).unwrap();
    assert_eq!(config.entries.len(), 1000);
}
```

The `common/mod.rs` convention prevents Cargo from treating the `common` directory as a standalone integration test file. Submodules inside `common/` are accessible via `mod common;` in each test file.

---

## Assertion Macros and Custom Assertions

Rust provides three built-in assertion macros, and you can extend them with custom assertion functions.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_standard_assertions() {
        let value = 42;

        // Basic boolean assertion
        assert!(value > 0, "value should be positive, got {value}");

        // Equality assertion (uses PartialEq + Debug)
        assert_eq!(value, 42, "expected 42 but got {value}");

        // Inequality assertion
        assert_ne!(value, 0, "value should not be zero");
    }

    #[test]
    fn test_result_assertions() {
        let ok_result: Result<i32, String> = Ok(42);
        let err_result: Result<i32, String> = Err("fail".into());

        assert!(ok_result.is_ok());
        assert!(err_result.is_err());

        // Unwrap to check the inner value
        assert_eq!(ok_result.unwrap(), 42);
        assert_eq!(err_result.unwrap_err(), "fail");
    }

    #[test]
    fn test_option_assertions() {
        let some_val: Option<u32> = Some(10);
        let none_val: Option<u32> = None;

        assert!(some_val.is_some());
        assert!(none_val.is_none());
        assert_eq!(some_val.unwrap(), 10);
    }

    #[test]
    fn test_float_approximate_equality() {
        let result = 0.1 + 0.2;
        // Floats should never use assert_eq! directly
        assert!((result - 0.3).abs() < f64::EPSILON * 4.0);
    }
}

// Custom assertion helper for reuse across tests
#[cfg(test)]
fn assert_json_contains(json: &serde_json::Value, key: &str, expected: &str) {
    let actual = json
        .get(key)
        .unwrap_or_else(|| panic!("key '{key}' not found in JSON"))
        .as_str()
        .unwrap_or_else(|| panic!("value for '{key}' is not a string"));
    assert_eq!(
        actual, expected,
        "expected '{key}' = '{expected}', got '{actual}'"
    );
}

#[cfg(test)]
mod json_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_json_response_structure() {
        let response = json!({
            "status": "ok",
            "user": "alice"
        });
        assert_json_contains(&response, "status", "ok");
        assert_json_contains(&response, "user", "alice");
    }
}
```

Custom assertion macros (for more advanced patterns):

```rust
#[cfg(test)]
macro_rules! assert_err_contains {
    ($result:expr, $substring:expr) => {
        match &$result {
            Err(e) => {
                let msg = e.to_string();
                assert!(
                    msg.contains($substring),
                    "expected error containing '{}', got '{}'",
                    $substring,
                    msg
                );
            }
            Ok(v) => panic!("expected Err, got Ok({:?})", v),
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_custom_error_macro() {
        let result: Result<(), String> = Err("connection timeout".into());
        assert_err_contains!(result, "timeout");
    }
}
```

---

## Test Fixtures and Setup/Teardown

Rust does not have built-in before/after hooks. Use constructor patterns, the `Drop` trait for cleanup, and helper functions for test fixtures.

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    /// Test fixture that creates a temporary workspace with sample files.
    struct TestWorkspace {
        dir: TempDir,
    }

    impl TestWorkspace {
        fn new() -> Self {
            let dir = TempDir::new().unwrap();
            // Setup: create fixture files
            fs::write(dir.path().join("config.toml"), "[server]\nport = 8080")
                .unwrap();
            fs::write(dir.path().join("data.csv"), "name,age\nalice,30\nbob,25")
                .unwrap();
            Self { dir }
        }

        fn path(&self) -> &std::path::Path {
            self.dir.path()
        }

        fn config_path(&self) -> std::path::PathBuf {
            self.dir.path().join("config.toml")
        }
    }

    // Drop is called automatically — no explicit teardown needed.
    // TempDir::drop() removes the directory and all contents.

    #[test]
    fn test_reads_config_from_workspace() {
        let ws = TestWorkspace::new();
        let content = fs::read_to_string(ws.config_path()).unwrap();
        assert!(content.contains("port = 8080"));
    }

    #[test]
    fn test_lists_files_in_workspace() {
        let ws = TestWorkspace::new();
        let entries: Vec<_> = fs::read_dir(ws.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .collect();
        assert_eq!(entries.len(), 2);
    }
}
```

For shared setup across multiple test files, place fixtures in `tests/common/mod.rs` or a dedicated `tests/fixtures/` directory.

---

## Mockall for Trait Mocking

[mockall](https://crates.io/crates/mockall) generates mock implementations of traits at compile time using procedural macros.

```toml
# Cargo.toml
[dev-dependencies]
mockall = "0.13"
tokio = { version = "1", features = ["full", "test-util"] }
```

```rust
use async_trait::async_trait;

#[async_trait]
pub trait UserRepository: Send + Sync {
    async fn find_by_id(&self, id: u64) -> Result<Option<User>, DbError>;
    async fn save(&self, user: &User) -> Result<(), DbError>;
    async fn delete(&self, id: u64) -> Result<bool, DbError>;
}

#[derive(Debug, Clone, PartialEq)]
pub struct User {
    pub id: u64,
    pub name: String,
    pub email: String,
}

#[derive(Debug, thiserror::Error)]
pub enum DbError {
    #[error("connection failed")]
    ConnectionFailed,
    #[error("not found")]
    NotFound,
}

pub struct UserService<R: UserRepository> {
    repo: R,
}

impl<R: UserRepository> UserService<R> {
    pub fn new(repo: R) -> Self {
        Self { repo }
    }

    pub async fn get_user(&self, id: u64) -> Result<User, DbError> {
        self.repo
            .find_by_id(id)
            .await?
            .ok_or(DbError::NotFound)
    }

    pub async fn rename_user(&self, id: u64, new_name: String) -> Result<User, DbError> {
        let mut user = self.get_user(id).await?;
        user.name = new_name;
        self.repo.save(&user).await?;
        Ok(user)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;
    use mockall::mock;

    mock! {
        pub UserRepo {}

        #[async_trait]
        impl UserRepository for UserRepo {
            async fn find_by_id(&self, id: u64) -> Result<Option<User>, DbError>;
            async fn save(&self, user: &User) -> Result<(), DbError>;
            async fn delete(&self, id: u64) -> Result<bool, DbError>;
        }
    }

    fn sample_user() -> User {
        User {
            id: 1,
            name: "Alice".to_string(),
            email: "alice@example.com".to_string(),
        }
    }

    #[tokio::test]
    async fn test_get_user_found() {
        let mut mock_repo = MockUserRepo::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(1))
            .times(1)
            .returning(|_| Ok(Some(sample_user())));

        let service = UserService::new(mock_repo);
        let user = service.get_user(1).await.unwrap();
        assert_eq!(user.name, "Alice");
    }

    #[tokio::test]
    async fn test_get_user_not_found() {
        let mut mock_repo = MockUserRepo::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(999))
            .times(1)
            .returning(|_| Ok(None));

        let service = UserService::new(mock_repo);
        let err = service.get_user(999).await.unwrap_err();
        assert!(matches!(err, DbError::NotFound));
    }

    #[tokio::test]
    async fn test_rename_user() {
        let mut mock_repo = MockUserRepo::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(1))
            .returning(|_| Ok(Some(sample_user())));
        mock_repo
            .expect_save()
            .withf(|user| user.name == "Bob")
            .times(1)
            .returning(|_| Ok(()));

        let service = UserService::new(mock_repo);
        let user = service.rename_user(1, "Bob".to_string()).await.unwrap();
        assert_eq!(user.name, "Bob");
    }
}
```

---

## Manual Test Doubles

When mockall is too heavy or you need more control, implement test doubles manually.

```rust
pub trait EmailSender: Send + Sync {
    fn send(&self, to: &str, subject: &str, body: &str) -> Result<(), String>;
}

// Production implementation
pub struct SmtpSender {
    pub host: String,
}

impl EmailSender for SmtpSender {
    fn send(&self, to: &str, subject: &str, body: &str) -> Result<(), String> {
        // Real SMTP logic
        todo!()
    }
}

// Fake: records calls for later inspection
#[cfg(test)]
pub struct FakeEmailSender {
    pub sent: std::sync::Mutex<Vec<(String, String, String)>>,
    pub should_fail: bool,
}

#[cfg(test)]
impl FakeEmailSender {
    pub fn new() -> Self {
        Self {
            sent: std::sync::Mutex::new(Vec::new()),
            should_fail: false,
        }
    }

    pub fn failing() -> Self {
        Self {
            sent: std::sync::Mutex::new(Vec::new()),
            should_fail: true,
        }
    }

    pub fn sent_messages(&self) -> Vec<(String, String, String)> {
        self.sent.lock().unwrap().clone()
    }
}

#[cfg(test)]
impl EmailSender for FakeEmailSender {
    fn send(&self, to: &str, subject: &str, body: &str) -> Result<(), String> {
        if self.should_fail {
            return Err("SMTP unavailable".into());
        }
        self.sent.lock().unwrap().push((
            to.to_string(),
            subject.to_string(),
            body.to_string(),
        ));
        Ok(())
    }
}

// Stub: always succeeds, discards data
#[cfg(test)]
pub struct StubEmailSender;

#[cfg(test)]
impl EmailSender for StubEmailSender {
    fn send(&self, _to: &str, _subject: &str, _body: &str) -> Result<(), String> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_sends_email() {
        let sender = FakeEmailSender::new();
        sender.send("bob@example.com", "Hello", "Welcome!").unwrap();

        let messages = sender.sent_messages();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].0, "bob@example.com");
        assert_eq!(messages[0].1, "Hello");
    }

    #[test]
    fn test_notification_handles_smtp_failure() {
        let sender = FakeEmailSender::failing();
        let result = sender.send("bob@example.com", "Hello", "Welcome!");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("SMTP unavailable"));
    }
}
```

---

## Testing Async Code and Tokio

Use `#[tokio::test]` for async test functions. Configure the runtime flavor for multi-threaded tests.

```rust
// Cargo.toml
// [dev-dependencies]
// tokio = { version = "1", features = ["full", "test-util"] }

#[cfg(test)]
mod tests {
    use std::time::Duration;
    use tokio::time;

    // Default: single-threaded runtime (current_thread)
    #[tokio::test]
    async fn test_async_operation() {
        let result = async { 42 }.await;
        assert_eq!(result, 42);
    }

    // Multi-threaded runtime for concurrency tests
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn test_concurrent_tasks() {
        let (tx, rx) = tokio::sync::oneshot::channel();

        tokio::spawn(async move {
            tx.send(42).unwrap();
        });

        let value = rx.await.unwrap();
        assert_eq!(value, 42);
    }

    // Testing timeouts
    #[tokio::test]
    async fn test_operation_completes_within_deadline() {
        let result = time::timeout(Duration::from_secs(1), async {
            // Simulate work
            time::sleep(Duration::from_millis(100)).await;
            "done"
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "done");
    }

    // Pausing time for deterministic tests
    #[tokio::test]
    async fn test_with_paused_time() {
        time::pause();

        let start = time::Instant::now();
        time::sleep(Duration::from_secs(60)).await;
        let elapsed = start.elapsed();

        // Time advances instantly when paused
        assert!(elapsed >= Duration::from_secs(60));
        // But wall-clock time barely passed
    }

    // Testing channels
    #[tokio::test]
    async fn test_mpsc_channel() {
        let (tx, mut rx) = tokio::sync::mpsc::channel(10);

        tx.send("hello").await.unwrap();
        tx.send("world").await.unwrap();
        drop(tx); // close the sender

        let mut messages = Vec::new();
        while let Some(msg) = rx.recv().await {
            messages.push(msg);
        }

        assert_eq!(messages, vec!["hello", "world"]);
    }
}
```

---

## Axum Handler Testing

Test Axum handlers using `axum::test` utilities or the `tower::ServiceExt` trait to send requests directly without starting an HTTP server.

```rust
use axum::{
    extract::{Path, State, Json},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<dyn UserRepository + Send + Sync>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct CreateUserRequest {
    pub name: String,
    pub email: String,
}

pub async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<u64>,
) -> impl IntoResponse {
    match state.db.find_by_id(id).await {
        Ok(Some(user)) => Json(user).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

pub async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> impl IntoResponse {
    if payload.name.is_empty() {
        return (StatusCode::BAD_REQUEST, "name is required").into_response();
    }
    let user = User {
        id: 0,
        name: payload.name,
        email: payload.email,
    };
    match state.db.save(&user).await {
        Ok(()) => (StatusCode::CREATED, Json(user)).into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/users/{id}", get(get_user))
        .route("/users", post(create_user))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    fn test_app() -> Router {
        let mut mock_repo = MockUserRepo::new();
        mock_repo.expect_find_by_id().returning(|id| {
            if id == 1 {
                Ok(Some(User {
                    id: 1,
                    name: "Alice".into(),
                    email: "alice@test.com".into(),
                }))
            } else {
                Ok(None)
            }
        });
        mock_repo.expect_save().returning(|_| Ok(()));

        let state = AppState {
            db: Arc::new(mock_repo),
        };
        app(state)
    }

    #[tokio::test]
    async fn test_get_user_returns_200() {
        let app = test_app();
        let request = Request::builder()
            .uri("/users/1")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let body = response.into_body().collect().await.unwrap().to_bytes();
        let user: User = serde_json::from_slice(&body).unwrap();
        assert_eq!(user.name, "Alice");
    }

    #[tokio::test]
    async fn test_get_user_returns_404() {
        let app = test_app();
        let request = Request::builder()
            .uri("/users/999")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_create_user_returns_201() {
        let app = test_app();
        let request = Request::builder()
            .method("POST")
            .uri("/users")
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&CreateUserRequest {
                    name: "Bob".into(),
                    email: "bob@test.com".into(),
                })
                .unwrap(),
            ))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::CREATED);
    }

    #[tokio::test]
    async fn test_create_user_validates_name() {
        let app = test_app();
        let request = Request::builder()
            .method("POST")
            .uri("/users")
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&CreateUserRequest {
                    name: "".into(),
                    email: "nobody@test.com".into(),
                })
                .unwrap(),
            ))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
}
```

---

## Database Testing with Transactions

Wrap each test in a database transaction that rolls back after the test, ensuring isolation and fast cleanup.

```rust
use sqlx::{PgPool, postgres::PgPoolOptions};

/// Create a shared pool for integration tests.
/// Uses the TEST_DATABASE_URL environment variable.
async fn test_pool() -> PgPool {
    let url = std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://localhost/myapp_test".into());
    PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .expect("failed to connect to test database")
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::Executor;

    /// Each test gets its own transaction that is rolled back.
    #[tokio::test]
    async fn test_insert_and_query_user() {
        let pool = test_pool().await;
        let mut tx = pool.begin().await.unwrap();

        // Insert within the transaction
        sqlx::query("INSERT INTO users (name, email) VALUES ($1, $2)")
            .bind("TestUser")
            .bind("test@example.com")
            .execute(&mut *tx)
            .await
            .unwrap();

        // Query within the same transaction
        let row: (String,) =
            sqlx::query_as("SELECT name FROM users WHERE email = $1")
                .bind("test@example.com")
                .fetch_one(&mut *tx)
                .await
                .unwrap();
        assert_eq!(row.0, "TestUser");

        // Transaction is NOT committed — it rolls back when `tx` is dropped.
        // This keeps the test database clean.
        tx.rollback().await.unwrap();
    }

    /// Helper macro to wrap tests in a transaction.
    macro_rules! db_test {
        ($name:ident, $tx:ident, $body:block) => {
            #[tokio::test]
            async fn $name() {
                let pool = test_pool().await;
                let mut $tx = pool.begin().await.unwrap();
                $body
                $tx.rollback().await.unwrap();
            }
        };
    }

    db_test!(test_user_count, tx, {
        sqlx::query("INSERT INTO users (name, email) VALUES ('A', 'a@test.com')")
            .execute(&mut *tx)
            .await
            .unwrap();

        let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        assert!(count.0 >= 1);
    });
}
```

For `sqlx`, you can also use the `#[sqlx::test]` macro which automatically provisions a test database per test function, runs migrations, and cleans up after each test.

---

## Property-Based Testing with Proptest

[proptest](https://crates.io/crates/proptest) generates random inputs to find edge cases that hand-written tests miss.

```toml
# Cargo.toml
[dev-dependencies]
proptest = "1"
```

```rust
use proptest::prelude::*;

/// A function that should round-trip: encode then decode.
pub fn encode(data: &[u8]) -> String {
    data.iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn decode(hex: &str) -> Result<Vec<u8>, String> {
    if hex.len() % 2 != 0 {
        return Err("odd length".into());
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&hex[i..i + 2], 16)
                .map_err(|e| e.to_string())
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use proptest::collection::vec;

    proptest! {
        // Round-trip property: decode(encode(x)) == x for all byte vectors
        #[test]
        fn test_hex_roundtrip(data in vec(any::<u8>(), 0..256)) {
            let encoded = encode(&data);
            let decoded = decode(&encoded).unwrap();
            prop_assert_eq!(decoded, data);
        }

        // Encoded length is always 2x the input length
        #[test]
        fn test_encoded_length(data in vec(any::<u8>(), 0..100)) {
            let encoded = encode(&data);
            prop_assert_eq!(encoded.len(), data.len() * 2);
        }

        // Encoded output only contains hex characters
        #[test]
        fn test_encoded_chars(data in vec(any::<u8>(), 1..50)) {
            let encoded = encode(&data);
            prop_assert!(encoded.chars().all(|c| c.is_ascii_hexdigit()));
        }

        // Odd-length strings always fail decoding
        #[test]
        fn test_odd_length_fails(s in "[0-9a-f]{1,99}") {
            if s.len() % 2 != 0 {
                prop_assert!(decode(&s).is_err());
            }
        }
    }

    // Custom strategies for domain types
    fn valid_email() -> impl Strategy<Value = String> {
        ("[a-z]{3,10}", "[a-z]{2,6}", "com|org|net")
            .prop_map(|(user, domain, tld)| format!("{user}@{domain}.{tld}"))
    }

    proptest! {
        #[test]
        fn test_email_contains_at(email in valid_email()) {
            prop_assert!(email.contains('@'));
            prop_assert!(email.contains('.'));
        }
    }
}
```

Proptest shrinks failing inputs to the smallest reproducing case and saves regressions in a `proptest-regressions/` directory for deterministic replay.

---

## Snapshot Testing with Insta

[insta](https://crates.io/crates/insta) captures output snapshots and alerts you when they change. Use `cargo insta review` to interactively accept or reject changes.

```toml
# Cargo.toml
[dev-dependencies]
insta = { version = "1", features = ["yaml", "json", "redactions"] }
```

```rust
use serde::Serialize;

#[derive(Serialize, Debug)]
pub struct Report {
    pub title: String,
    pub items: Vec<ReportItem>,
    pub generated_at: String,
}

#[derive(Serialize, Debug)]
pub struct ReportItem {
    pub name: String,
    pub count: u32,
}

pub fn generate_report() -> Report {
    Report {
        title: "Weekly Summary".into(),
        items: vec![
            ReportItem { name: "Users".into(), count: 150 },
            ReportItem { name: "Orders".into(), count: 42 },
        ],
        generated_at: "2026-02-26T00:00:00Z".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use insta::{assert_yaml_snapshot, assert_json_snapshot, assert_debug_snapshot};

    #[test]
    fn test_report_yaml_snapshot() {
        let report = generate_report();
        assert_yaml_snapshot!(report);
    }

    #[test]
    fn test_report_json_snapshot() {
        let report = generate_report();
        assert_json_snapshot!(report);
    }

    #[test]
    fn test_report_debug_snapshot() {
        let report = generate_report();
        assert_debug_snapshot!(report);
    }

    // Redactions replace volatile values (timestamps, IDs) with placeholders
    #[test]
    fn test_report_with_redactions() {
        let report = generate_report();
        assert_yaml_snapshot!(report, {
            ".generated_at" => "[timestamp]",
        });
    }

    // Inline snapshots: the expected value is written into the source file
    #[test]
    fn test_report_inline() {
        let report = generate_report();
        insta::assert_snapshot!(report.title, @"Weekly Summary");
    }
}

// Workflow:
// 1. Run tests: cargo test
// 2. New snapshots are written to `src/snapshots/` as `.snap.new` files
// 3. Review: cargo insta review
// 4. Accept: updates `.snap` files and deletes `.snap.new`
```

---

## Doc Tests

Doc tests verify that code examples in documentation compile and run correctly. They are executed by `cargo test --doc`.

```rust
/// Parses a key-value pair from a string.
///
/// # Examples
///
/// ```
/// use my_crate::parse_kv;
///
/// let (key, value) = parse_kv("name=Alice").unwrap();
/// assert_eq!(key, "name");
/// assert_eq!(value, "Alice");
/// ```
///
/// Returns an error if no `=` separator is found:
///
/// ```
/// use my_crate::parse_kv;
///
/// assert!(parse_kv("no_separator").is_err());
/// ```
///
/// Handles whitespace around the separator:
///
/// ```
/// use my_crate::parse_kv;
///
/// let (key, value) = parse_kv("key = value").unwrap();
/// assert_eq!(key, "key");
/// assert_eq!(value, "value");
/// ```
pub fn parse_kv(input: &str) -> Result<(&str, &str), &'static str> {
    let (key, value) = input.split_once('=').ok_or("missing '=' separator")?;
    Ok((key.trim(), value.trim()))
}

/// A configuration builder.
///
/// # Examples
///
/// ```
/// use my_crate::ConfigBuilder;
///
/// let config = ConfigBuilder::new()
///     .host("localhost")
///     .port(8080)
///     .build();
///
/// assert_eq!(config.host, "localhost");
/// assert_eq!(config.port, 8080);
/// ```
///
/// Doc tests that should compile but not run use `no_run`:
///
/// ```no_run
/// use my_crate::ConfigBuilder;
///
/// let config = ConfigBuilder::new()
///     .host("production.example.com")
///     .port(443)
///     .build();
/// // This would connect to a real server
/// config.connect().await;
/// ```
///
/// Code that should not even compile (demonstrating errors) uses `compile_fail`:
///
/// ```compile_fail
/// use my_crate::ConfigBuilder;
///
/// // This should fail because port is required
/// let config = ConfigBuilder::new().build();
/// ```
pub struct ConfigBuilder {
    host: String,
    port: u16,
}
```

---

## Test Coverage with Cargo-Tarpaulin

[cargo-tarpaulin](https://crates.io/crates/cargo-tarpaulin) measures code coverage for Rust projects. It supports line and branch coverage and outputs reports for CI.

```bash
# Install
cargo install cargo-tarpaulin

# Run coverage
cargo tarpaulin

# Generate HTML report
cargo tarpaulin --out html

# Generate multiple report formats
cargo tarpaulin --out xml --out html --out json

# Exclude test code from coverage
cargo tarpaulin --ignore-tests

# Set minimum coverage threshold (fail CI if below)
cargo tarpaulin --fail-under 80

# Coverage for specific packages in a workspace
cargo tarpaulin -p my_crate_core -p my_crate_api

# Exclude files from coverage
cargo tarpaulin --exclude-files "*/generated/*" --exclude-files "*/migrations/*"
```

CI integration with GitHub Actions:

```yaml
# .github/workflows/coverage.yml
- name: Install tarpaulin
  run: cargo install cargo-tarpaulin

- name: Run coverage
  run: cargo tarpaulin --out xml --fail-under 80

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    file: cobertura.xml
```

---

## Benchmarking with Criterion

[criterion](https://crates.io/crates/criterion) provides statistically rigorous benchmarks with automatic outlier detection and comparison reports.

```toml
# Cargo.toml
[dev-dependencies]
criterion = { version = "0.5", features = ["html_reports"] }

[[bench]]
name = "parser_bench"
harness = false
```

```rust
// benches/parser_bench.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use my_crate::parse_config;

fn bench_parse_small(c: &mut Criterion) {
    let input = "key1 = value1\nkey2 = value2\nkey3 = value3";
    c.bench_function("parse_small_config", |b| {
        b.iter(|| parse_config(black_box(input)))
    });
}

fn bench_parse_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("parse_scaling");
    for size in [10, 100, 1000, 10000] {
        let input: String = (0..size)
            .map(|i| format!("key{i} = value{i}"))
            .collect::<Vec<_>>()
            .join("\n");
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &input,
            |b, input| {
                b.iter(|| parse_config(black_box(input)));
            },
        );
    }
    group.finish();
}

criterion_group!(benches, bench_parse_small, bench_parse_scaling);
criterion_main!(benches);

// Run benchmarks:
// $ cargo bench
// $ cargo bench -- parse_small   # filter by name
//
// Reports are generated in target/criterion/
```

---

## Test Filtering, Ordering, and Feature Flags

### Filtering and Ignoring Tests

```rust
#[cfg(test)]
mod tests {
    // Standard test
    #[test]
    fn test_quick_unit() {
        assert!(true);
    }

    // Ignored by default; run with `cargo test -- --ignored`
    #[test]
    #[ignore = "requires external service"]
    fn test_external_api() {
        // Calls a real API endpoint
    }

    // Ignored slow test
    #[test]
    #[ignore = "takes > 30 seconds"]
    fn test_large_dataset() {
        // Process 1M records
    }
}

// Run specific patterns:
// $ cargo test test_quick         # matches test name substring
// $ cargo test -- --ignored       # run only ignored tests
// $ cargo test -- --include-ignored  # run all, including ignored
```

### Test-Specific Feature Flags

```toml
# Cargo.toml
[features]
default = []
test-slow = []        # Enable slow integration tests
test-external = []    # Enable tests that hit external services
```

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_always_runs() {
        assert!(true);
    }

    #[test]
    #[cfg(feature = "test-slow")]
    fn test_slow_operation() {
        // Only compiled and run with: cargo test --features test-slow
        std::thread::sleep(std::time::Duration::from_secs(5));
    }

    #[test]
    #[cfg(feature = "test-external")]
    fn test_real_api_call() {
        // Only compiled and run with: cargo test --features test-external
    }
}
```

### Test Ordering

By default, Rust runs tests in parallel in an undefined order. Control execution:

```bash
# Run tests serially (one at a time)
cargo test -- --test-threads=1

# Combine with filtering
cargo test database -- --test-threads=1
```

Use the `serial_test` crate for tests that must not run concurrently:

```rust
// Cargo.toml: serial_test = "3"
use serial_test::serial;

#[test]
#[serial]
fn test_global_state_a() {
    // Runs serially with other #[serial] tests
}

#[test]
#[serial]
fn test_global_state_b() {
    // Will not run at the same time as test_global_state_a
}
```

---

## CI Integration

A complete GitHub Actions workflow for Rust testing.

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [main]
  pull_request:

env:
  CARGO_TERM_COLOR: always
  RUSTFLAGS: "-Dwarnings"

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: myapp_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt

      - name: Cache cargo registry and build
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}

      - name: Check formatting
        run: cargo fmt --all -- --check

      - name: Run clippy
        run: cargo clippy --all-targets --all-features

      - name: Run unit tests
        run: cargo test --lib --workspace

      - name: Run integration tests
        run: cargo test --test '*' --workspace
        env:
          TEST_DATABASE_URL: postgres://test:test@localhost:5432/myapp_test

      - name: Run doc tests
        run: cargo test --doc --workspace

      - name: Run release tests
        run: cargo test --release --workspace
        env:
          TEST_DATABASE_URL: postgres://test:test@localhost:5432/myapp_test

      - name: Install tarpaulin
        run: cargo install cargo-tarpaulin

      - name: Generate coverage
        run: cargo tarpaulin --out xml --fail-under 70 --ignore-tests

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: cobertura.xml
          token: ${{ secrets.CODECOV_TOKEN }}

  # Separate job for slow / ignored tests
  slow-tests:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Run slow tests
        run: cargo test --features test-slow -- --ignored --test-threads=1
```

Key CI considerations:

- **`cargo test --release`** catches optimized-build-only bugs and runs performance-sensitive tests closer to production
- **Separate unit and integration test steps** for faster feedback on failures
- **`RUSTFLAGS: "-Dwarnings"`** treats all warnings as errors in CI
- **Cache the `target/` directory** and cargo registry to speed up builds
- **Use `--fail-under`** with tarpaulin to enforce minimum coverage
- **Run `cargo fmt` and `cargo clippy`** before tests to catch issues early

---

## Best Practices

1. **Prefer unit tests for logic, integration tests for boundaries** — Unit tests in `#[cfg(test)]` are fast and can access private functions. Integration tests in `tests/` verify the public API and system interactions.
2. **Use `#[should_panic]` sparingly** — Prefer returning `Result<(), E>` from test functions and asserting on the error, which gives better diagnostic output.
3. **Keep tests deterministic** — Avoid relying on wall-clock time, random numbers, or external services. Use `tokio::time::pause()` for time-dependent code.
4. **Test error paths explicitly** — Every `Result`-returning function should have tests for both `Ok` and `Err` branches.
5. **Use proptest for parsing and serialization** — Round-trip property tests (encode/decode, serialize/deserialize) catch edge cases hand-written tests miss.
6. **Use insta for complex output** — Snapshot tests are ideal for CLI output, error messages, JSON responses, and formatted reports.
7. **Run `cargo test --doc` in CI** — Doc tests ensure your documentation examples stay correct as code evolves.
8. **Isolate database tests with transactions** — Roll back after each test to avoid test pollution and speed up cleanup.
9. **Use feature flags for slow or external tests** — Gate tests behind `#[cfg(feature = "test-slow")]` so they do not slow down local development.
10. **Benchmark before and after optimization** — Use criterion to measure performance changes with statistical rigor instead of guessing.

---

## Anti-Patterns

```rust
// BAD: Sleeping for arbitrary durations in tests
#[tokio::test]
async fn test_bad_sleep() {
    start_background_task().await;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await; // Flaky!
    assert!(check_result().await);
}

// GOOD: Use channels, events, or tokio::time::pause() instead
#[tokio::test]
async fn test_good_event() {
    let (tx, rx) = tokio::sync::oneshot::channel();
    start_background_task_with_notify(tx).await;
    let result = rx.await.unwrap(); // Waits for actual completion
    assert!(result);
}

// BAD: Sharing mutable state between tests via static mut
static mut COUNTER: i32 = 0;

#[test]
fn test_bad_shared_state() {
    unsafe { COUNTER += 1; } // Data race between parallel tests!
}

// GOOD: Each test owns its state
#[test]
fn test_good_own_state() {
    let mut counter = 0;
    counter += 1;
    assert_eq!(counter, 1);
}

// BAD: Testing implementation details (exact SQL queries, private method calls)
// GOOD: Test observable behavior through the public API

// BAD: Ignoring tests that fail instead of fixing them
#[test]
#[ignore = "TODO: fix later"]  // Tech debt that accumulates
fn test_something_broken() {}

// GOOD: Fix the test or delete it. Use #[ignore] only for genuinely slow tests.

// BAD: No assertions in tests
#[test]
fn test_no_assertions() {
    let _ = parse_config("key=value"); // "Tests" nothing — just checks it doesn't panic
}

// GOOD: Always assert on the result
#[test]
fn test_with_assertions() {
    let config = parse_config("key=value").unwrap();
    assert_eq!(config.entries.get("key").unwrap(), "value");
}

// BAD: Enormous integration tests that test everything at once
// GOOD: Small, focused tests that each verify one behavior

// BAD: Hardcoding file paths or port numbers in tests
// GOOD: Use tempfile for paths, port 0 for dynamic port allocation
```

---

## Sources & References

- [The Rust Programming Language - Writing Automated Tests](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [Rust By Example - Testing](https://doc.rust-lang.org/rust-by-example/testing.html)
- [mockall - Rust Mock Framework](https://docs.rs/mockall/latest/mockall/)
- [proptest - Property-Based Testing for Rust](https://proptest-rs.github.io/proptest/intro.html)
- [insta - Snapshot Testing for Rust](https://insta.rs/)
- [cargo-tarpaulin - Code Coverage for Rust](https://github.com/xd009642/tarpaulin)
- [Criterion.rs - Statistics-Driven Benchmarking](https://bheisler.github.io/criterion.rs/book/)
- [Axum Testing Guide](https://docs.rs/axum/latest/axum/#testing)
- [sqlx - Compile-Time Checked SQL](https://docs.rs/sqlx/latest/sqlx/)
- [Tokio - Testing Utilities](https://docs.rs/tokio/latest/tokio/time/fn.pause.html)
