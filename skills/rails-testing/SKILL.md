---
name: rails-testing
description: Rails testing patterns with RSpec, security best practices (CSRF, XSS, CSP), FactoryBot, request/system specs, and CI setup
---

# Rails Testing & Security

Production-ready testing patterns and security best practices for Rails 7/8. Covers RSpec configuration, FactoryBot, model/request/system specs, shared examples, security (CSRF, XSS, SQL injection, CSP), Brakeman, and CI integration.

## Table of Contents

1. [RSpec Configuration](#rspec-configuration)
2. [FactoryBot Patterns](#factorybot-patterns)
3. [Model Specs](#model-specs)
4. [Request Specs (API Testing)](#request-specs-api-testing)
5. [System Specs (Browser Testing)](#system-specs-browser-testing)
6. [Shared Examples](#shared-examples)
7. [ViewComponent Testing](#viewcomponent-testing)
8. [Security - Content Security Policy](#security---content-security-policy)
9. [Security - CSRF Protection](#security---csrf-protection)
10. [Security - Strong Parameters](#security---strong-parameters)
11. [Security - Secrets Management](#security---secrets-management)
12. [Brakeman (Static Analysis)](#brakeman-static-analysis)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)

---

## RSpec Configuration

```ruby
# spec/rails_helper.rb
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("Rails is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "capybara/rspec"

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include RequestSpecHelper, type: :request
  config.include SystemSpecHelper, type: :system

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before { DatabaseCleaner.strategy = :transaction }
  config.before(:each, js: true) { DatabaseCleaner.strategy = :truncation }
  config.before { DatabaseCleaner.start }
  config.after { DatabaseCleaner.clean }
end

# spec/spec_helper.rb
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
```

---

## FactoryBot Patterns

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { Faker::Name.name }
    password { "password123" }

    association :organization

    trait :admin do
      role { "admin" }
    end

    trait :with_posts do
      transient do
        posts_count { 3 }
      end

      after(:create) do |user, evaluator|
        create_list(:post, evaluator.posts_count, author: user)
      end
    end

    trait :inactive do
      active { false }
    end

    factory :admin_user, traits: [:admin]
    factory :inactive_user, traits: [:inactive]
  end
end

# Usage
user = create(:user)
admin = create(:admin_user)
user_with_posts = create(:user, :with_posts, posts_count: 5)
user = build(:user)              # Without saving
user = build_stubbed(:user)      # Without database
attrs = attributes_for(:user)    # Attributes hash
```

### Advanced FactoryBot

```ruby
factory :post do
  title { "Post #{SecureRandom.hex(4)}" }
  published_at { rand(1..30).days.ago }
  published { published_at.present? }

  after(:build) do |post|
    post.slug = post.title.parameterize
  end

  transient do
    notify_author { false }
  end

  after(:create) do |post, evaluator|
    PostMailer.published(post).deliver_later if evaluator.notify_author
  end
end

factory :post_with_everything, parent: :post do
  association :author, factory: :user
  association :category

  after(:create) do |post|
    create_list(:comment, 3, post: post)
    create_list(:tag, 5, posts: [post])
  end
end
```

---

## Model Specs

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to have_one(:profile).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_inclusion_of(:role).in_array(User::ROLES) }

    it "validates email format" do
      user = build(:user, email: "invalid")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("is invalid")
    end
  end

  describe "scopes" do
    let!(:active_user) { create(:user, active: true) }
    let!(:inactive_user) { create(:user, active: false) }

    describe ".active" do
      it "returns only active users" do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user)
      end
    end
  end

  describe "#display_name" do
    context "when name is present" do
      let(:user) { build(:user, name: "John Doe") }
      it "returns the name" do
        expect(user.display_name).to eq("John Doe")
      end
    end

    context "when name is blank" do
      let(:user) { build(:user, name: "", email: "john@example.com") }
      it "returns email username" do
        expect(user.display_name).to eq("john")
      end
    end
  end

  describe "callbacks" do
    it "normalizes email before validation" do
      user = build(:user, email: " USER@EXAMPLE.COM ")
      user.valid?
      expect(user.email).to eq("user@example.com")
    end

    it "sends welcome email after creation", :aggregate_failures do
      expect {
        create(:user)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end
  end
end
```

---

## Request Specs (API Testing)

```ruby
# spec/requests/api/v1/posts_spec.rb
RSpec.describe "Api::V1::Posts", type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.token}" } }
  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:headers) { auth_headers.merge(json_headers) }

  describe "GET /api/v1/posts" do
    let!(:posts) { create_list(:post, 3, :published) }

    before { get "/api/v1/posts", headers: headers }

    it "returns success" do
      expect(response).to have_http_status(:ok)
    end

    it "returns all posts" do
      expect(json_response["data"].size).to eq(3)
    end

    it "returns correct structure", :aggregate_failures do
      post_data = json_response["data"].first
      expect(post_data).to include("id", "title", "body", "published_at")
      expect(post_data["author"]).to include("id", "name", "email")
    end
  end

  describe "POST /api/v1/posts" do
    let(:valid_params) do
      { post: { title: "New Post", body: "Post content", published: true } }
    end

    context "with valid params" do
      it "creates a post" do
        expect {
          post "/api/v1/posts", params: valid_params.to_json, headers: headers
        }.to change(Post, :count).by(1)
      end

      it "returns created status" do
        post "/api/v1/posts", params: valid_params.to_json, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { post: { title: "" } } }

      it "does not create a post" do
        expect {
          post "/api/v1/posts", params: invalid_params.to_json, headers: headers
        }.not_to change(Post, :count)
      end

      it "returns unprocessable entity" do
        post "/api/v1/posts", params: invalid_params.to_json, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/v1/posts", params: valid_params.to_json, headers: json_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  def json_response
    JSON.parse(response.body)
  end
end
```

---

## System Specs (Browser Testing)

```ruby
# spec/system/posts_spec.rb
RSpec.describe "Posts", type: :system do
  let(:user) { create(:user) }

  before do
    driven_by(:selenium, using: :headless_chrome, screen_size: [1400, 1400])
    login_as(user)
  end

  describe "Creating a post" do
    it "allows user to create a post", js: true do
      visit posts_path
      click_on "New Post"

      fill_in "Title", with: "My First Post"
      fill_in "Body", with: "This is the post content"
      check "Published"
      click_on "Create Post"

      expect(page).to have_content("Post created successfully")
      expect(page).to have_content("My First Post")
    end

    it "shows validation errors" do
      visit new_post_path
      click_on "Create Post"
      expect(page).to have_content("Title can't be blank")
    end
  end

  describe "Editing a post with Turbo Frame", js: true do
    let!(:post) { create(:post, author: user) }

    it "updates post inline" do
      visit posts_path
      within("##{dom_id(post)}") do
        click_on "Edit"
        fill_in "Title", with: "Updated Title"
        click_on "Update Post"
        expect(page).to have_content("Updated Title")
      end
    end
  end
end
```

---

## Shared Examples

```ruby
# spec/support/shared_examples/api_authentication.rb
RSpec.shared_examples "requires authentication" do
  context "without authentication" do
    it "returns unauthorized" do
      make_request(headers: {})
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# Usage
RSpec.describe "Api::V1::Posts", type: :request do
  describe "GET /api/v1/posts" do
    def make_request(headers:)
      get "/api/v1/posts", headers: headers
    end

    it_behaves_like "requires authentication"
  end
end
```

---

## ViewComponent Testing

```ruby
# app/components/alert_component.rb
class AlertComponent < ViewComponent::Base
  TYPES = {
    notice: { icon: "check-circle", color: "green" },
    alert: { icon: "exclamation-triangle", color: "red" },
  }.freeze

  def initialize(type:, message:, dismissible: true)
    @type = type.to_sym
    @message = message
    @dismissible = dismissible
  end
end

# spec/components/alert_component_spec.rb
RSpec.describe AlertComponent, type: :component do
  it "renders notice alert" do
    render_inline(AlertComponent.new(type: :notice, message: "Done!"))
    expect(page).to have_css(".alert-green")
    expect(page).to have_content("Done!")
  end

  it "renders dismissible button by default" do
    render_inline(AlertComponent.new(type: :notice, message: "Done!"))
    expect(page).to have_button(class: "close")
  end

  it "does not render dismiss button when not dismissible" do
    render_inline(AlertComponent.new(type: :notice, message: "Done!", dismissible: false))
    expect(page).not_to have_button(class: "close")
  end
end
```

---

## Security - Content Security Policy

```ruby
# config/initializers/content_security_policy.rb
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self, :https
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data, :blob
  policy.object_src  :none
  policy.script_src  :self, :https
  policy.style_src   :self, :https
  policy.script_src :self, :https, :unsafe_inline if Rails.env.development?
  policy.report_uri "/csp-violation-report-endpoint"
end

Rails.application.config.content_security_policy_nonce_generator =
  ->(request) { SecureRandom.base64(16) }
```

---

## Security - CSRF Protection

```ruby
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
end

# For API controllers (use API tokens instead)
class Api::V1::BaseController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_with_token!
end
```

---

## Security - Strong Parameters

```ruby
class PostsController < ApplicationController
  private

  def post_params
    params.require(:post).permit(
      :title, :body,
      tag_ids: [],
      author_attributes: [:name, :email],
      comments_attributes: [:id, :body, :_destroy],
      metadata: {}
    )
  end
end

# Global parameter filtering (logs)
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :password_confirmation, :ssn, :credit_card, :cvv
]
```

---

## Security - Secrets Management

```ruby
# Use Rails encrypted credentials
# bin/rails credentials:edit --environment production

# Access in code
Rails.application.credentials.dig(:aws, :access_key_id)
Rails.application.credentials.stripe[:secret_key]
```

### Security Headers

```ruby
# config/application.rb
config.action_dispatch.default_headers = {
  'X-Frame-Options' => 'SAMEORIGIN',
  'X-Content-Type-Options' => 'nosniff',
  'X-XSS-Protection' => '0',
  'Referrer-Policy' => 'strict-origin-when-cross-origin'
}

# config/environments/production.rb
config.force_ssl = true
config.ssl_options = {
  hsts: { expires: 31536000, subdomains: true, preload: true }
}
```

---

## Brakeman (Static Analysis)

```bash
# Install
gem install brakeman

# Run scan
brakeman

# CI/CD integration
brakeman --exit-on-warn --no-pager
```

```yaml
# .github/workflows/security.yml
- name: Run Brakeman
  run: bundle exec brakeman --no-pager --exit-on-warn
```

---

## Best Practices

1. **Test behavior, not implementation** - Focus on inputs and outputs
2. **Use `build_stubbed` for unit tests** - Faster than `create` (no database)
3. **Use `let!` sparingly** - Only when records must exist before the test runs
4. **Use `aggregate_failures`** for multiple assertions in one example
5. **Run Brakeman in CI** - Catch security issues early
6. **Test authorization** - Verify forbidden access for every endpoint
7. **Use VCR or WebMock** for external API calls in tests
8. **Keep factories minimal** - Only required attributes, use traits for variations

---

## Anti-Patterns

```ruby
# BAD: Testing implementation details
it "calls the save method" do
  expect(user).to receive(:save)
  # ...
end

# GOOD: Testing behavior
it "creates the user" do
  expect { subject }.to change(User, :count).by(1)
end

# BAD: Shared state between tests (using instance variables in before blocks)
# BAD: Testing private methods directly
# BAD: Overly complex factories with many associations (slow tests)
# BAD: Not testing error paths and edge cases

# GOOD: Each test is independent
# GOOD: Test public interface only
# GOOD: Minimal factory definitions with traits
# GOOD: Test both happy path and error cases
```

---

## Sources & References

- [Complete Guide to RSpec with Rails 7+](https://railsdrop.com/2025/08/08/complete-guide-to-rspec-with-rails-from-basics-to-advanced-testing/)
- [A journey towards better Ruby on Rails testing practices](https://thoughtbot.com/blog/a-journey-towards-better-testing-practices)
- [Securing Rails Applications - Ruby on Rails Guides](https://guides.rubyonrails.org/security.html)
- [A Complete Guide to Ruby on Rails Security Measures](https://railsdrop.com/2025/05/11/a-complete-guide-to-ruby-on-rails-security-measures/)
- [FactoryBot Getting Started](https://github.com/thoughtbot/factory_bot/blob/main/GETTING_STARTED.md)
- [RSpec Best Practices](https://www.betterspecs.org/)
- [ViewComponent Testing](https://viewcomponent.org/guide/testing.html)
- [Brakeman Security Scanner](https://brakemanscanner.org/)
