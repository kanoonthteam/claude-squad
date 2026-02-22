---
name: rails-controllers
description: Rails controller patterns, API design, service objects, form objects, serialization, and architecture patterns
---

# Rails Controllers & Architecture Patterns

Production-ready controller patterns for Rails 7/8 applications. Covers RESTful controllers, API design, Hotwire/Turbo integration, service objects, form objects, decorators, serialization, and authorization.

## Table of Contents

1. [API Controller Pattern](#api-controller-pattern)
2. [Hotwire Controller (Turbo Streams)](#hotwire-controller-turbo-streams)
3. [Controller Concerns](#controller-concerns)
4. [Service Objects](#service-objects)
5. [Form Objects](#form-objects)
6. [Query Objects in Controllers](#query-objects-in-controllers)
7. [Decorators & Presenters](#decorators--presenters)
8. [Serialization (Alba / Blueprinter)](#serialization-alba--blueprinter)
9. [API Versioning & Pagination](#api-versioning--pagination)
10. [Authorization (Pundit)](#authorization-pundit)
11. [Rate Limiting](#rate-limiting)
12. [Error Handling](#error-handling)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)

---

## API Controller Pattern

```ruby
# frozen_string_literal: true

module Api
  module V1
    class PostsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_post, only: %i[show update destroy]
      before_action :authorize_post, only: %i[update destroy]

      def index
        @posts = PostsQuery.new(current_user)
                           .filter(params[:filter])
                           .search(params[:q])
                           .page(params[:page])

        render json: PostSerializer.new(@posts).serialize
      end

      def show
        render json: PostSerializer.new(@post).serialize
      end

      def create
        result = Posts::CreateService.new(
          author: current_user,
          params: post_params
        ).call

        if result.success?
          render json: PostSerializer.new(result.data[:post]).serialize,
                 status: :created,
                 location: api_v1_post_url(result.data[:post])
        else
          render json: { errors: result.errors },
                 status: :unprocessable_entity
        end
      end

      def update
        if @post.update(post_params)
          render json: PostSerializer.new(@post).serialize
        else
          render json: { errors: @post.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        @post.destroy!
        head :no_content
      end

      private

      def set_post
        @post = Post.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Post not found" }, status: :not_found
      end

      def authorize_post
        authorize @post
      end

      def post_params
        params.require(:post).permit(
          :title, :body, :published, :category_id,
          tag_ids: [], metadata: {}
        )
      end
    end
  end
end
```

---

## Hotwire Controller (Turbo Streams)

```ruby
# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post, only: %i[show edit update destroy]

  def index
    @posts = Post.includes(:author).order(created_at: :desc)
  end

  def create
    @post = current_user.posts.build(post_params)

    respond_to do |format|
      if @post.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend("posts", partial: "posts/post", locals: { post: @post }),
            turbo_stream.replace("post_form", partial: "posts/form", locals: { post: Post.new }),
            turbo_stream.append("flash", partial: "shared/flash", locals: { notice: "Post created!" })
          ]
        end
        format.html { redirect_to @post, notice: "Post created!" }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "post_form",
            partial: "posts/form",
            locals: { post: @post }
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @post.update(post_params)
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@post),
            partial: "posts/post",
            locals: { post: @post }
          )
        end
        format.html { redirect_to @post, notice: "Post updated!" }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "edit_post_#{@post.id}",
            partial: "posts/form",
            locals: { post: @post }
          ), status: :unprocessable_entity
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @post.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@post)) }
      format.html { redirect_to posts_url, notice: "Post deleted!" }
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :body, :published)
  end
end
```

---

## Controller Concerns

```ruby
# app/controllers/concerns/api_error_handling.rb
module ApiErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from Pundit::NotAuthorizedError, with: :forbidden
    rescue_from ActionController::ParameterMissing, with: :bad_request
  end

  private

  def not_found(exception)
    render json: {
      error: { type: "not_found", message: exception.message, code: "RESOURCE_NOT_FOUND" }
    }, status: :not_found
  end

  def unprocessable_entity(exception)
    render json: {
      error: {
        type: "validation_error",
        message: "Validation failed",
        details: exception.record&.errors&.messages
      }
    }, status: :unprocessable_entity
  end

  def forbidden(_exception)
    render json: {
      error: { type: "forbidden", message: "Not authorized", code: "FORBIDDEN" }
    }, status: :forbidden
  end

  def bad_request(exception)
    render json: {
      error: { type: "bad_request", message: exception.message, code: "BAD_REQUEST" }
    }, status: :bad_request
  end
end

# Usage
class Api::V1::BaseController < ApplicationController
  include ApiErrorHandling
end
```

---

## Service Objects

Use service objects for complex business logic that spans multiple models or has side effects.

```ruby
# app/services/posts/create_service.rb
module Posts
  class CreateService
    def initialize(author:, params:)
      @author = author
      @params = params
    end

    def call
      ActiveRecord::Base.transaction do
        create_post
        notify_followers
        index_in_search

        Result.success(post: @post)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Post creation failed: #{e.message}")
      Result.failure(errors: ["Failed to create post"])
    end

    private

    def create_post
      @post = @author.posts.create!(@params)
    end

    def notify_followers
      @author.followers.find_each do |follower|
        NotifyFollowerJob.perform_later(follower.id, @post.id)
      end
    end

    def index_in_search
      SearchIndexJob.perform_later(@post.id)
    end
  end
end

# app/services/result.rb
class Result
  attr_reader :data, :errors

  def initialize(success:, data: nil, errors: [])
    @success = success
    @data = data
    @errors = errors
  end

  def self.success(data)
    new(success: true, data: data)
  end

  def self.failure(errors:)
    new(success: false, errors: errors)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
```

---

## Form Objects

```ruby
# app/forms/user_registration_form.rb
class UserRegistrationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :name, :string
  attribute :terms_accepted, :boolean

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }
  validates :password_confirmation, presence: true
  validates :name, presence: true
  validates :terms_accepted, acceptance: true
  validate :passwords_match

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      create_user
      create_profile
      send_welcome_email
      true
    end
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  private

  def create_user
    @user = User.create!(email: email, password: password, name: name)
  end

  def create_profile
    @user.create_profile!(default_attributes)
  end

  def send_welcome_email
    UserMailer.welcome(@user).deliver_later
  end

  def passwords_match
    return if password == password_confirmation
    errors.add(:password_confirmation, "doesn't match password")
  end

  def default_attributes
    { theme: "light", notifications_enabled: true }
  end
end

# Usage in controller
def create
  @form = UserRegistrationForm.new(registration_params)
  if @form.save
    redirect_to root_path, notice: "Welcome!"
  else
    render :new, status: :unprocessable_entity
  end
end
```

---

## Query Objects in Controllers

```ruby
# app/controllers/api/v1/posts_controller.rb
def index
  @posts = PostsQuery.new(current_user.posts)
    .filter(params.fetch(:filter, {}))
    .search(params[:q])
    .sort(params[:sort], params[:direction])
    .page(params[:page])
    .all

  render json: PostSerializer.new(@posts).serialize
end
```

---

## Decorators & Presenters

```ruby
# Gemfile
gem "draper"

# app/decorators/post_decorator.rb
class PostDecorator < Draper::Decorator
  delegate_all

  def formatted_published_at
    return "Draft" unless object.published_at
    object.published_at.strftime("%B %d, %Y")
  end

  def reading_time
    words = object.body.split.size
    minutes = (words / 200.0).ceil
    "#{minutes} min read"
  end

  def author_link
    h.link_to object.author.name, h.user_path(object.author)
  end

  def status_badge
    if object.published?
      h.content_tag(:span, "Published", class: "badge badge-success")
    else
      h.content_tag(:span, "Draft", class: "badge badge-secondary")
    end
  end
end

# Usage
@post = Post.find(params[:id]).decorate
@posts = PostDecorator.decorate_collection(Post.all)
```

---

## Serialization (Alba / Blueprinter)

### Alba

```ruby
# Gemfile
gem "alba"

# app/serializers/post_serializer.rb
class PostSerializer
  include Alba::Resource

  root_key :post, :posts
  attributes :id, :title, :body, :published

  attribute :reading_time do |post|
    (post.body.split.size / 200.0).ceil
  end

  attribute :draft_notes, if: proc { |post, params|
    params[:current_user]&.admin? && !post.published?
  }

  one :author, serializer: UserSerializer
  many :comments, serializer: CommentSerializer

  transform_keys :lower_camel
end

# Usage
render json: PostSerializer.new(@posts).serialize
render json: PostSerializer.new(@posts, params: { current_user: current_user }).serialize
```

### Blueprinter

```ruby
# Gemfile
gem "blueprinter"

# app/blueprints/post_blueprint.rb
class PostBlueprint < Blueprinter::Base
  identifier :id
  fields :title, :body, :published, :created_at

  field :reading_time do |post|
    (post.body.split.size / 200.0).ceil
  end

  association :author, blueprint: UserBlueprint

  view :detailed do
    fields :updated_at
    association :comments, blueprint: CommentBlueprint
  end

  view :admin do
    include_view :detailed
    fields :draft_notes, :internal_score
  end
end

# Usage
PostBlueprint.render(@posts)
PostBlueprint.render(@post, view: :detailed)
```

---

## API Versioning & Pagination

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :posts
      resources :users
    end
  end
end

# Pagination with Pagy
# Gemfile
gem "pagy"

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pagy::Backend
end

# app/controllers/api/v1/posts_controller.rb
def index
  @pagy, @posts = pagy(Post.all, items: 25)

  render json: {
    data: PostSerializer.new(@posts).serialize,
    meta: {
      current_page: @pagy.page,
      total_pages: @pagy.pages,
      total_count: @pagy.count,
      per_page: @pagy.items,
      next_page: @pagy.next,
      prev_page: @pagy.prev
    }
  }
end
```

---

## Authorization (Pundit)

```ruby
# Gemfile
gem "pundit"

# app/policies/post_policy.rb
class PostPolicy < ApplicationPolicy
  def show?
    record.published? || record.author == user || user.admin?
  end

  def update?
    record.author == user || user.admin?
  end

  def destroy?
    record.author == user || user.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(published: true).or(scope.where(author: user))
      end
    end
  end
end

# Usage in controller
def show
  @post = Post.find(params[:id])
  authorize @post
  render json: PostSerializer.new(@post).serialize
end
```

---

## Rate Limiting

```ruby
# Gemfile
gem "rack-attack"

# config/initializers/rack_attack.rb
class Rack::Attack
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  throttle("api/ip", limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/") && req.post?
  end

  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/login" && req.post?
      req.params["email"].to_s.downcase.presence
    end
  end

  self.throttled_responder = lambda do |env|
    retry_after = env["rack.attack.match_data"][:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "Rate limit exceeded. Try again in #{retry_after} seconds." }.to_json]
    ]
  end
end
```

---

## Error Handling

```ruby
# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ApplicationController
      include ApiErrorHandling

      skip_forgery_protection
      before_action :authenticate_with_token!

      respond_to :json
    end
  end
end
```

---

## Best Practices

1. **Keep controllers thin** - Delegate business logic to service objects
2. **One action per controller** when actions get complex (Single Responsibility)
3. **Use strong parameters** consistently for all input
4. **Respond to multiple formats** (HTML + Turbo Stream for Hotwire apps)
5. **Use `rescue_from`** in base controllers for consistent error handling
6. **Authorize every action** with Pundit or Action Policy
7. **Version your APIs** from day one using namespace routing
8. **Add rate limiting** to protect against abuse

---

## Anti-Patterns

```ruby
# BAD: Fat controller with business logic
class PostsController < ApplicationController
  def create
    @post = Post.new(post_params)
    @post.author = current_user
    if @post.save
      @post.followers.each do |follower|
        NotificationMailer.new_post(follower, @post).deliver_later
      end
      SearchIndex.index(@post)
      Analytics.track("post_created", @post.id)
      render json: @post, status: :created
    else
      render json: { errors: @post.errors }, status: :unprocessable_entity
    end
  end
end

# GOOD: Thin controller delegating to service
class PostsController < ApplicationController
  def create
    result = Posts::CreateService.new(author: current_user, params: post_params).call
    if result.success?
      render json: result.data[:post], status: :created
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end
end

# BAD: Inconsistent error responses
# BAD: No authorization checks
# BAD: No rate limiting on public APIs
```

---

## Sources & References

- [Layered Architecture in Ruby on Rails: A Deep Dive](https://patrick204nqh.github.io/tech/rails/architecture/layered-architecture-in-ruby-on-rails-a-deep-dive/)
- [A Comprehensive Guide to Rails Service Objects](https://www.toptal.com/ruby-on-rails/rails-service-objects-tutorial)
- [Building APIs with Rails: Best Practices for 2025](https://codescaptain.medium.com/building-apis-with-rails-best-practices-for-2025-295e0809115d)
- [Effortless JSON Serialization in Rails Using Blueprinter](https://medium.com/@abdulmuqsit987/effortless-json-serialization-in-rails-using-blueprinter-914110c7bb1c)
- [Hotwire and Turbo in Rails: Complete Guide 2025](https://www.railscarma.com/blog/hotwire-and-turbo-in-rails-complete-guide/)
- [Securing Rails Applications - Ruby on Rails Guides](https://guides.rubyonrails.org/security.html)
- [Action Controller Overview](https://guides.rubyonrails.org/action_controller_overview.html)
- [Rails Routing from the Outside In](https://guides.rubyonrails.org/routing.html)
