---
name: rails-models
description: ActiveRecord model patterns, associations, validations, callbacks, scopes, and database design for Rails 7/8
---

# Rails Models & ActiveRecord Patterns

Production-ready model patterns for Rails 7/8 applications. Covers ActiveRecord conventions, associations, validations, callbacks, scopes, concerns, and database design.

## Table of Contents

1. [Project Structure & Model Organization](#project-structure--model-organization)
2. [Complete Model Structure](#complete-model-structure)
3. [Associations](#associations)
4. [Validations](#validations)
5. [Callbacks](#callbacks)
6. [Scopes & Queries](#scopes--queries)
7. [Concerns (Mixins)](#concerns-mixins)
8. [Enums](#enums)
9. [Single Table Inheritance & Polymorphism](#single-table-inheritance--polymorphism)
10. [Database Migrations](#database-migrations)
11. [PostgreSQL-Specific Features](#postgresql-specific-features)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)

---

## Project Structure & Model Organization

```
app/
├── models/
│   ├── application_record.rb    # Base class for all models
│   ├── concerns/                # Shared model mixins
│   │   ├── publishable.rb
│   │   ├── searchable.rb
│   │   └── multi_tenant.rb
│   ├── queries/                 # Query objects for complex SQL
│   │   └── posts_query.rb
│   ├── user.rb
│   ├── post.rb
│   └── comment.rb
```

**Modern Rails Stack (2025-2026):**
- **ORM:** ActiveRecord (built-in)
- **Authentication:** Built-in Rails 8 generator or Devise
- **Encryption:** ActiveRecord Encryption (Rails 7+)
- **Background Jobs:** Solid Queue (Rails 8 default) or Sidekiq
- **Caching:** Solid Cache (replaces Redis for caching)

---

## Complete Model Structure

Follow this canonical ordering for model internals:

```ruby
# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  email                  :string           not null
#  encrypted_password     :string           not null
#  name                   :string
#  role                   :string           default("viewer"), not null
#  active                 :boolean          default(TRUE), not null
#  last_sign_in_at        :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
#  index_users_on_role   (role)
#

class User < ApplicationRecord
  # == Constants ===========================================================
  ROLES = %w[admin editor viewer].freeze
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\z/

  # == Extensions ==========================================================
  has_secure_password

  # == Attributes ==========================================================
  attribute :preferences, :json, default: {}

  # Encrypted attributes (Rails 7+)
  encrypts :ssn, deterministic: true
  encrypts :notes

  # == Associations ========================================================
  belongs_to :organization
  has_one :profile, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :nullify
  has_many :authored_posts, class_name: "Post", foreign_key: :author_id

  # Eager loading with strict loading mode
  has_many :tasks, strict_loading: true

  # == Validations =========================================================
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: EMAIL_REGEX }
  validates :name, presence: true, length: { maximum: 100 }
  validates :role, inclusion: { in: ROLES }

  validate :email_domain_allowed, if: :email_changed?

  # == Callbacks ===========================================================
  before_validation :normalize_email
  before_create :set_default_preferences
  after_create_commit :send_welcome_email
  after_update_commit :sync_to_crm, if: :saved_change_to_email?
  after_destroy_commit :cleanup_external_resources

  # == Scopes ==============================================================
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_role, ->(role) { where(role: role) }
  scope :recent, -> { order(created_at: :desc) }
  scope :signed_in_since, ->(date) { where("last_sign_in_at >= ?", date) }
  scope :active_admins, -> { active.by_role("admin") }

  # == Class Methods =======================================================
  class << self
    def search(query)
      where("name ILIKE :q OR email ILIKE :q", q: "%#{query}%")
    end

    def find_by_email_ci(email)
      find_by("LOWER(email) = ?", email.downcase)
    end
  end

  # == Instance Methods ====================================================
  def display_name
    name.presence || email.split("@").first
  end

  def admin?
    role == "admin"
  end

  def can_edit?(resource)
    admin? || resource.author == self
  end

  # == Private Methods =====================================================
  private

  def normalize_email
    self.email = email.to_s.downcase.strip
  end

  def set_default_preferences
    self.preferences = { theme: "light", notifications: true }
  end

  def email_domain_allowed
    domain = email.split("@").last
    unless organization.allowed_domains.include?(domain)
      errors.add(:email, "domain not allowed")
    end
  end

  def send_welcome_email
    UserMailer.welcome(self).deliver_later
  end

  def sync_to_crm
    SyncUserToCrmJob.perform_later(id)
  end

  def cleanup_external_resources
    DeleteUserFromCrmJob.perform_later(id)
  end
end
```

---

## Associations

### Standard Associations

```ruby
class Post < ApplicationRecord
  # Order: belongs_to, has_one, has_many, has_and_belongs_to_many
  belongs_to :author, class_name: "User", foreign_key: :author_id
  belongs_to :category, optional: true

  has_one :featured_image, dependent: :destroy

  has_many :comments, dependent: :destroy
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  # Counter cache
  belongs_to :author, class_name: "User", counter_cache: true
end

# Migration for counter cache
add_column :users, :posts_count, :integer, default: 0, null: false
```

### Polymorphic Associations

```ruby
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"
end

class Post < ApplicationRecord
  has_many :comments, as: :commentable, dependent: :destroy
end

class Video < ApplicationRecord
  has_many :comments, as: :commentable, dependent: :destroy
end

# Migration
create_table :comments do |t|
  t.references :commentable, polymorphic: true, null: false
  t.references :author, null: false, foreign_key: { to_table: :users }
  t.text :body
  t.timestamps
end
```

### Delegations

```ruby
class Post < ApplicationRecord
  belongs_to :author, class_name: "User"

  delegate :name, :email, to: :author, prefix: true, allow_nil: true
  # post.author_name, post.author_email

  delegate :subscription_active?, to: :author, prefix: false
  # post.subscription_active?
end
```

### Self-Referential Associations

```ruby
class Employee < ApplicationRecord
  belongs_to :manager, class_name: "Employee", optional: true
  has_many :direct_reports, class_name: "Employee", foreign_key: :manager_id

  scope :top_level, -> { where(manager_id: nil) }
end
```

---

## Validations

### Built-In Validations

```ruby
class User < ApplicationRecord
  # Presence
  validates :name, presence: true

  # Uniqueness (with scope)
  validates :email, uniqueness: { case_sensitive: false, scope: :organization_id }

  # Format
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Length
  validates :name, length: { minimum: 2, maximum: 100 }
  validates :bio, length: { maximum: 500, too_long: "%{count} characters max" }

  # Numericality
  validates :age, numericality: { greater_than: 0, less_than: 150 }, allow_nil: true

  # Inclusion
  validates :role, inclusion: { in: ROLES }

  # Conditional
  validates :phone, presence: true, if: :requires_phone?
  validates :bio, presence: true, unless: -> { role == "admin" }
end
```

### Custom Validations

```ruby
class Order < ApplicationRecord
  validate :delivery_date_not_in_past
  validate :items_in_stock, on: :create

  private

  def delivery_date_not_in_past
    return if delivery_date.blank?
    if delivery_date < Date.current
      errors.add(:delivery_date, "cannot be in the past")
    end
  end

  def items_in_stock
    order_items.each do |item|
      unless item.product.in_stock?(item.quantity)
        errors.add(:base, "#{item.product.name} is out of stock")
      end
    end
  end
end
```

### Custom Validator Class

```ruby
# app/validators/email_domain_validator.rb
class EmailDomainValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    domain = value.split("@").last
    allowed = options[:domains] || []

    unless allowed.include?(domain)
      record.errors.add(attribute, options[:message] || "domain not allowed")
    end
  end
end

# Usage
class User < ApplicationRecord
  validates :email, email_domain: { domains: %w[company.com partner.com] }
end
```

---

## Callbacks

### Callback Ordering

```ruby
class Post < ApplicationRecord
  # Lifecycle order:
  # before_validation -> after_validation
  # before_save -> around_save
  # before_create/update -> around_create/update -> after_create/update
  # after_save
  # after_commit / after_rollback

  before_validation :generate_slug, on: :create
  before_save :sanitize_content
  before_create :set_published_at, if: :published?
  after_create_commit :notify_subscribers
  after_update_commit :reindex_search, if: :saved_change_to_title?
  after_destroy_commit :remove_from_search_index
end
```

### Safe Callback Patterns

```ruby
class Post < ApplicationRecord
  # Use after_commit for external side effects (email, jobs, webhooks)
  # NOT after_save (which runs inside the transaction)
  after_create_commit :send_notification
  after_update_commit :sync_to_external_service
  after_destroy_commit :cleanup_cdn_assets

  # Use after_save for database-only side effects
  after_save :update_author_post_count

  private

  def send_notification
    NotifyFollowersJob.perform_later(id)
  end

  def sync_to_external_service
    SyncPostJob.perform_later(id)
  end
end
```

---

## Scopes & Queries

### Scope Patterns

```ruby
class Post < ApplicationRecord
  # Always use lambda syntax
  scope :published, -> { where(published: true) }
  scope :draft, -> { where(published: false) }
  scope :by_author, ->(author_id) { where(author_id: author_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :older_than, ->(date) { where("created_at < ?", date) }

  # Composable scopes
  scope :published_recently, -> { published.where("created_at > ?", 1.week.ago) }

  # Scope with eager loading
  scope :with_author, -> { includes(:author) }
  scope :with_comments, -> { includes(:comments) }
end

# Usage
Post.published.recent.with_author.limit(10)
Post.by_author(user.id).published_recently
```

### Query Objects

```ruby
# app/queries/posts_query.rb
class PostsQuery
  def initialize(relation = Post.all)
    @relation = relation
  end

  def filter(params)
    @relation = @relation.published if params[:published]
    @relation = @relation.by_category(params[:category_id]) if params[:category_id]
    @relation = @relation.by_author(params[:author_id]) if params[:author_id]
    self
  end

  def search(query)
    return self if query.blank?
    @relation = @relation.where(
      "title ILIKE :q OR body ILIKE :q", q: "%#{query}%"
    )
    self
  end

  def sort(column, direction = :desc)
    @relation = @relation.order(column => direction)
    self
  end

  def page(number, per: 25)
    @relation = @relation.page(number).per(per)
    self
  end

  def to_relation
    @relation
  end

  alias_method :all, :to_relation
end

# Usage in controller
@posts = PostsQuery.new(current_user.posts)
  .filter(params[:filter])
  .search(params[:q])
  .sort(:created_at, :desc)
  .page(params[:page])
  .all
```

---

## Concerns (Mixins)

```ruby
# app/models/concerns/publishable.rb
module Publishable
  extend ActiveSupport::Concern

  included do
    scope :published, -> { where(published: true) }
    scope :draft, -> { where(published: false) }

    validates :published_at, presence: true, if: :published?
  end

  def publish!
    update!(published: true, published_at: Time.current)
  end

  def unpublish!
    update!(published: false, published_at: nil)
  end

  class_methods do
    def publish_all
      draft.find_each(&:publish!)
    end
  end
end

# app/models/concerns/searchable.rb
module Searchable
  extend ActiveSupport::Concern

  included do
    scope :search_by, ->(query, *fields) {
      return all if query.blank?
      conditions = fields.map { |f| "#{f} ILIKE :q" }.join(" OR ")
      where(conditions, q: "%#{query}%")
    }
  end
end

# Usage
class Post < ApplicationRecord
  include Publishable
  include Searchable
end
```

---

## Enums

```ruby
class Order < ApplicationRecord
  # Use hash syntax for explicit database values (not integers)
  enum status: {
    pending: "pending",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled"
  }, _prefix: true

  enum payment_method: {
    credit_card: "credit_card",
    paypal: "paypal",
    bank_transfer: "bank_transfer"
  }, _suffix: true

  # Rails 7+ enum with validation
  enum :priority, { low: 0, medium: 1, high: 2 }, validate: true
end

# Usage
order.status_pending?
Order.status_shipped
order.status_processing!
```

---

## Single Table Inheritance & Polymorphism

### STI (Use Sparingly)

```ruby
class Vehicle < ApplicationRecord
  # Requires 'type' column in the table
end

class Car < Vehicle
  def drive
    "Driving on roads"
  end
end

class Boat < Vehicle
  def drive
    "Sailing on water"
  end
end

# Queries
Car.all    # SELECT * FROM vehicles WHERE type = 'Car'
Boat.all   # SELECT * FROM vehicles WHERE type = 'Boat'
```

### Delegated Types (Preferred Over STI)

```ruby
# Rails 6.1+ - better than STI for divergent schemas
class Entry < ApplicationRecord
  delegated_type :entryable, types: %w[Message Comment]
end

class Message < ApplicationRecord
  has_one :entry, as: :entryable, touch: true
  validates :subject, presence: true
end

class Comment < ApplicationRecord
  has_one :entry, as: :entryable, touch: true
  validates :body, presence: true
end
```

---

## Database Migrations

### Migration Best Practices

```ruby
# Always make migrations reversible
class AddStatusToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :status, :string, default: "draft", null: false
    add_index :posts, :status
  end
end

# Large table migrations (avoid locking)
class AddIndexConcurrently < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :posts, :author_id, algorithm: :concurrently
  end
end

# Data migrations in separate files
class BackfillUserRole < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    User.where(role: nil).in_batches(of: 1000) do |batch|
      batch.update_all(role: "viewer")
      sleep(0.1)  # Avoid overwhelming database
    end
  end
end

# Strong migrations gem for safety
# Gemfile
gem "strong_migrations"
```

---

## PostgreSQL-Specific Features

```ruby
# JSONB columns
class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :products, :metadata, using: :gin
  end
end

# Query JSONB
Product.where("metadata @> ?", { color: "red" }.to_json)
Product.where("metadata->>'brand' = ?", "Nike")

# Array columns
class AddTagsToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :tags, :string, array: true, default: []
    add_index :posts, :tags, using: :gin
  end
end

# Query arrays
Post.where("? = ANY(tags)", "rails")
Post.where("tags @> ARRAY[?]::varchar[]", "ruby")

# Full-text search
class AddFullTextSearch < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      ALTER TABLE posts
      ADD COLUMN searchable tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))
      ) STORED;
    SQL
    add_index :posts, :searchable, using: :gin
  end
end

Post.where("searchable @@ plainto_tsquery('english', ?)", "rails guide")
```

---

## Best Practices

1. **Keep models focused** - Move complex query logic to query objects, complex validations to form objects, and business logic to service objects
2. **Use `after_commit` for side effects** - Not `after_save`, which runs inside the transaction
3. **Prefer `find_each` for batch processing** - Not `.all.each` which loads everything into memory
4. **Use `exists?` instead of `any?`** - For checking existence without loading records
5. **Always add database indexes** for columns used in `WHERE`, `ORDER BY`, and `JOIN` clauses
6. **Use `strict_loading`** in development to catch N+1 queries early
7. **Annotate models** with `annotate` gem for schema documentation
8. **Use encrypted attributes** (Rails 7+) for sensitive data like SSN, tokens

---

## Anti-Patterns

```ruby
# BAD: Callback for business logic
after_save :send_invoice_and_update_inventory_and_notify_warehouse

# GOOD: Use a service object
# Posts::CreateService.new(params).call

# BAD: Too many callbacks creating hidden side effects
class Order < ApplicationRecord
  after_create :send_confirmation
  after_create :notify_warehouse
  after_create :update_inventory
  after_create :charge_payment
  # Hard to follow, test, and debug
end

# BAD: N+1 in model method
def recent_comments_count
  posts.map { |p| p.comments.count }.sum
end

# GOOD: Use counter cache or single query
def recent_comments_count
  Comment.where(post_id: post_ids).count
end

# BAD: Using default_scope
default_scope { where(active: true) }
# Causes confusion, hard to query inactive records

# GOOD: Use explicit scopes
scope :active, -> { where(active: true) }
```

---

## Sources & References

- [Active Record Associations Guide](https://guides.rubyonrails.org/association_basics.html)
- [Active Record Validations Guide](https://guides.rubyonrails.org/active_record_validations.html)
- [Active Record Callbacks Guide](https://guides.rubyonrails.org/active_record_callbacks.html)
- [Active Record Query Interface Guide](https://guides.rubyonrails.org/active_record_querying.html)
- [Optimize Database Performance in Ruby on Rails and ActiveRecord](https://blog.appsignal.com/2024/10/30/optimize-database-performance-in-ruby-on-rails-and-activerecord.html)
- [Rails Encrypted Attributes](https://guides.rubyonrails.org/active_record_encryption.html)
- [Scaling with PostgreSQL without boiling the ocean](https://www.shayon.dev/post/2025/40/scaling-with-postgresql-without-boiling-the-ocean/)
- [A journey towards better Ruby on Rails testing practices](https://thoughtbot.com/blog/a-journey-towards-better-testing-practices)
