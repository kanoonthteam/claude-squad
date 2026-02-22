---
name: rails-performance
description: Rails performance optimization -- N+1 prevention, caching strategies, background jobs, database tuning, and Kamal deployment
---

# Rails Performance & Deployment

Production-ready performance optimization patterns for Rails 7/8. Covers N+1 prevention, caching (fragment, Russian doll, HTTP), background jobs (Solid Queue/Sidekiq), database indexing and tuning, connection pooling, and Kamal 2 deployment.

## Table of Contents

1. [N+1 Query Prevention](#n1-query-prevention)
2. [Database Indexing](#database-indexing)
3. [Query Optimization](#query-optimization)
4. [Connection Pooling](#connection-pooling)
5. [Low-Level Caching](#low-level-caching)
6. [Fragment Caching](#fragment-caching)
7. [Russian Doll Caching](#russian-doll-caching)
8. [HTTP Caching](#http-caching)
9. [Background Jobs - Solid Queue](#background-jobs---solid-queue)
10. [Background Jobs - Sidekiq](#background-jobs---sidekiq)
11. [Database Views & Partitioning](#database-views--partitioning)
12. [Deployment with Kamal 2](#deployment-with-kamal-2)
13. [Monitoring & Observability](#monitoring--observability)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)

---

## N+1 Query Prevention

### Eager Loading

```ruby
# BAD: N+1 query (1 + N queries)
posts = Post.all
posts.each { |post| puts post.author.name }

# GOOD: Eager loading (2 queries)
posts = Post.includes(:author).all
posts.each { |post| puts post.author.name }

# Multiple and nested associations
posts = Post.includes(:author, :comments, tags: :category).all
posts = Post.includes(comments: :author).all
```

### preload vs eager_load vs includes

```ruby
# preload: Always uses separate queries
posts = Post.preload(:author).all
# SELECT * FROM posts
# SELECT * FROM users WHERE id IN (1, 2, 3...)

# eager_load: Always uses LEFT OUTER JOIN
posts = Post.eager_load(:author).all
# SELECT * FROM posts LEFT OUTER JOIN users ON ...

# includes: Rails decides (preload by default, eager_load if filtering)
posts = Post.includes(:author).all

# Use eager_load when you need to query on the association
posts = Post.eager_load(:author).where(users: { active: true })

# Use preload when you do NOT need to filter on the association
posts = Post.preload(:author).where(published: true)
```

### Strict Loading (Rails 6.1+)

```ruby
class User < ApplicationRecord
  has_many :posts, strict_loading: true
end

user = User.first
user.posts.to_a  # Raises ActiveRecord::StrictLoadingViolationError

# Enable globally in development
# config/environments/development.rb
config.active_record.strict_loading_by_default = true

# Opt-out per query
User.includes(:posts).first.posts.to_a  # OK
```

### Bullet Gem (Development)

```ruby
# Gemfile
group :development do
  gem "bullet"
end

# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.bullet_logger = true
  Bullet.console = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
end
```

---

## Database Indexing

```ruby
class AddIndexesToPosts < ActiveRecord::Migration[8.0]
  def change
    # Single column index
    add_index :posts, :published
    add_index :posts, :author_id

    # Unique index
    add_index :posts, :slug, unique: true

    # Composite index (order matters for queries)
    add_index :posts, [:author_id, :published]

    # Partial index (PostgreSQL)
    add_index :posts, :published_at,
              where: "published = true",
              name: "index_posts_published_at_on_published"

    # Expression index (PostgreSQL)
    add_index :posts, "LOWER(title)", name: "index_posts_on_lower_title"

    # Concurrent index (PostgreSQL, no table locking)
    add_index :posts, :category_id, algorithm: :concurrently
  end
end
```

---

## Query Optimization

```ruby
# Use select to limit columns
posts = Post.select(:id, :title, :published_at).all

# Use pluck for single or multiple columns
author_ids = Post.pluck(:author_id)
data = Post.pluck(:id, :title)

# Use exists? instead of any? or present?
Post.where(published: true).exists?  # Fast query
# NOT: Post.where(published: true).any?  # Loads all records

# Use find_each for batch processing
Post.find_each(batch_size: 1000) do |post|
  post.process!
end

# Use in_batches for batch updates
Post.in_batches(of: 1000) do |batch|
  batch.update_all(processed: true)
end

# Use counter_cache for associations
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
# Add column: add_column :posts, :comments_count, :integer, default: 0, null: false

# Avoid count on large tables (use estimate for PostgreSQL)
total = Post.connection.execute(
  "SELECT reltuples::bigint FROM pg_class WHERE relname = 'posts'"
).first["reltuples"]
```

---

## Connection Pooling

```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
  checkout_timeout: 5
  idle_timeout: 300
  reaping_frequency: 10
```

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY", 2)
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count

# Database pool should be >= threads
# If WEB_CONCURRENCY=2 and RAILS_MAX_THREADS=5
# Minimum pool size: 2 * 5 = 10
```

---

## Low-Level Caching

```ruby
# Simple fetch with expiration
result = Rails.cache.fetch("complex_calculation", expires_in: 1.hour) do
  perform_complex_calculation
end

# Delete
Rails.cache.delete("complex_calculation")

# Multi-fetch
user_ids = [1, 2, 3]
Rails.cache.fetch_multi(*user_ids, namespace: "user_stats", expires_in: 1.hour) do |id|
  calculate_user_stats(id)
end

# Increment/Decrement
Rails.cache.increment("page_views")
Rails.cache.decrement("items_remaining")

# Rate limiting example
def rate_limited?(user_id)
  key = "rate_limit:#{user_id}"
  count = Rails.cache.read(key) || 0
  if count >= 100
    true
  else
    Rails.cache.write(key, count + 1, expires_in: 1.hour)
    false
  end
end
```

---

## Fragment Caching

```erb
<%# Simple fragment cache %>
<% cache @post do %>
  <h1><%= @post.title %></h1>
  <p><%= @post.body %></p>
<% end %>

<%# Cache with custom key %>
<% cache ["v1", @post, current_user.admin?] do %>
  <h1><%= @post.title %></h1>
  <% if current_user.admin? %>
    <%= link_to "Edit", edit_post_path(@post) %>
  <% end %>
<% end %>

<%# Conditional caching %>
<% cache_if @post.published?, @post do %>
  <%= render @post %>
<% end %>

<%# Collection caching %>
<%= render partial: "posts/post", collection: @posts, cached: true %>
```

---

## Russian Doll Caching

```erb
<% cache ["v1", "posts", Post.maximum(:updated_at)] do %>
  <h1>All Posts</h1>
  <% @posts.each do |post| %>
    <% cache ["v1", post] do %>
      <article>
        <h2><%= post.title %></h2>
        <div class="comments">
          <% cache ["v1", post, "comments", post.comments.maximum(:updated_at)] do %>
            <% post.comments.each do |comment| %>
              <% cache ["v1", comment] do %>
                <%= render comment %>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </article>
    <% end %>
  <% end %>
<% end %>
```

**Touch associations for automatic invalidation:**

```ruby
class Comment < ApplicationRecord
  belongs_to :post, touch: true
end

class Post < ApplicationRecord
  belongs_to :author, class_name: "User", touch: true
  has_many :comments
end
# When a comment changes, post.updated_at and author.updated_at update automatically
```

---

## HTTP Caching

```ruby
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])

    # ETag-based caching
    fresh_when(@post)

    # Or with custom options
    fresh_when(etag: @post, last_modified: @post.updated_at, public: true)

    # Stale check with block
    if stale?(@post)
      respond_to do |format|
        format.html
        format.json { render json: @post }
      end
    end
  end

  def public_page
    expires_in 1.hour, public: true
    render :show
  end
end
```

---

## Background Jobs - Solid Queue

```ruby
# config/application.rb (Rails 8 default)
config.active_job.queue_adapter = :solid_queue

# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 5
      processes: 3
    - queues: high_priority
      threads: 10
      processes: 5
      polling_interval: 0.1

# app/jobs/process_video_job.rb
class ProcessVideoJob < ApplicationJob
  queue_as :default

  retry_on NetworkError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(video_id)
    video = Video.find(video_id)
    video.process!
  end
end

# Enqueue
ProcessVideoJob.perform_later(video.id)
ProcessVideoJob.set(wait: 1.hour).perform_later(video.id)
```

---

## Background Jobs - Sidekiq

```ruby
# Gemfile
gem "sidekiq"

# config/application.rb
config.active_job.queue_adapter = :sidekiq

# app/jobs/send_email_job.rb
class SendEmailJob < ApplicationJob
  queue_as :default

  # Idempotency - make jobs safe to retry
  def perform(user_id, email_type)
    user = User.find(user_id)
    return if email_already_sent?(user, email_type)

    UserMailer.send(email_type, user).deliver_now
    mark_email_sent(user, email_type)
  end

  private

  def email_already_sent?(user, email_type)
    user.sent_emails.exists?(email_type: email_type, sent_at: 24.hours.ago..)
  end

  def mark_email_sent(user, email_type)
    user.sent_emails.create!(email_type: email_type, sent_at: Time.current)
  end
end
```

### Job Patterns

```ruby
# Transactional jobs - enqueue after commit
class Post < ApplicationRecord
  after_create_commit -> { NotifyFollowersJob.perform_later(id) }
end

# Batch processing
class BulkImportJob < ApplicationJob
  def perform(import_id)
    import = Import.find(import_id)
    import.data.each_slice(1000) do |batch|
      ProcessBatchJob.perform_later(batch)
    end
  end
end
```

---

## Database Views & Partitioning

```ruby
# Database views for complex queries
class CreateUserStatsView < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      CREATE VIEW user_stats AS
      SELECT users.id, users.email,
        COUNT(DISTINCT posts.id) as posts_count,
        COUNT(DISTINCT comments.id) as comments_count,
        MAX(posts.created_at) as last_post_at
      FROM users
      LEFT JOIN posts ON posts.author_id = users.id
      LEFT JOIN comments ON comments.author_id = users.id
      GROUP BY users.id, users.email;
    SQL
  end

  def down
    execute "DROP VIEW user_stats;"
  end
end

class UserStat < ApplicationRecord
  self.primary_key = "id"
  def readonly?
    true
  end
end

# Advisory locks for exclusive operations
# Gemfile
gem "with_advisory_lock"

class ImportJob < ApplicationJob
  def perform(import_id)
    Import.with_advisory_lock("import_#{import_id}") do
      process_import(import_id)
    end
  end
end
```

---

## Deployment with Kamal 2

```yaml
# config/deploy.yml
service: my-app
image: my-company/my-app

servers:
  web:
    hosts:
      - 192.168.0.1
      - 192.168.0.2
    labels:
      traefik.http.routers.my-app.rule: Host(`myapp.com`)
      traefik.http.routers.my-app.tls.certresolver: letsencrypt

  workers:
    hosts:
      - 192.168.0.3
    cmd: bundle exec solid_queue:start

registry:
  server: registry.digitalocean.com
  username: my-username
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
  secret:
    - RAILS_MASTER_KEY

healthcheck:
  path: /up
  port: 3000
  max_attempts: 10
  interval: 5s
  timeout: 5s
```

### Kamal Commands

```bash
kamal setup         # Initial setup
kamal deploy        # Deploy
kamal rollback [V]  # Rollback
kamal app logs      # View logs
kamal app exec -i bash  # SSH into container
kamal app exec bin/rails console  # Rails console
kamal healthcheck perform  # Check health
```

### Health Check Endpoint

```ruby
class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    checks = {
      database: check_database,
      redis: check_redis,
      storage: check_storage
    }

    status = checks.values.all? ? :ok : :service_unavailable
    render json: { status: status == :ok ? "ok" : "error", checks: checks }, status: status
  end

  private

  def check_database
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue => e
    Rails.logger.error("DB health check failed: #{e.message}")
    false
  end
end
```

---

## Monitoring & Observability

```ruby
# Use ActiveSupport::Notifications
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  duration = finish - start
  Rails.logger.info("Request took #{duration}ms: #{payload[:controller]}##{payload[:action]}")
end

# Custom instrumentation
ActiveSupport::Notifications.instrument("my_app.expensive_operation", data: data) do
  perform_expensive_operation(data)
end

# Recommended gems:
# - rack-mini-profiler (development)
# - bullet (N+1 detection)
# - scout_apm or skylight (production monitoring)
# - lograge (structured logging)
```

---

## Best Practices

1. **Profile before optimizing** - Use rack-mini-profiler, New Relic, or Scout APM
2. **Add indexes for all foreign keys** and columns used in WHERE/ORDER BY
3. **Use `includes` by default** for associations accessed in views
4. **Enable strict_loading in development** to catch N+1 queries
5. **Cache aggressively** - Fragment caching is cheap and effective
6. **Make background jobs idempotent** - Safe to retry without side effects
7. **Use connection pooling** sized to match thread count
8. **Monitor slow queries** with pg_stat_statements

---

## Anti-Patterns

```ruby
# BAD: Loading all records into memory
Post.all.each { |p| p.update(processed: true) }
# GOOD: Batch update
Post.in_batches(of: 1000) { |batch| batch.update_all(processed: true) }

# BAD: After_save for external calls (runs inside transaction)
after_save :call_external_api
# GOOD: After_commit (runs after transaction commits)
after_commit :call_external_api

# BAD: No index on frequently queried column
# GOOD: Always add indexes for foreign keys and search columns

# BAD: Caching without expiration
Rails.cache.write("key", value)
# GOOD: Always set expiration
Rails.cache.write("key", value, expires_in: 1.hour)
```

---

## Sources & References

- [Caching with Rails: An Overview](https://guides.rubyonrails.org/caching_with_rails.html)
- [Russian doll caching in Rails](https://blog.appsignal.com/2018/04/03/russian-doll-caching-in-rails.html)
- [Optimize Database Performance in Ruby on Rails](https://blog.appsignal.com/2024/10/30/optimize-database-performance-in-ruby-on-rails-and-activerecord.html)
- [Understanding Active Record Connection Pooling](https://www.bigbinary.com/blog/understanding-active-record-connection-pooling)
- [Solid Queue in Rails 8: Setup and Production Tuning](https://nsinenko.com/rails/background-jobs/performance/2025/10/07/solid-queue-rails-practical-guide/)
- [Sidekiq Best Practices](https://github.com/sidekiq/sidekiq/wiki/Best-Practices)
- [An Honest Take on Deploying Rails with Kamal](https://www.ivanturkovic.com/2026/02/06/honest-take-kamal-rails-deployment/)
- [Understanding Kamal healthcheck settings](https://nts.strzibny.name/kamal-healthcheck-settings/)
- [Scaling with PostgreSQL without boiling the ocean](https://www.shayon.dev/post/2025/40/scaling-with-postgresql-without-boiling-the-ocean/)
