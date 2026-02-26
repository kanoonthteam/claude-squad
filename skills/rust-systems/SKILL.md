---
name: rust-systems
description: Rust systems programming — serde serialization, clap CLI parsing, tracing/structured logging, error handling (thiserror/anyhow), config management, process/signal handling, file I/O, cross-platform paths, Cargo workspaces, feature flags, build scripts, FFI, CI/CD
---

# Rust Systems Programming

Comprehensive reference for building production-grade Rust systems software. Covers serialization with serde (JSON, TOML, YAML, MessagePack), CLI argument parsing with clap (derive and builder APIs), structured logging and tracing (tracing, tracing-subscriber, tracing-opentelemetry), error handling with thiserror and anyhow, configuration management (config crate, environment variables), process management and signal handling, file I/O patterns, cross-platform path handling, Cargo workspaces and multi-crate architecture, feature flags, build scripts, FFI basics, custom derive macros, dependency management, and CI/CD pipelines.

## Table of Contents

1. [Serde Serialization & Deserialization](#1-serde-serialization--deserialization)
2. [Clap CLI Argument Parsing](#2-clap-cli-argument-parsing)
3. [Tracing & Structured Logging](#3-tracing--structured-logging)
4. [Error Handling with thiserror and anyhow](#4-error-handling-with-thiserror-and-anyhow)
5. [Configuration Management](#5-configuration-management)
6. [Process Management & Signal Handling](#6-process-management--signal-handling)
7. [File I/O Patterns](#7-file-io-patterns)
8. [Cross-Platform Path Handling](#8-cross-platform-path-handling)
9. [Cargo Workspaces & Multi-Crate Architecture](#9-cargo-workspaces--multi-crate-architecture)
10. [Feature Flags & Conditional Compilation](#10-feature-flags--conditional-compilation)
11. [Build Scripts (build.rs)](#11-build-scripts-buildrs)
12. [FFI Basics — Calling C from Rust](#12-ffi-basics--calling-c-from-rust)
13. [Custom Derive Macros Overview](#13-custom-derive-macros-overview)
14. [Cargo.toml Dependency Management & Publishing](#14-cargotoml-dependency-management--publishing)
15. [CI/CD with Cargo](#15-cicd-with-cargo)
16. [Best Practices](#16-best-practices)
17. [Anti-Patterns](#17-anti-patterns)
18. [Sources & References](#18-sources--references)

---

## 1. Serde Serialization & Deserialization

Serde is the standard framework for serializing and deserializing Rust data structures. It supports JSON, TOML, YAML, MessagePack, and dozens of other formats through separate crates.

### Cargo.toml Dependencies

```toml
[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"            # JSON
toml = "0.8"                # TOML
serde_yaml = "0.9"          # YAML
rmp-serde = "1"             # MessagePack
```

### Derive-Based Serialization

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct AppConfig {
    pub name: String,
    pub version: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls_cert: Option<String>,
    #[serde(rename = "logLevel")]
    pub log_level: LogLevel,
    #[serde(flatten)]
    pub extra: std::collections::HashMap<String, serde_json::Value>,
}

fn default_port() -> u16 {
    8080
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

// JSON round-trip
fn json_example() -> serde_json::Result<()> {
    let config = AppConfig {
        name: "myservice".into(),
        version: "1.0.0".into(),
        port: 3000,
        tls_cert: None,
        log_level: LogLevel::Info,
        extra: Default::default(),
    };
    let json_str = serde_json::to_string_pretty(&config)?;
    let parsed: AppConfig = serde_json::from_str(&json_str)?;
    println!("{parsed:?}");
    Ok(())
}

// TOML round-trip
fn toml_example() -> Result<(), toml::de::Error> {
    let toml_str = r#"
        name = "myservice"
        version = "1.0.0"
        port = 3000
        logLevel = "info"
    "#;
    let config: AppConfig = toml::from_str(toml_str)?;
    println!("{config:?}");
    Ok(())
}

// MessagePack binary serialization
fn msgpack_example() -> Result<(), Box<dyn std::error::Error>> {
    let config = AppConfig {
        name: "myservice".into(),
        version: "1.0.0".into(),
        port: 3000,
        tls_cert: Some("/etc/ssl/cert.pem".into()),
        log_level: LogLevel::Warn,
        extra: Default::default(),
    };
    let bytes = rmp_serde::to_vec(&config)?;
    let restored: AppConfig = rmp_serde::from_slice(&bytes)?;
    println!("MessagePack size: {} bytes", bytes.len());
    println!("{restored:?}");
    Ok(())
}
```

### Key Serde Attributes

| Attribute | Purpose |
|-----------|---------|
| `#[serde(rename = "...")]` | Rename a field during ser/de |
| `#[serde(rename_all = "camelCase")]` | Rename all fields with a casing convention |
| `#[serde(default)]` | Use `Default::default()` when field is missing |
| `#[serde(skip)]` | Skip this field entirely |
| `#[serde(skip_serializing_if = "...")]` | Conditionally skip during serialization |
| `#[serde(flatten)]` | Flatten nested struct or map into parent |
| `#[serde(tag = "type")]` | Internally tagged enum representation |
| `#[serde(untagged)]` | Untagged enum representation |
| `#[serde(with = "...")]` | Custom serialization module |

### Custom Serialization with `#[serde(with)]`

```rust
mod date_format {
    use chrono::NaiveDate;
    use serde::{self, Deserialize, Deserializer, Serializer};

    const FORMAT: &str = "%Y-%m-%d";

    pub fn serialize<S>(date: &NaiveDate, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let s = date.format(FORMAT).to_string();
        serializer.serialize_str(&s)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<NaiveDate, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        NaiveDate::parse_from_str(&s, FORMAT).map_err(serde::de::Error::custom)
    }
}

#[derive(Serialize, Deserialize)]
pub struct Event {
    pub name: String,
    #[serde(with = "date_format")]
    pub date: chrono::NaiveDate,
}
```

---

## 2. Clap CLI Argument Parsing

Clap provides two APIs: derive (declarative) and builder (programmatic). The derive API is preferred for most use cases.

### Derive API

```rust
use clap::{Parser, Subcommand, Args, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "mytool")]
#[command(version, about = "A production systems tool", long_about = None)]
pub struct Cli {
    /// Config file path
    #[arg(short, long, default_value = "config.toml")]
    pub config: PathBuf,

    /// Verbosity level (-v, -vv, -vvv)
    #[arg(short, long, action = clap::ArgAction::Count)]
    pub verbose: u8,

    /// Output format
    #[arg(long, value_enum, default_value_t = OutputFormat::Text)]
    pub format: OutputFormat,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Start the service
    Start(StartArgs),
    /// Stop the service
    Stop {
        /// Force stop without graceful shutdown
        #[arg(long)]
        force: bool,
    },
    /// Show service status
    Status,
    /// Manage configuration
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
}

#[derive(Args, Debug)]
pub struct StartArgs {
    /// Port to listen on
    #[arg(short, long, default_value_t = 8080)]
    pub port: u16,
    /// Bind address
    #[arg(long, default_value = "0.0.0.0")]
    pub bind: String,
    /// Enable TLS
    #[arg(long)]
    pub tls: bool,
}

#[derive(Subcommand, Debug)]
pub enum ConfigAction {
    /// Show current config
    Show,
    /// Set a config value
    Set { key: String, value: String },
    /// Validate config file
    Validate { path: PathBuf },
}

#[derive(ValueEnum, Clone, Debug)]
pub enum OutputFormat {
    Text,
    Json,
    Yaml,
}

fn main() {
    let cli = Cli::parse();

    match cli.verbose {
        0 => println!("Normal output"),
        1 => println!("Verbose output"),
        2 => println!("Very verbose output"),
        _ => println!("Trace-level output"),
    }

    match &cli.command {
        Commands::Start(args) => {
            println!("Starting on {}:{}", args.bind, args.port);
        }
        Commands::Stop { force } => {
            if *force {
                println!("Force stopping...");
            } else {
                println!("Gracefully stopping...");
            }
        }
        Commands::Status => println!("Service is running"),
        Commands::Config { action } => match action {
            ConfigAction::Show => println!("Current config..."),
            ConfigAction::Set { key, value } => println!("Setting {key}={value}"),
            ConfigAction::Validate { path } => println!("Validating {}", path.display()),
        },
    }
}
```

### Builder API

Use the builder API when arguments must be constructed dynamically at runtime:

```rust
use clap::{Arg, Command};

fn build_cli() -> Command {
    Command::new("mytool")
        .version("1.0.0")
        .about("Dynamic CLI example")
        .arg(
            Arg::new("config")
                .short('c')
                .long("config")
                .help("Configuration file")
                .default_value("config.toml"),
        )
        .subcommand(
            Command::new("run")
                .about("Run the service")
                .arg(
                    Arg::new("port")
                        .short('p')
                        .long("port")
                        .help("Port number")
                        .value_parser(clap::value_parser!(u16))
                        .default_value("8080"),
                ),
        )
}
```

---

## 3. Tracing & Structured Logging

The `tracing` ecosystem provides structured, context-aware logging and distributed tracing for Rust applications.

### Dependencies

```toml
[dependencies]
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json", "fmt"] }
tracing-opentelemetry = "0.22"
opentelemetry = "0.21"
opentelemetry_sdk = "0.21"
opentelemetry-otlp = "0.14"
```

### Subscriber Setup

```rust
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

fn init_tracing() {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,my_crate=debug,tower_http=debug"));

    let fmt_layer = tracing_subscriber::fmt::layer()
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true);

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt_layer)
        .init();
}

// JSON-formatted output for production
fn init_json_tracing() {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    let json_layer = tracing_subscriber::fmt::layer()
        .json()
        .with_current_span(true)
        .with_span_list(true);

    tracing_subscriber::registry()
        .with(env_filter)
        .with(json_layer)
        .init();
}
```

### Instrumentation Patterns

```rust
use tracing::{info, warn, error, debug, instrument, span, Level};

#[instrument(skip(password), fields(user_id))]
async fn authenticate_user(username: &str, password: &str) -> Result<User, AuthError> {
    info!(username, "Attempting authentication");

    let user = db::find_user(username).await.map_err(|e| {
        error!(username, error = %e, "Database lookup failed");
        AuthError::DatabaseError(e)
    })?;

    // Record the user_id in the current span
    tracing::Span::current().record("user_id", user.id);

    if !verify_password(password, &user.password_hash) {
        warn!(username, user_id = user.id, "Invalid password attempt");
        return Err(AuthError::InvalidCredentials);
    }

    info!(user_id = user.id, "Authentication successful");
    Ok(user)
}

// Manual span creation for non-async code
fn process_batch(items: &[Item]) {
    let span = span!(Level::INFO, "process_batch", count = items.len());
    let _enter = span.enter();

    for (i, item) in items.iter().enumerate() {
        let item_span = span!(Level::DEBUG, "process_item", index = i, item_id = %item.id);
        let _enter = item_span.enter();

        debug!("Processing item");
        // ... processing logic
    }

    info!("Batch processing complete");
}
```

### OpenTelemetry Integration

```rust
use opentelemetry::global;
use opentelemetry_sdk::trace::TracerProvider;
use opentelemetry_otlp::WithExportConfig;
use tracing_opentelemetry::OpenTelemetryLayer;

fn init_otel_tracing() -> Result<(), Box<dyn std::error::Error>> {
    let exporter = opentelemetry_otlp::new_exporter()
        .tonic()
        .with_endpoint("http://localhost:4317");

    let tracer_provider = TracerProvider::builder()
        .with_batch_exporter(
            opentelemetry_otlp::new_pipeline()
                .tracing()
                .with_exporter(exporter)
                .build_batch_exporter()?,
            opentelemetry_sdk::runtime::Tokio,
        )
        .build();

    let tracer = tracer_provider.tracer("my-service");
    global::set_tracer_provider(tracer_provider);

    let otel_layer = OpenTelemetryLayer::new(tracer);

    let env_filter = EnvFilter::new("info");
    let fmt_layer = tracing_subscriber::fmt::layer();

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt_layer)
        .with(otel_layer)
        .init();

    Ok(())
}
```

---

## 4. Error Handling with thiserror and anyhow

Use `thiserror` for library code where callers need structured errors. Use `anyhow` for application code where you want ergonomic, context-rich error propagation.

### thiserror for Library Errors

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum StorageError {
    #[error("file not found: {path}")]
    NotFound { path: String },

    #[error("permission denied accessing {path}")]
    PermissionDenied { path: String },

    #[error("corrupt data in {file} at offset {offset}")]
    CorruptData { file: String, offset: u64 },

    #[error("I/O error")]
    Io(#[from] std::io::Error),

    #[error("serialization error")]
    Serialization(#[from] serde_json::Error),

    #[error("connection timeout after {duration:?}")]
    Timeout { duration: std::time::Duration },

    #[error(transparent)]
    Other(#[from] Box<dyn std::error::Error + Send + Sync>),
}

// Usage in library code
pub fn read_record(path: &str) -> Result<Record, StorageError> {
    let data = std::fs::read_to_string(path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            StorageError::NotFound { path: path.to_string() }
        } else if e.kind() == std::io::ErrorKind::PermissionDenied {
            StorageError::PermissionDenied { path: path.to_string() }
        } else {
            StorageError::Io(e)
        }
    })?;
    let record: Record = serde_json::from_str(&data)?;
    Ok(record)
}
```

### anyhow for Application Errors

```rust
use anyhow::{Context, Result, bail, ensure};

async fn run_migration(config_path: &str) -> Result<()> {
    let config_str = std::fs::read_to_string(config_path)
        .with_context(|| format!("Failed to read config from {config_path}"))?;

    let config: MigrationConfig = toml::from_str(&config_str)
        .context("Failed to parse migration config")?;

    ensure!(!config.migrations.is_empty(), "No migrations defined in config");

    let db = Database::connect(&config.database_url)
        .await
        .context("Failed to connect to database")?;

    for migration in &config.migrations {
        db.execute(&migration.sql)
            .await
            .with_context(|| format!("Failed to run migration: {}", migration.name))?;
    }

    if config.dry_run {
        bail!("Dry run mode: rolling back all changes");
    }

    Ok(())
}
```

### Combining thiserror and anyhow

```rust
// Library crate exposes thiserror types
pub fn process_file(path: &str) -> Result<Output, StorageError> { /* ... */ }

// Application crate wraps with anyhow context
fn main() -> anyhow::Result<()> {
    let output = process_file("data.json")
        .context("Failed to process primary data file")?;
    println!("{output:?}");
    Ok(())
}
```

---

## 5. Configuration Management

The `config` crate supports layered configuration from files, environment variables, and defaults.

### Layered Config Setup

```rust
use config::{Config, ConfigError, Environment, File};
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub logging: LoggingConfig,
}

#[derive(Debug, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub workers: usize,
    pub request_timeout_secs: u64,
}

#[derive(Debug, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
    pub connect_timeout_secs: u64,
}

#[derive(Debug, Deserialize)]
pub struct LoggingConfig {
    pub level: String,
    pub format: String,
}

impl Settings {
    pub fn load(config_path: Option<PathBuf>) -> Result<Self, ConfigError> {
        let mut builder = Config::builder()
            // Defaults
            .set_default("server.host", "0.0.0.0")?
            .set_default("server.port", 8080)?
            .set_default("server.workers", 4)?
            .set_default("server.request_timeout_secs", 30)?
            .set_default("database.max_connections", 10)?
            .set_default("database.min_connections", 1)?
            .set_default("database.connect_timeout_secs", 5)?
            .set_default("logging.level", "info")?
            .set_default("logging.format", "json")?
            // Base config file
            .add_source(File::with_name("config/default").required(false))
            // Environment-specific config
            .add_source(
                File::with_name(&format!(
                    "config/{}",
                    std::env::var("APP_ENV").unwrap_or_else(|_| "development".into())
                ))
                .required(false),
            );

        // Optional explicit config file
        if let Some(path) = config_path {
            builder = builder.add_source(File::from(path));
        }

        // Environment variables with APP_ prefix (APP_SERVER__PORT -> server.port)
        builder = builder.add_source(
            Environment::with_prefix("APP")
                .separator("__")
                .try_parsing(true),
        );

        builder.build()?.try_deserialize()
    }
}
```

### Validation After Loading

```rust
impl Settings {
    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(self.server.port > 0, "Server port must be positive");
        anyhow::ensure!(
            self.database.max_connections >= self.database.min_connections,
            "max_connections must be >= min_connections"
        );
        anyhow::ensure!(
            !self.database.url.is_empty(),
            "Database URL must not be empty"
        );
        Ok(())
    }
}
```

---

## 6. Process Management & Signal Handling

### Tokio-Based Signal Handling

```rust
use tokio::signal;
use tokio::sync::broadcast;
use tracing::{info, warn};

pub struct GracefulShutdown {
    tx: broadcast::Sender<()>,
}

impl GracefulShutdown {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(1);
        Self { tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<()> {
        self.tx.subscribe()
    }

    pub async fn wait_for_shutdown_signal(&self) {
        let ctrl_c = async {
            signal::ctrl_c()
                .await
                .expect("Failed to install Ctrl+C handler");
        };

        #[cfg(unix)]
        let terminate = async {
            signal::unix::signal(signal::unix::SignalKind::terminate())
                .expect("Failed to install SIGTERM handler")
                .recv()
                .await;
        };

        #[cfg(not(unix))]
        let terminate = std::future::pending::<()>();

        tokio::select! {
            _ = ctrl_c => {
                info!("Received Ctrl+C, starting graceful shutdown");
            }
            _ = terminate => {
                info!("Received SIGTERM, starting graceful shutdown");
            }
        }

        let _ = self.tx.send(());
    }
}

// Usage in main
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let shutdown = GracefulShutdown::new();
    let mut shutdown_rx = shutdown.subscribe();

    // Spawn server task
    let server_handle = tokio::spawn(async move {
        // run_server(&mut shutdown_rx).await
    });

    // Wait for shutdown signal
    shutdown.wait_for_shutdown_signal().await;

    // Allow up to 30 seconds for graceful shutdown
    match tokio::time::timeout(
        std::time::Duration::from_secs(30),
        server_handle,
    ).await {
        Ok(Ok(())) => info!("Server shut down cleanly"),
        Ok(Err(e)) => warn!("Server task panicked: {e}"),
        Err(_) => warn!("Shutdown timed out, forcing exit"),
    }

    Ok(())
}
```

### ctrlc Crate (Simpler Alternative)

```rust
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

fn main() {
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();

    ctrlc::set_handler(move || {
        r.store(false, Ordering::SeqCst);
        println!("Received Ctrl+C, shutting down...");
    })
    .expect("Error setting Ctrl+C handler");

    while running.load(Ordering::SeqCst) {
        // Main loop work
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    println!("Cleanup complete, exiting.");
}
```

---

## 7. File I/O Patterns

### Synchronous I/O with std::fs

```rust
use std::fs;
use std::io::{self, BufRead, Write, BufWriter};
use std::path::Path;

// Read entire file into string
fn read_file(path: &Path) -> io::Result<String> {
    fs::read_to_string(path)
}

// Read file line by line (memory-efficient)
fn process_lines(path: &Path) -> io::Result<Vec<String>> {
    let file = fs::File::open(path)?;
    let reader = io::BufReader::new(file);
    let mut results = Vec::new();
    for line in reader.lines() {
        let line = line?;
        if !line.is_empty() {
            results.push(line);
        }
    }
    Ok(results)
}

// Write with buffering (critical for performance)
fn write_buffered(path: &Path, items: &[String]) -> io::Result<()> {
    let file = fs::File::create(path)?;
    let mut writer = BufWriter::new(file);
    for item in items {
        writeln!(writer, "{item}")?;
    }
    writer.flush()?;
    Ok(())
}

// Atomic write (write to temp, then rename)
fn atomic_write(path: &Path, content: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(dir)?;
    temp.write_all(content)?;
    temp.persist(path).map_err(|e| e.error)?;
    Ok(())
}
```

### Async I/O with tokio::fs

```rust
use tokio::fs;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, BufWriter};

async fn async_read_lines(path: &std::path::Path) -> io::Result<Vec<String>> {
    let file = fs::File::open(path).await?;
    let reader = BufReader::new(file);
    let mut lines = reader.lines();
    let mut results = Vec::new();
    while let Some(line) = lines.next_line().await? {
        results.push(line);
    }
    Ok(results)
}

async fn async_write_file(path: &std::path::Path, data: &[u8]) -> io::Result<()> {
    let file = fs::File::create(path).await?;
    let mut writer = BufWriter::new(file);
    writer.write_all(data).await?;
    writer.flush().await?;
    Ok(())
}

// Directory traversal
async fn list_files_recursive(dir: &std::path::Path) -> io::Result<Vec<std::path::PathBuf>> {
    let mut entries = Vec::new();
    let mut stack = vec![dir.to_path_buf()];

    while let Some(current) = stack.pop() {
        let mut read_dir = fs::read_dir(&current).await?;
        while let Some(entry) = read_dir.next_entry().await? {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else {
                entries.push(path);
            }
        }
    }
    Ok(entries)
}
```

---

## 8. Cross-Platform Path Handling

```rust
use std::path::{Path, PathBuf};

// Constructing paths portably
fn config_path() -> PathBuf {
    let mut path = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."));
    path.push("myapp");
    path.push("config.toml");
    path
}

// Path manipulation
fn path_examples() {
    let base = PathBuf::from("/var/log/myapp");

    // Join paths (uses platform separator)
    let log_file = base.join("app.log");

    // Extension manipulation
    let backup = log_file.with_extension("log.bak");

    // Components
    let path = Path::new("/usr/local/bin/mytool");
    for component in path.components() {
        println!("{component:?}");
    }

    // Parent and file name
    let parent = path.parent(); // Some("/usr/local/bin")
    let filename = path.file_name(); // Some("mytool")
    let stem = path.file_stem(); // Some("mytool")
    let ext = path.extension(); // None

    // Canonicalize (resolve symlinks, make absolute)
    if let Ok(canonical) = path.canonicalize() {
        println!("Canonical: {}", canonical.display());
    }

    // Check existence and type
    if path.exists() && path.is_file() {
        println!("File exists: {}", path.display());
    }
}

// Cross-platform temp directory
fn temp_workspace() -> PathBuf {
    let mut tmp = std::env::temp_dir();
    tmp.push("myapp-workspace");
    std::fs::create_dir_all(&tmp).expect("Failed to create temp workspace");
    tmp
}
```

---

## 9. Cargo Workspaces & Multi-Crate Architecture

### Workspace Root Cargo.toml

```toml
[workspace]
resolver = "2"
members = [
    "crates/core",
    "crates/cli",
    "crates/server",
    "crates/storage",
    "crates/proto",
]

# Workspace-level dependency inheritance
[workspace.package]
version = "0.1.0"
edition = "2021"
rust-version = "1.75"
license = "MIT OR Apache-2.0"
repository = "https://github.com/org/project"

[workspace.dependencies]
# Shared dependencies — members inherit these
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
anyhow = "1"
thiserror = "1"

# Internal crate cross-references
project-core = { path = "crates/core" }
project-storage = { path = "crates/storage" }
project-proto = { path = "crates/proto" }

[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
unwrap_used = "warn"
```

### Member Crate Cargo.toml (inherits workspace settings)

```toml
[package]
name = "project-cli"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[dependencies]
project-core.workspace = true
project-storage.workspace = true
serde.workspace = true
serde_json.workspace = true
tokio.workspace = true
tracing.workspace = true
anyhow.workspace = true
clap = { version = "4", features = ["derive"] }

[lints]
workspace = true
```

### Recommended Workspace Layout

```
project/
  Cargo.toml              # workspace root
  Cargo.lock
  crates/
    core/                  # domain types, traits, pure logic
      Cargo.toml
      src/lib.rs
    storage/               # persistence layer
      Cargo.toml
      src/lib.rs
    proto/                 # protobuf/gRPC definitions
      Cargo.toml
      src/lib.rs
      build.rs
    server/                # HTTP/gRPC server binary
      Cargo.toml
      src/main.rs
    cli/                   # CLI binary
      Cargo.toml
      src/main.rs
  config/                  # configuration files
  tests/                   # integration tests
  benches/                 # benchmarks
```

---

## 10. Feature Flags & Conditional Compilation

### Defining Features in Cargo.toml

```toml
[features]
default = ["json", "toml-config"]
json = ["dep:serde_json"]
yaml = ["dep:serde_yaml"]
toml-config = ["dep:toml"]
msgpack = ["dep:rmp-serde"]
tls = ["dep:rustls", "dep:tokio-rustls"]
otel = ["dep:opentelemetry", "dep:tracing-opentelemetry"]

# Feature groups
full = ["json", "yaml", "toml-config", "msgpack", "tls", "otel"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = { version = "1", optional = true }
serde_yaml = { version = "0.9", optional = true }
toml = { version = "0.8", optional = true }
rmp-serde = { version = "1", optional = true }
rustls = { version = "0.23", optional = true }
tokio-rustls = { version = "0.26", optional = true }
opentelemetry = { version = "0.21", optional = true }
tracing-opentelemetry = { version = "0.22", optional = true }
```

### Using Features in Code

```rust
pub fn serialize(data: &AppConfig, format: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    match format {
        #[cfg(feature = "json")]
        "json" => Ok(serde_json::to_vec_pretty(data)?),

        #[cfg(feature = "yaml")]
        "yaml" => Ok(serde_yaml::to_string(data)?.into_bytes()),

        #[cfg(feature = "toml-config")]
        "toml" => Ok(toml::to_string_pretty(data)?.into_bytes()),

        #[cfg(feature = "msgpack")]
        "msgpack" => Ok(rmp_serde::to_vec(data)?),

        other => Err(format!("Unsupported format: {other}").into()),
    }
}

// Conditional module inclusion
#[cfg(feature = "otel")]
pub mod telemetry;

#[cfg(feature = "tls")]
pub mod tls_config;

// Platform-specific code
#[cfg(target_os = "linux")]
pub fn set_process_priority(nice: i32) {
    unsafe { libc::setpriority(libc::PRIO_PROCESS, 0, nice) };
}

#[cfg(not(target_os = "linux"))]
pub fn set_process_priority(_nice: i32) {
    tracing::warn!("Process priority not supported on this platform");
}
```

---

## 11. Build Scripts (build.rs)

Build scripts run before compilation and can generate code, compile C libraries, set cfg flags, and more.

### Common build.rs Patterns

```rust
// build.rs
use std::process::Command;

fn main() {
    // Tell Cargo to re-run if these change
    println!("cargo::rerun-if-changed=build.rs");
    println!("cargo::rerun-if-changed=proto/service.proto");
    println!("cargo::rerun-if-env-changed=APP_VERSION");

    // Embed git hash at compile time
    let git_hash = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_else(|| "unknown".into());
    println!("cargo::rustc-env=GIT_HASH={}", git_hash.trim());

    // Set version from environment or Cargo.toml
    let version = std::env::var("APP_VERSION")
        .unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string());
    println!("cargo::rustc-env=APP_VERSION={version}");

    // Set custom cfg flags
    if std::env::var("PROFILE").unwrap_or_default() == "release" {
        println!("cargo::rustc-cfg=production");
    }

    // Compile protobuf definitions (using prost-build)
    #[cfg(feature = "grpc")]
    {
        tonic_build::configure()
            .build_server(true)
            .build_client(true)
            .compile(&["proto/service.proto"], &["proto/"])
            .expect("Failed to compile protobuf");
    }
}
```

### Using Build Script Outputs

```rust
// In your source code
const GIT_HASH: &str = env!("GIT_HASH");
const APP_VERSION: &str = env!("APP_VERSION");

fn print_version() {
    println!("Version: {APP_VERSION} (commit: {GIT_HASH})");
}

#[cfg(production)]
fn init_sentry() {
    // Only compiled in release builds
}
```

---

## 12. FFI Basics -- Calling C from Rust

### Linking to a C Library

```rust
// build.rs
fn main() {
    // Link to system library
    println!("cargo::rustc-link-lib=z"); // libz (zlib)

    // Or compile C source files with the cc crate
    cc::Build::new()
        .file("src/native/helper.c")
        .include("src/native/include")
        .flag("-Wall")
        .compile("helper");
}
```

### Declaring FFI Bindings

```rust
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};

// Manual FFI declarations
extern "C" {
    fn compress(
        dest: *mut u8,
        dest_len: *mut libc::c_ulong,
        source: *const u8,
        source_len: libc::c_ulong,
    ) -> c_int;
}

// Safe wrapper around unsafe FFI
pub fn zlib_compress(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut dest_len = (data.len() as f64 * 1.1 + 12.0) as libc::c_ulong;
    let mut dest = vec![0u8; dest_len as usize];

    let result = unsafe {
        compress(
            dest.as_mut_ptr(),
            &mut dest_len,
            data.as_ptr(),
            data.len() as libc::c_ulong,
        )
    };

    if result == 0 {
        dest.truncate(dest_len as usize);
        Ok(dest)
    } else {
        Err(format!("Compression failed with code {result}"))
    }
}

// String handling across FFI boundary
extern "C" {
    fn get_version() -> *const c_char;
    fn process_data(input: *const c_char, length: c_int) -> c_int;
}

pub fn version() -> String {
    unsafe {
        let ptr = get_version();
        if ptr.is_null() {
            return String::from("unknown");
        }
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

pub fn process(input: &str) -> Result<i32, std::ffi::NulError> {
    let c_input = CString::new(input)?;
    let result = unsafe { process_data(c_input.as_ptr(), input.len() as c_int) };
    Ok(result)
}
```

### Using bindgen for Automatic Bindings

Add to `build.rs`:

```rust
fn main() {
    println!("cargo::rerun-if-changed=wrapper.h");
    let bindings = bindgen::Builder::default()
        .header("wrapper.h")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings");
}
```

Include generated bindings:

```rust
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
```

---

## 13. Custom Derive Macros Overview

Procedural derive macros generate code at compile time based on struct/enum definitions.

### Macro Crate Structure

```
my-derive/
  Cargo.toml      # proc-macro = true
  src/lib.rs       # the macro implementation
my-core/
  Cargo.toml
  src/lib.rs       # re-exports the derive macro + trait
```

### Derive Macro Implementation

```rust
// my-derive/Cargo.toml
// [lib]
// proc-macro = true

// my-derive/src/lib.rs
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput, Data, Fields};

#[proc_macro_derive(Builder, attributes(builder))]
pub fn derive_builder(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;
    let builder_name = syn::Ident::new(
        &format!("{name}Builder"),
        name.span(),
    );

    let fields = match &input.data {
        Data::Struct(data) => match &data.fields {
            Fields::Named(fields) => &fields.named,
            _ => panic!("Builder only supports named fields"),
        },
        _ => panic!("Builder only supports structs"),
    };

    let builder_fields = fields.iter().map(|f| {
        let name = &f.ident;
        let ty = &f.ty;
        quote! { #name: Option<#ty> }
    });

    let builder_setters = fields.iter().map(|f| {
        let name = &f.ident;
        let ty = &f.ty;
        quote! {
            pub fn #name(mut self, value: #ty) -> Self {
                self.#name = Some(value);
                self
            }
        }
    });

    let build_fields = fields.iter().map(|f| {
        let name = &f.ident;
        let name_str = name.as_ref().map(|n| n.to_string()).unwrap_or_default();
        quote! {
            #name: self.#name.ok_or_else(|| format!("Missing field: {}", #name_str))?
        }
    });

    let expanded = quote! {
        pub struct #builder_name {
            #(#builder_fields,)*
        }

        impl #name {
            pub fn builder() -> #builder_name {
                #builder_name {
                    #(#(#fields.ident): None,)*
                }
            }
        }

        impl #builder_name {
            #(#builder_setters)*

            pub fn build(self) -> Result<#name, String> {
                Ok(#name {
                    #(#build_fields,)*
                })
            }
        }
    };

    TokenStream::from(expanded)
}
```

### Usage

```rust
use my_core::Builder;

#[derive(Builder)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub max_connections: usize,
}

let config = ServerConfig::builder()
    .host("0.0.0.0".into())
    .port(8080)
    .max_connections(100)
    .build()
    .expect("Failed to build config");
```

---

## 14. Cargo.toml Dependency Management & Publishing

### Dependency Specification Patterns

```toml
[dependencies]
# From crates.io
serde = "1"                           # ^1.0.0
serde = "=1.0.193"                    # exact version
serde = ">=1.0.180, <1.1"            # range

# With features
tokio = { version = "1", features = ["full"] }
serde = { version = "1", default-features = false, features = ["derive", "alloc"] }

# From git
my-lib = { git = "https://github.com/org/my-lib", branch = "main" }
my-lib = { git = "https://github.com/org/my-lib", tag = "v1.0.0" }
my-lib = { git = "https://github.com/org/my-lib", rev = "abc123" }

# Local path (for workspace members or development)
my-core = { path = "../core" }

# Platform-specific dependencies
[target.'cfg(unix)'.dependencies]
libc = "0.2"

[target.'cfg(windows)'.dependencies]
winapi = { version = "0.3", features = ["processthreadsapi"] }
```

### Profile Configuration

```toml
[profile.dev]
opt-level = 0
debug = true
incremental = true

[profile.release]
opt-level = 3
lto = "thin"           # link-time optimization
codegen-units = 1       # better optimization, slower compile
strip = true            # strip debug symbols from binary
panic = "abort"         # smaller binary, no unwinding

[profile.release-with-debug]
inherits = "release"
debug = true
strip = false
```

### Publishing a Crate

```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2021"
description = "A brief description of the crate"
license = "MIT OR Apache-2.0"
repository = "https://github.com/org/my-crate"
documentation = "https://docs.rs/my-crate"
readme = "README.md"
keywords = ["keyword1", "keyword2"]
categories = ["command-line-utilities"]
exclude = ["tests/fixtures/*", ".github/*"]
```

Commands for publishing:

```bash
# Login to crates.io
cargo login

# Dry run to check packaging
cargo publish --dry-run

# Publish
cargo publish

# Yank a version (mark as not recommended)
cargo yank --version 0.1.0
```

---

## 15. CI/CD with Cargo

### GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:

env:
  CARGO_TERM_COLOR: always
  RUSTFLAGS: "-Dwarnings"

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2

      # Format check
      - name: Check formatting
        run: cargo fmt --all -- --check

      # Lint
      - name: Clippy
        run: cargo clippy --all-targets --all-features

      # Build
      - name: Build
        run: cargo build --all-features

      # Tests
      - name: Run tests
        run: cargo test --all-features -- --nocapture

      # Doc tests
      - name: Doc tests
        run: cargo doc --no-deps --all-features

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable

      # Audit dependencies for known vulnerabilities
      - name: Install cargo-audit
        run: cargo install cargo-audit
      - name: Security audit
        run: cargo audit

      # Check dependency licenses and bans
      - name: Install cargo-deny
        run: cargo install cargo-deny
      - name: Dependency check
        run: cargo deny check

  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-tarpaulin
        run: cargo install cargo-tarpaulin
      - name: Generate coverage
        run: cargo tarpaulin --all-features --workspace --out xml
      - name: Upload to codecov
        uses: codecov/codecov-action@v3
        with:
          file: cobertura.xml

  msrv:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install cargo-msrv
        run: cargo install cargo-msrv
      - name: Check MSRV
        run: cargo msrv verify
```

### cargo-deny Configuration

```toml
# deny.toml
[advisories]
vulnerability = "deny"
unmaintained = "warn"
yanked = "warn"

[licenses]
unlicensed = "deny"
allow = [
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
]

[bans]
multiple-versions = "warn"
wildcards = "deny"

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```

### Essential Cargo Commands for CI

```bash
# Format check (no modification)
cargo fmt --all -- --check

# Lint with all features enabled
cargo clippy --all-targets --all-features -- -D warnings

# Run all tests including doc tests
cargo test --all-features --workspace

# Build in release mode
cargo build --release --all-features

# Check for known vulnerabilities
cargo audit

# Check licenses and dependency policy
cargo deny check

# Generate documentation
cargo doc --no-deps --all-features

# Check minimum supported Rust version
cargo msrv verify

# Run benchmarks
cargo bench --all-features
```

---

## 16. Best Practices

**Error Handling**
- Use `thiserror` for library error types; use `anyhow` for application binaries.
- Always provide context when propagating errors with `.context()` or `.with_context()`.
- Never use `.unwrap()` in library code. Reserve `.expect("reason")` for cases where failure is a programming bug.

**Serialization**
- Derive `Serialize` and `Deserialize` rather than implementing manually unless you have a specific formatting need.
- Use `#[serde(deny_unknown_fields)]` on config structs to catch typos in configuration files.
- Always use `#[serde(default)]` or `#[serde(default = "...")]` for fields that may be absent in older data versions.
- Prefer `#[serde(rename_all = "camelCase")]` or `#[serde(rename_all = "snake_case")]` at the container level for consistent naming.

**CLI Design**
- Use clap's derive API for static CLIs and the builder API only when arguments must be constructed at runtime.
- Provide `--version`, `--help`, and shell completions for every CLI tool.
- Use `ValueEnum` for any argument with a fixed set of valid values.
- Return proper exit codes: 0 for success, 1 for general errors, 2 for usage errors.

**Tracing & Logging**
- Use `tracing` instead of the older `log` crate for new projects.
- Add `#[instrument]` to key functions, especially async ones that cross await points.
- Use structured fields (`info!(user_id = %id, action = "login")`) rather than string interpolation.
- Always configure `EnvFilter` so log levels can be changed at runtime via `RUST_LOG`.

**Configuration**
- Layer configuration: defaults, then config file, then environment variables, then CLI flags.
- Validate configuration immediately after loading, before passing it to the rest of the application.
- Use the `APP_` prefix convention for environment variables to avoid collisions.

**Workspaces**
- Place shared types and traits in a `core` crate with no heavy dependencies.
- Use workspace dependency inheritance to keep versions in sync across members.
- Enable workspace lints to enforce consistent code quality.

**Feature Flags**
- Keep the default feature set minimal. Opt users into heavyweight dependencies explicitly.
- Use `dep:` syntax for optional dependencies to avoid implicit feature names.
- Test with `--no-default-features` and `--all-features` in CI.

**File I/O**
- Always use `BufReader` and `BufWriter` for line-oriented or repeated small I/O.
- Use atomic writes (write to temp file, then rename) for files that must not be partially written.
- Prefer `PathBuf` over `String` for all file path handling.

**FFI**
- Wrap every `unsafe` FFI call in a safe Rust function that validates inputs and outputs.
- Use `CString` for passing strings to C and `CStr` for reading strings from C.
- Prefer `bindgen` for large C headers instead of maintaining manual `extern "C"` blocks.

---

## 17. Anti-Patterns

**Using `.unwrap()` Everywhere**
Calling `.unwrap()` on `Result` or `Option` causes panics on failure. In production code, this leads to crashes rather than graceful error handling. Use `?`, `.context()`, or pattern matching instead.

**Ignoring Errors with `let _ = ...`**
Discarding `Result` values silently hides failures. If the error truly does not matter, add a comment explaining why. Otherwise, log it or propagate it.

**Giant Monolithic Crate**
Putting all code in a single crate leads to slow compilation and poor separation of concerns. Split into workspace members with clear dependency boundaries.

**Stringly-Typed Configuration**
Using `HashMap<String, String>` for config instead of typed structs loses compile-time safety and makes validation harder. Always deserialize into strongly-typed structs.

**Over-Using `Arc<Mutex<T>>`**
Reaching for `Arc<Mutex<T>>` as a first resort often indicates a design problem. Consider channels, actor patterns, or restructuring ownership before adding locks.

**Blocking in Async Context**
Calling synchronous `std::fs` functions or `thread::sleep` inside a Tokio async task blocks the entire runtime thread. Use `tokio::fs`, `tokio::time::sleep`, or `tokio::task::spawn_blocking` instead.

**Leaking FFI Memory**
Forgetting to free memory allocated by C libraries causes memory leaks. Always pair allocation with deallocation, and consider RAII wrappers that call the C free function in `Drop`.

**Feature Flag Spaghetti**
Adding too many fine-grained feature flags creates a combinatorial explosion of configurations that are hard to test. Group related functionality into coarse features and test the important combinations.

**Not Pinning Dependencies in CI**
Using bare version ranges in CI can cause builds to break when a transitive dependency publishes a semver-incompatible change. Use `Cargo.lock` in application repos and run `cargo audit` regularly.

**Logging Sensitive Data**
Accidentally logging passwords, tokens, or PII in tracing spans or structured fields. Use `#[instrument(skip(password))]` and review log output for sensitive information.

**Ignoring Clippy Warnings**
Suppressing clippy lints broadly with `#[allow(clippy::all)]` instead of addressing them individually. Clippy catches real bugs. Fix the warnings or allow them individually with a justifying comment.

**Reinventing Existing Crates**
Writing custom serialization, argument parsing, or logging instead of using battle-tested crates like serde, clap, and tracing. The ecosystem crates are well-audited, well-documented, and handle edge cases you have not considered.

---

## 18. Sources & References

- Serde documentation and guide: https://serde.rs/
- Clap derive tutorial and API reference: https://docs.rs/clap/latest/clap/
- Tracing crate documentation: https://docs.rs/tracing/latest/tracing/
- The Rust Programming Language book (official): https://doc.rust-lang.org/book/
- Rust API Guidelines (naming, design, conventions): https://rust-lang.github.io/api-guidelines/
- thiserror crate documentation: https://docs.rs/thiserror/latest/thiserror/
- anyhow crate documentation: https://docs.rs/anyhow/latest/anyhow/
- config crate for layered configuration: https://docs.rs/config/latest/config/
- Cargo reference (workspaces, features, profiles): https://doc.rust-lang.org/cargo/reference/
- Rust FFI Omnibus (comprehensive FFI guide): https://jakegoulding.com/rust-ffi-omnibus/
- cargo-deny documentation: https://embarkstudios.github.io/cargo-deny/
- Rust Cookbook (practical patterns): https://rust-lang-nursery.github.io/rust-cookbook/
