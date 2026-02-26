---
name: rust-web
description: Rust web development with Axum 0.7+ — routers, handlers, extractors, middleware, error handling, SeaORM entities, migrations, CRUD, tower-http layers, authentication patterns
---

# Rust Web Development with Axum & SeaORM

Production-ready patterns for building web APIs in Rust using Axum 0.7+, SeaORM 1.x, and the tower ecosystem. Covers router setup, handler functions, extractors (Path, Query, Json, State), middleware composition with tower layers, error handling with `IntoResponse` and `thiserror`, shared state with `Arc`, request validation, CORS, graceful shutdown, nested routers, WebSocket support, multipart uploads, static file serving, SeaORM entity definitions, migrations, CRUD operations, query builders, relations, transactions, SQLx raw queries, JSON serialization with serde, tower-http middleware (compression, tracing, timeout), and authentication middleware patterns.

## Table of Contents

1. [Project Structure & Dependencies](#project-structure--dependencies)
2. [Router Setup & Nested Routers](#router-setup--nested-routers)
3. [Handlers & Extractors](#handlers--extractors)
4. [Error Handling with IntoResponse & thiserror](#error-handling-with-intoresponse--thiserror)
5. [Shared State with Arc](#shared-state-with-arc)
6. [Middleware & Tower Layers](#middleware--tower-layers)
7. [Authentication Middleware](#authentication-middleware)
8. [SeaORM Entities & Migrations](#seaorm-entities--migrations)
9. [CRUD Operations & Query Builders](#crud-operations--query-builders)
10. [Relations & Transactions](#relations--transactions)
11. [SQLx Raw Queries](#sqlx-raw-queries)
12. [Request Validation](#request-validation)
13. [WebSocket Support](#websocket-support)
14. [Multipart File Upload](#multipart-file-upload)
15. [Serving Static Files](#serving-static-files)
16. [CORS Configuration & Graceful Shutdown](#cors-configuration--graceful-shutdown)
17. [Best Practices](#best-practices)
18. [Anti-Patterns](#anti-patterns)
19. [Sources & References](#sources--references)

---

## Project Structure & Dependencies

```toml
# Cargo.toml
[package]
name = "my-api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = { version = "0.7", features = ["ws", "multipart"] }
axum-extra = { version = "0.9", features = ["typed-header"] }
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = [
    "cors", "compression-gzip", "trace", "timeout", "fs"
] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sea-orm = { version = "1", features = [
    "sqlx-postgres", "runtime-tokio-rustls", "macros"
] }
sea-orm-migration = "1"
sqlx = { version = "0.8", features = ["runtime-tokio", "postgres"] }
thiserror = "2"
validator = { version = "0.19", features = ["derive"] }
jsonwebtoken = "9"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
```

Typical project layout:

```
src/
  main.rs
  lib.rs
  routes/
    mod.rs
    users.rs
    posts.rs
  handlers/
    mod.rs
    users.rs
    posts.rs
  models/           # SeaORM entities
    mod.rs
    user.rs
    post.rs
  migration/
    mod.rs
    m20240101_000001_create_users.rs
  middleware/
    mod.rs
    auth.rs
  errors.rs
  state.rs
  validation.rs
```

---

## Router Setup & Nested Routers

```rust
use axum::{
    Router,
    routing::{get, post, put, delete},
};
use tower_http::cors::CorsLayer;
use tower_http::compression::CompressionLayer;
use tower_http::trace::TraceLayer;

pub fn create_router(state: AppState) -> Router {
    let api_v1 = Router::new()
        .nest("/users", user_routes())
        .nest("/posts", post_routes())
        .nest("/admin", admin_routes());

    Router::new()
        .nest("/api/v1", api_v1)
        .nest("/ws", websocket_routes())
        .fallback(handler_404)
        .layer(CompressionLayer::new())
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state)
}

fn user_routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_users).post(create_user))
        .route("/{id}", get(get_user).put(update_user).delete(delete_user))
}

fn post_routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_posts).post(create_post))
        .route("/{id}", get(get_post).put(update_post).delete(delete_post))
        .route("/{id}/comments", get(list_comments).post(create_comment))
}

fn admin_routes() -> Router<AppState> {
    Router::new()
        .route("/stats", get(admin_stats))
        .route_layer(axum::middleware::from_fn(require_admin))
}

async fn handler_404() -> impl axum::response::IntoResponse {
    (
        axum::http::StatusCode::NOT_FOUND,
        axum::Json(serde_json::json!({ "error": "Not found" })),
    )
}
```

---

## Handlers & Extractors

Axum 0.7 extractors consume the request. Order matters: `State`, `Path`, `Query` implement `FromRequestParts` (can appear in any order before body extractors), while `Json` and `Multipart` implement `FromRequest` (must be last).

```rust
use axum::{
    extract::{Path, Query, State, Json},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Deserialize)]
pub struct Pagination {
    #[serde(default = "default_page")]
    pub page: u64,
    #[serde(default = "default_per_page")]
    pub per_page: u64,
}

fn default_page() -> u64 { 1 }
fn default_per_page() -> u64 { 20 }

#[derive(Serialize)]
pub struct UserResponse {
    pub id: Uuid,
    pub email: String,
    pub name: String,
}

#[derive(Serialize)]
pub struct PaginatedResponse<T: Serialize> {
    pub data: Vec<T>,
    pub meta: PaginationMeta,
}

#[derive(Serialize)]
pub struct PaginationMeta {
    pub page: u64,
    pub per_page: u64,
    pub total: u64,
    pub total_pages: u64,
}

// GET /api/v1/users?page=1&per_page=20
pub async fn list_users(
    State(state): State<AppState>,
    Query(pagination): Query<Pagination>,
) -> Result<Json<PaginatedResponse<UserResponse>>, AppError> {
    let paginator = entity::user::Entity::find()
        .order_by_asc(entity::user::Column::CreatedAt)
        .paginate(&state.db, pagination.per_page);

    let total = paginator.num_items().await?;
    let total_pages = paginator.num_pages().await?;
    let users = paginator
        .fetch_page(pagination.page.saturating_sub(1))
        .await?;

    let data = users
        .into_iter()
        .map(|u| UserResponse {
            id: u.id,
            email: u.email,
            name: u.name,
        })
        .collect();

    Ok(Json(PaginatedResponse {
        data,
        meta: PaginationMeta {
            page: pagination.page,
            per_page: pagination.per_page,
            total,
            total_pages,
        },
    }))
}

// GET /api/v1/users/:id
pub async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<UserResponse>, AppError> {
    let user = entity::user::Entity::find_by_id(id)
        .one(&state.db)
        .await?
        .ok_or(AppError::NotFound("User not found".into()))?;

    Ok(Json(UserResponse {
        id: user.id,
        email: user.email,
        name: user.name,
    }))
}

#[derive(Deserialize)]
pub struct CreateUserRequest {
    pub email: String,
    pub name: String,
    pub password: String,
}

// POST /api/v1/users
pub async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<UserResponse>), AppError> {
    let model = entity::user::ActiveModel {
        id: sea_orm::ActiveValue::Set(Uuid::new_v4()),
        email: sea_orm::ActiveValue::Set(payload.email),
        name: sea_orm::ActiveValue::Set(payload.name),
        password_hash: sea_orm::ActiveValue::Set(hash_password(&payload.password)?),
        created_at: sea_orm::ActiveValue::Set(chrono::Utc::now().naive_utc()),
        updated_at: sea_orm::ActiveValue::Set(chrono::Utc::now().naive_utc()),
    };

    let user = model.insert(&state.db).await?;

    Ok((
        StatusCode::CREATED,
        Json(UserResponse {
            id: user.id,
            email: user.email,
            name: user.name,
        }),
    ))
}
```

---

## Error Handling with IntoResponse & thiserror

```rust
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Forbidden: {0}")]
    Forbidden(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Database error: {0}")]
    Database(#[from] sea_orm::DbErr),

    #[error("SQLx error: {0}")]
    Sqlx(#[from] sqlx::Error),

    #[error("JWT error: {0}")]
    Jwt(#[from] jsonwebtoken::errors::Error),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::Validation(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::Unauthorized(msg) => (StatusCode::UNAUTHORIZED, msg.clone()),
            AppError::Forbidden(msg) => (StatusCode::FORBIDDEN, msg.clone()),
            AppError::Conflict(msg) => (StatusCode::CONFLICT, msg.clone()),
            AppError::Database(err) => {
                tracing::error!("Database error: {:?}", err);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".into())
            }
            AppError::Sqlx(err) => {
                tracing::error!("SQLx error: {:?}", err);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".into())
            }
            AppError::Jwt(_) => (StatusCode::UNAUTHORIZED, "Invalid token".into()),
            AppError::Internal(msg) => {
                tracing::error!("Internal error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".into())
            }
        };

        let body = serde_json::json!({
            "error": {
                "status": status.as_u16(),
                "message": message,
            }
        });

        (status, Json(body)).into_response()
    }
}
```

---

## Shared State with Arc

```rust
use sea_orm::DatabaseConnection;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub jwt_secret: String,
    pub config: Arc<AppConfig>,
}

pub struct AppConfig {
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_expiry_hours: u64,
    pub upload_dir: String,
    pub max_upload_size: usize,
    pub cors_origins: Vec<String>,
}

impl AppConfig {
    pub fn from_env() -> Result<Self, std::env::VarError> {
        Ok(Self {
            database_url: std::env::var("DATABASE_URL")?,
            jwt_secret: std::env::var("JWT_SECRET")?,
            jwt_expiry_hours: std::env::var("JWT_EXPIRY_HOURS")
                .unwrap_or_else(|_| "24".into())
                .parse()
                .unwrap_or(24),
            upload_dir: std::env::var("UPLOAD_DIR")
                .unwrap_or_else(|_| "./uploads".into()),
            max_upload_size: std::env::var("MAX_UPLOAD_SIZE")
                .unwrap_or_else(|_| "10485760".into())
                .parse()
                .unwrap_or(10 * 1024 * 1024),
            cors_origins: std::env::var("CORS_ORIGINS")
                .unwrap_or_else(|_| "http://localhost:3000".into())
                .split(',')
                .map(String::from)
                .collect(),
        })
    }
}

pub async fn build_state() -> Result<AppState, Box<dyn std::error::Error>> {
    let config = AppConfig::from_env()?;
    let db = sea_orm::Database::connect(&config.database_url).await?;

    Ok(AppState {
        db,
        jwt_secret: config.jwt_secret.clone(),
        config: Arc::new(config),
    })
}
```

---

## Middleware & Tower Layers

```rust
use axum::{
    Router,
    middleware::{self, Next},
    extract::Request,
    response::Response,
    http::header,
};
use tower_http::{
    cors::{CorsLayer, Any},
    compression::CompressionLayer,
    trace::TraceLayer,
    timeout::TimeoutLayer,
};
use std::time::Duration;

pub fn apply_middleware(router: Router<AppState>) -> Router<AppState> {
    router
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &axum::http::Request<_>| {
                    tracing::info_span!(
                        "http_request",
                        method = %request.method(),
                        uri = %request.uri(),
                        version = ?request.version(),
                    )
                })
                .on_response(
                    |response: &axum::http::Response<_>,
                     latency: Duration,
                     _span: &tracing::Span| {
                        tracing::info!(
                            status = response.status().as_u16(),
                            latency_ms = latency.as_millis(),
                            "response"
                        );
                    },
                ),
        )
        .layer(CompressionLayer::new())
        .layer(TimeoutLayer::new(Duration::from_secs(30)))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(vec![
                    header::CONTENT_TYPE,
                    header::AUTHORIZATION,
                    header::ACCEPT,
                ])
                .max_age(Duration::from_secs(3600)),
        )
}

// Custom request-timing middleware
pub async fn timing_middleware(request: Request, next: Next) -> Response {
    let start = std::time::Instant::now();
    let method = request.method().clone();
    let uri = request.uri().clone();

    let response = next.run(request).await;

    let elapsed = start.elapsed();
    tracing::info!(
        method = %method,
        uri = %uri,
        elapsed_ms = elapsed.as_millis(),
        status = response.status().as_u16(),
        "request completed"
    );

    response
}

// Usage: .layer(middleware::from_fn(timing_middleware))
```

---

## Authentication Middleware

```rust
use axum::{
    extract::{Request, State},
    http::{self, StatusCode},
    middleware::Next,
    response::Response,
    Json,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use chrono::{Utc, Duration};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: Uuid,        // user id
    pub email: String,
    pub role: String,
    pub exp: usize,       // expiry timestamp
    pub iat: usize,       // issued at
}

pub fn create_token(
    user_id: Uuid,
    email: &str,
    role: &str,
    secret: &str,
    expiry_hours: u64,
) -> Result<String, jsonwebtoken::errors::Error> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        email: email.to_string(),
        role: role.to_string(),
        exp: (now + Duration::hours(expiry_hours as i64)).timestamp() as usize,
        iat: now.timestamp() as usize,
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
}

pub fn verify_token(token: &str, secret: &str) -> Result<Claims, AppError> {
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|e| AppError::Unauthorized(format!("Invalid token: {}", e)))?;

    Ok(token_data.claims)
}

// Middleware function for protected routes
pub async fn require_auth(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = request
        .headers()
        .get(http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| AppError::Unauthorized("Missing authorization header".into()))?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or_else(|| AppError::Unauthorized("Invalid authorization format".into()))?;

    let claims = verify_token(token, &state.jwt_secret)?;

    // Insert claims into request extensions for downstream handlers
    request.extensions_mut().insert(claims);

    Ok(next.run(request).await)
}

// Admin-only middleware
pub async fn require_admin(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let claims = request
        .extensions()
        .get::<Claims>()
        .ok_or_else(|| AppError::Unauthorized("Not authenticated".into()))?;

    if claims.role != "admin" {
        return Err(AppError::Forbidden("Admin access required".into()));
    }

    Ok(next.run(request).await)
}

// Extract claims in handler
pub async fn get_current_user(
    State(state): State<AppState>,
    axum::Extension(claims): axum::Extension<Claims>,
) -> Result<Json<UserResponse>, AppError> {
    let user = entity::user::Entity::find_by_id(claims.sub)
        .one(&state.db)
        .await?
        .ok_or(AppError::NotFound("User not found".into()))?;

    Ok(Json(UserResponse {
        id: user.id,
        email: user.email,
        name: user.name,
    }))
}

// Wire into the router
fn protected_routes() -> Router<AppState> {
    Router::new()
        .route("/me", get(get_current_user))
        .route_layer(middleware::from_fn_with_state(
            app_state.clone(),
            require_auth,
        ))
}
```

---

## SeaORM Entities & Migrations

### Entity Definition

```rust
// src/models/user.rs
use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "users")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    #[sea_orm(unique)]
    pub email: String,
    pub name: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub role: String,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::post::Entity")]
    Posts,
}

impl Related<super::post::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Posts.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}

// src/models/post.rs
use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "posts")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    pub title: String,
    #[sea_orm(column_type = "Text")]
    pub body: String,
    pub published: bool,
    pub author_id: Uuid,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::user::Entity",
        from = "Column::AuthorId",
        to = "super::user::Column::Id"
    )]
    Author,
    #[sea_orm(has_many = "super::comment::Entity")]
    Comments,
}

impl Related<super::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Author.def()
    }
}

impl Related<super::comment::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Comments.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
```

### Migration

```rust
// migration/src/m20240101_000001_create_users.rs
use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Users::Table)
                    .if_not_exists()
                    .col(uuid(Users::Id).primary_key())
                    .col(string_uniq(Users::Email))
                    .col(string(Users::Name))
                    .col(string(Users::PasswordHash))
                    .col(string(Users::Role).default("user"))
                    .col(
                        timestamp(Users::CreatedAt)
                            .default(Expr::current_timestamp()),
                    )
                    .col(
                        timestamp(Users::UpdatedAt)
                            .default(Expr::current_timestamp()),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_users_email")
                    .table(Users::Table)
                    .col(Users::Email)
                    .unique()
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Users::Table).to_owned())
            .await
    }
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
    Email,
    Name,
    PasswordHash,
    Role,
    CreatedAt,
    UpdatedAt,
}
```

---

## CRUD Operations & Query Builders

```rust
use sea_orm::*;
use uuid::Uuid;

// CREATE
pub async fn create_post(
    db: &DatabaseConnection,
    author_id: Uuid,
    title: String,
    body: String,
) -> Result<post::Model, DbErr> {
    let model = post::ActiveModel {
        id: ActiveValue::Set(Uuid::new_v4()),
        title: ActiveValue::Set(title),
        body: ActiveValue::Set(body),
        published: ActiveValue::Set(false),
        author_id: ActiveValue::Set(author_id),
        created_at: ActiveValue::Set(chrono::Utc::now().naive_utc()),
        updated_at: ActiveValue::Set(chrono::Utc::now().naive_utc()),
    };

    model.insert(db).await
}

// READ with filters
pub async fn find_posts(
    db: &DatabaseConnection,
    author_id: Option<Uuid>,
    published_only: bool,
    search: Option<&str>,
    page: u64,
    per_page: u64,
) -> Result<(Vec<post::Model>, u64), DbErr> {
    let mut query = post::Entity::find();

    if let Some(aid) = author_id {
        query = query.filter(post::Column::AuthorId.eq(aid));
    }

    if published_only {
        query = query.filter(post::Column::Published.eq(true));
    }

    if let Some(term) = search {
        query = query.filter(
            Condition::any()
                .add(post::Column::Title.contains(term))
                .add(post::Column::Body.contains(term)),
        );
    }

    let paginator = query
        .order_by_desc(post::Column::CreatedAt)
        .paginate(db, per_page);

    let total = paginator.num_items().await?;
    let posts = paginator.fetch_page(page.saturating_sub(1)).await?;

    Ok((posts, total))
}

// UPDATE
pub async fn update_post(
    db: &DatabaseConnection,
    id: Uuid,
    title: Option<String>,
    body: Option<String>,
    published: Option<bool>,
) -> Result<post::Model, AppError> {
    let post = post::Entity::find_by_id(id)
        .one(db)
        .await?
        .ok_or(AppError::NotFound("Post not found".into()))?;

    let mut active: post::ActiveModel = post.into();

    if let Some(title) = title {
        active.title = ActiveValue::Set(title);
    }
    if let Some(body) = body {
        active.body = ActiveValue::Set(body);
    }
    if let Some(published) = published {
        active.published = ActiveValue::Set(published);
    }
    active.updated_at = ActiveValue::Set(chrono::Utc::now().naive_utc());

    active.update(db).await.map_err(AppError::from)
}

// DELETE
pub async fn delete_post(
    db: &DatabaseConnection,
    id: Uuid,
) -> Result<(), AppError> {
    let result = post::Entity::delete_by_id(id).exec(db).await?;

    if result.rows_affected == 0 {
        return Err(AppError::NotFound("Post not found".into()));
    }

    Ok(())
}

// Batch operations
pub async fn publish_posts(
    db: &DatabaseConnection,
    ids: Vec<Uuid>,
) -> Result<u64, DbErr> {
    let result = post::Entity::update_many()
        .col_expr(post::Column::Published, Expr::value(true))
        .col_expr(
            post::Column::UpdatedAt,
            Expr::value(chrono::Utc::now().naive_utc()),
        )
        .filter(post::Column::Id.is_in(ids))
        .exec(db)
        .await?;

    Ok(result.rows_affected)
}
```

---

## Relations & Transactions

```rust
use sea_orm::*;

// Eager loading (find related)
pub async fn get_post_with_author(
    db: &DatabaseConnection,
    post_id: Uuid,
) -> Result<(post::Model, Option<user::Model>), DbErr> {
    let post = post::Entity::find_by_id(post_id)
        .one(db)
        .await?
        .ok_or(DbErr::RecordNotFound("Post not found".into()))?;

    let author = post.find_related(user::Entity).one(db).await?;

    Ok((post, author))
}

// Load all posts with their authors in one query
pub async fn get_posts_with_authors(
    db: &DatabaseConnection,
) -> Result<Vec<(post::Model, Option<user::Model>)>, DbErr> {
    post::Entity::find()
        .find_also_related(user::Entity)
        .order_by_desc(post::Column::CreatedAt)
        .all(db)
        .await
}

// Transaction: create user with initial post atomically
pub async fn create_user_with_post(
    db: &DatabaseConnection,
    email: String,
    name: String,
    password_hash: String,
    post_title: String,
    post_body: String,
) -> Result<(user::Model, post::Model), AppError> {
    let txn = db.begin().await?;

    let user_id = Uuid::new_v4();
    let now = chrono::Utc::now().naive_utc();

    let user = user::ActiveModel {
        id: ActiveValue::Set(user_id),
        email: ActiveValue::Set(email),
        name: ActiveValue::Set(name),
        password_hash: ActiveValue::Set(password_hash),
        role: ActiveValue::Set("user".into()),
        created_at: ActiveValue::Set(now),
        updated_at: ActiveValue::Set(now),
    }
    .insert(&txn)
    .await?;

    let post = post::ActiveModel {
        id: ActiveValue::Set(Uuid::new_v4()),
        title: ActiveValue::Set(post_title),
        body: ActiveValue::Set(post_body),
        published: ActiveValue::Set(false),
        author_id: ActiveValue::Set(user_id),
        created_at: ActiveValue::Set(now),
        updated_at: ActiveValue::Set(now),
    }
    .insert(&txn)
    .await?;

    txn.commit().await?;

    Ok((user, post))
}

// Nested transaction with savepoints
pub async fn transfer_posts(
    db: &DatabaseConnection,
    from_user_id: Uuid,
    to_user_id: Uuid,
) -> Result<u64, AppError> {
    let txn = db.begin().await?;

    // Verify both users exist
    let _from = user::Entity::find_by_id(from_user_id)
        .one(&txn)
        .await?
        .ok_or(AppError::NotFound("Source user not found".into()))?;

    let _to = user::Entity::find_by_id(to_user_id)
        .one(&txn)
        .await?
        .ok_or(AppError::NotFound("Target user not found".into()))?;

    let result = post::Entity::update_many()
        .col_expr(post::Column::AuthorId, Expr::value(to_user_id))
        .col_expr(
            post::Column::UpdatedAt,
            Expr::value(chrono::Utc::now().naive_utc()),
        )
        .filter(post::Column::AuthorId.eq(from_user_id))
        .exec(&txn)
        .await?;

    txn.commit().await?;

    Ok(result.rows_affected)
}
```

---

## SQLx Raw Queries

Use SQLx directly when SeaORM's query builder is insufficient for complex queries, aggregations, or database-specific features.

```rust
use sea_orm::{DatabaseConnection, FromQueryResult, Statement, DatabaseBackend};
use sqlx::Row;

// Using SeaORM's raw query interface
#[derive(Debug, FromQueryResult)]
pub struct PostStats {
    pub author_id: Uuid,
    pub author_name: String,
    pub total_posts: i64,
    pub published_posts: i64,
    pub avg_body_length: f64,
}

pub async fn get_author_stats(
    db: &DatabaseConnection,
) -> Result<Vec<PostStats>, DbErr> {
    PostStats::find_by_statement(Statement::from_sql_and_values(
        DatabaseBackend::Postgres,
        r#"
        SELECT
            u.id AS author_id,
            u.name AS author_name,
            COUNT(p.id) AS total_posts,
            COUNT(p.id) FILTER (WHERE p.published = true) AS published_posts,
            COALESCE(AVG(LENGTH(p.body)), 0) AS avg_body_length
        FROM users u
        LEFT JOIN posts p ON p.author_id = u.id
        GROUP BY u.id, u.name
        ORDER BY total_posts DESC
        "#,
        [],
    ))
    .all(db)
    .await
}

// Using SQLx pool directly for advanced queries
pub async fn full_text_search(
    pool: &sqlx::PgPool,
    query: &str,
    limit: i64,
) -> Result<Vec<SearchResult>, sqlx::Error> {
    sqlx::query_as!(
        SearchResult,
        r#"
        SELECT
            p.id,
            p.title,
            ts_headline('english', p.body, plainto_tsquery('english', $1)) AS snippet,
            ts_rank(
                to_tsvector('english', p.title || ' ' || p.body),
                plainto_tsquery('english', $1)
            ) AS rank
        FROM posts p
        WHERE to_tsvector('english', p.title || ' ' || p.body)
            @@ plainto_tsquery('english', $1)
            AND p.published = true
        ORDER BY rank DESC
        LIMIT $2
        "#,
        query,
        limit,
    )
    .fetch_all(pool)
    .await
}
```

---

## Request Validation

```rust
use axum::{
    async_trait,
    extract::{rejection::JsonRejection, FromRequest, Request},
    http::StatusCode,
    Json,
};
use serde::de::DeserializeOwned;
use validator::Validate;

// Validated JSON extractor
pub struct ValidatedJson<T>(pub T);

#[async_trait]
impl<S, T> FromRequest<S> for ValidatedJson<T>
where
    T: DeserializeOwned + Validate,
    S: Send + Sync,
    Json<T>: FromRequest<S, Rejection = JsonRejection>,
{
    type Rejection = AppError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let Json(value) = Json::<T>::from_request(req, state)
            .await
            .map_err(|e| AppError::Validation(e.to_string()))?;

        value
            .validate()
            .map_err(|e| AppError::Validation(format_validation_errors(&e)))?;

        Ok(ValidatedJson(value))
    }
}

fn format_validation_errors(errors: &validator::ValidationErrors) -> String {
    errors
        .field_errors()
        .iter()
        .map(|(field, errs)| {
            let messages: Vec<String> = errs
                .iter()
                .map(|e| {
                    e.message
                        .as_ref()
                        .map(|m| m.to_string())
                        .unwrap_or_else(|| format!("{} is invalid", field))
                })
                .collect();
            format!("{}: {}", field, messages.join(", "))
        })
        .collect::<Vec<_>>()
        .join("; ")
}

// Request structs with validation
#[derive(Deserialize, Validate)]
pub struct CreatePostRequest {
    #[validate(length(min = 1, max = 200, message = "Title must be 1-200 characters"))]
    pub title: String,

    #[validate(length(min = 1, message = "Body cannot be empty"))]
    pub body: String,

    #[validate(email(message = "Invalid email format"))]
    pub notify_email: Option<String>,
}

#[derive(Deserialize, Validate)]
pub struct UpdateUserRequest {
    #[validate(length(min = 1, max = 100, message = "Name must be 1-100 characters"))]
    pub name: Option<String>,

    #[validate(email(message = "Invalid email format"))]
    pub email: Option<String>,
}

// Handler using validated extractor
pub async fn create_post_handler(
    State(state): State<AppState>,
    axum::Extension(claims): axum::Extension<Claims>,
    ValidatedJson(payload): ValidatedJson<CreatePostRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), AppError> {
    let post = create_post(&state.db, claims.sub, payload.title, payload.body).await?;

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({
            "id": post.id,
            "title": post.title,
            "published": post.published,
        })),
    ))
}
```

---

## WebSocket Support

```rust
use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::broadcast;

#[derive(Clone)]
pub struct WsState {
    pub tx: broadcast::Sender<String>,
}

pub fn websocket_routes() -> Router<AppState> {
    Router::new()
        .route("/chat", get(ws_handler))
}

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();

    let mut rx = state.ws.tx.subscribe();

    // Spawn task to forward broadcast messages to this client
    let mut send_task = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if sender.send(Message::Text(msg.into())).await.is_err() {
                break;
            }
        }
    });

    // Receive messages from client and broadcast
    let tx = state.ws.tx.clone();
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Text(text) => {
                    let _ = tx.send(text.to_string());
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    // If either task completes, abort the other
    tokio::select! {
        _ = &mut send_task => recv_task.abort(),
        _ = &mut recv_task => send_task.abort(),
    }
}
```

---

## Multipart File Upload

```rust
use axum::{
    extract::{Multipart, State},
    http::StatusCode,
    Json,
};
use tokio::fs;
use uuid::Uuid;
use std::path::PathBuf;

pub async fn upload_file(
    State(state): State<AppState>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, AppError> {
    let upload_dir = &state.config.upload_dir;
    fs::create_dir_all(upload_dir).await.map_err(|e| {
        AppError::Internal(format!("Failed to create upload dir: {}", e))
    })?;

    let mut uploaded_files = Vec::new();

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::Validation(format!("Multipart error: {}", e)))?
    {
        let file_name = field
            .file_name()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "unknown".to_string());

        let content_type = field
            .content_type()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "application/octet-stream".to_string());

        // Validate content type
        let allowed = ["image/png", "image/jpeg", "image/webp", "application/pdf"];
        if !allowed.contains(&content_type.as_str()) {
            return Err(AppError::Validation(format!(
                "File type '{}' not allowed",
                content_type
            )));
        }

        let data = field
            .bytes()
            .await
            .map_err(|e| AppError::Validation(format!("Failed to read field: {}", e)))?;

        // Check file size
        if data.len() > state.config.max_upload_size {
            return Err(AppError::Validation("File too large".into()));
        }

        let extension = PathBuf::from(&file_name)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("bin")
            .to_string();

        let stored_name = format!("{}.{}", Uuid::new_v4(), extension);
        let path = PathBuf::from(upload_dir).join(&stored_name);

        fs::write(&path, &data).await.map_err(|e| {
            AppError::Internal(format!("Failed to write file: {}", e))
        })?;

        uploaded_files.push(serde_json::json!({
            "original_name": file_name,
            "stored_name": stored_name,
            "content_type": content_type,
            "size": data.len(),
        }));
    }

    Ok(Json(serde_json::json!({
        "files": uploaded_files,
    })))
}
```

---

## Serving Static Files

```rust
use tower_http::services::{ServeDir, ServeFile};
use axum::Router;

pub fn static_routes() -> Router {
    Router::new()
        // Serve a single file at the root
        .route_service("/", ServeFile::new("static/index.html"))
        // Serve a directory of static assets
        .nest_service("/assets", ServeDir::new("static/assets"))
        // Serve uploaded files
        .nest_service("/uploads", ServeDir::new("uploads"))
        // Serve with a fallback for SPA
        .fallback_service(
            ServeDir::new("static")
                .not_found_service(ServeFile::new("static/index.html")),
        )
}
```

---

## CORS Configuration & Graceful Shutdown

```rust
use axum::http::{header, HeaderValue, Method};
use tower_http::cors::CorsLayer;
use tokio::signal;

pub fn cors_layer(origins: &[String]) -> CorsLayer {
    let origins: Vec<HeaderValue> = origins
        .iter()
        .filter_map(|o| o.parse().ok())
        .collect();

    CorsLayer::new()
        .allow_origin(origins)
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::PATCH,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([
            header::CONTENT_TYPE,
            header::AUTHORIZATION,
            header::ACCEPT,
            header::ORIGIN,
        ])
        .allow_credentials(true)
        .max_age(std::time::Duration::from_secs(3600))
}

// main.rs with graceful shutdown
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "my_api=debug,tower_http=debug".into()),
        )
        .init();

    let state = build_state().await?;
    let app = create_router(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await?;
    tracing::info!("Listening on {}", listener.local_addr()?);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    tracing::info!("Server shut down gracefully");
    Ok(())
}

async fn shutdown_signal() {
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
        _ = ctrl_c => tracing::info!("Received Ctrl+C"),
        _ = terminate => tracing::info!("Received SIGTERM"),
    }
}
```

---

## Best Practices

1. **Use `thiserror` for library errors and implement `IntoResponse`** -- centralize error-to-HTTP mapping in one place; never leak internal details in responses.
2. **Keep handlers thin** -- handlers should parse input, call a service/repository function, and return a response. Business logic belongs in dedicated modules.
3. **Clone `AppState` cheaply** -- `DatabaseConnection` is already an `Arc<Pool>`. Wrapping additional config in `Arc` avoids expensive clones on every request.
4. **Order extractors correctly** -- `FromRequestParts` extractors (State, Path, Query, headers) can appear in any order, but `FromRequest` extractors (Json, Multipart) must be the last parameter.
5. **Validate at the boundary** -- use a custom `ValidatedJson` extractor with the `validator` crate so invalid payloads are rejected before reaching business logic.
6. **Use transactions for multi-step mutations** -- SeaORM's `db.begin()` returns a transaction that auto-rolls back on drop if not committed.
7. **Layer middleware from outermost to innermost** -- layers applied later wrap earlier ones. Tracing should be outermost, auth should be close to routes.
8. **Prefer typed extractors over manual header parsing** -- `axum_extra::TypedHeader` and custom `FromRequestParts` implementations are safer and more testable.
9. **Use `tower_http::TimeoutLayer` for request timeouts** -- prevents slow clients or long queries from exhausting server resources.
10. **Run migrations in CI and startup** -- use `sea-orm-migration` programmatically or via CLI to keep schemas in sync across environments.
11. **Enable tracing from day one** -- `tower_http::TraceLayer` combined with `tracing-subscriber` gives structured, filterable request logs with zero custom code.
12. **Use connection pooling settings** -- configure `sqlx::pool::PoolOptions` with `max_connections`, `min_connections`, and `acquire_timeout` appropriate for your deployment.

---

## Anti-Patterns

1. **Leaking database errors to clients** -- returning `DbErr` directly in JSON exposes schema details. Always map to generic messages in `IntoResponse`.
2. **Storing secrets in `AppState` as plain `String` without `Arc`** -- causes unnecessary cloning of sensitive data on every request. Wrap in `Arc` or use a secrets manager.
3. **Blocking the async runtime with synchronous code** -- CPU-heavy work (password hashing, image processing) must use `tokio::task::spawn_blocking`. Never call `std::thread::sleep` or run heavy computations directly in handlers.
4. **Using `.unwrap()` in handlers** -- panics crash the request. Always propagate errors with `?` and let the `IntoResponse` implementation produce a proper HTTP response.
5. **Ignoring extractor ordering** -- placing `Json<T>` before `Path<Uuid>` compiles but consumes the body, making the path extractor fail at runtime. Body extractors must always be last.
6. **Creating a new database pool per request** -- `Database::connect` opens a new pool. Create it once at startup and share via `AppState`.
7. **Not setting request body limits** -- axum defaults to 2 MB. For file uploads, configure `axum::extract::DefaultBodyLimit::max()` explicitly; for regular APIs, keep the default or lower it.
8. **Using `String` for IDs in entities** -- prefer `Uuid` or typed newtypes. String IDs invite format inconsistencies and injection vectors.
9. **Mixing raw SQL and ORM without clear boundaries** -- pick one approach per repository module. If you need raw SQL, isolate it in clearly-named functions and document why the ORM was insufficient.
10. **Skipping graceful shutdown** -- without `with_graceful_shutdown`, active connections are terminated abruptly on deploy, causing client errors.

---

## Sources & References

- [Axum GitHub Repository & Documentation](https://github.com/tokio-rs/axum)
- [Axum 0.7 Official Examples](https://github.com/tokio-rs/axum/tree/main/examples)
- [SeaORM Documentation](https://www.sea-ql.org/SeaORM/docs/introduction/sea-orm/)
- [SeaORM Cookbook](https://www.sea-ql.org/sea-orm-cookbook/)
- [Tower HTTP Middleware Crate](https://github.com/tower-rs/tower-http)
- [SQLx GitHub Repository](https://github.com/launchbadge/sqlx)
- [Tokio Graceful Shutdown Guide](https://tokio.rs/tokio/topics/shutdown)
- [Validator Crate Documentation](https://docs.rs/validator/latest/validator/)
- [jsonwebtoken Crate Documentation](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/)
- [Serde Documentation](https://serde.rs/)
