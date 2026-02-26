---
name: dotnet-testing
description: Comprehensive .NET 8 testing with xUnit, Moq, FluentAssertions, WebApplicationFactory integration testing, EF Core test strategies, test fixtures, data builders, background service testing, coverlet code coverage, and CI pipeline integration
---

# .NET Testing

Production-ready testing patterns for C# 12 / .NET 8 applications. Covers xUnit fundamentals, Moq mocking, FluentAssertions, integration testing with WebApplicationFactory, EF Core database strategies, test fixtures, test data builders, background service testing, code coverage with coverlet, and CI integration.

## Table of Contents

1. [Test Project Organization](#test-project-organization)
2. [xUnit Fundamentals](#xunit-fundamentals)
3. [Test Naming Conventions](#test-naming-conventions)
4. [Moq for Mocking](#moq-for-mocking)
5. [FluentAssertions](#fluentassertions)
6. [Integration Testing with WebApplicationFactory](#integration-testing-with-webapplicationfactory)
7. [Custom WebApplicationFactory](#custom-webapplicationfactory)
8. [Testing HTTP Endpoints](#testing-http-endpoints)
9. [Testing EF Core - In-Memory vs SQLite](#testing-ef-core---in-memory-vs-sqlite)
10. [Test Fixtures](#test-fixtures)
11. [Test Data Builders and Object Mothers](#test-data-builders-and-object-mothers)
12. [Testing Background Services](#testing-background-services)
13. [Code Coverage with Coverlet](#code-coverage-with-coverlet)
14. [CI Integration and Parallel Test Execution](#ci-integration-and-parallel-test-execution)
15. [Best Practices](#best-practices)
16. [Anti-Patterns](#anti-patterns)
17. [Sources & References](#sources--references)

---

## Test Project Organization

Structure test projects to mirror source projects. Keep unit, integration, and functional tests separated.

```
src/
  MyApp.Api/
  MyApp.Domain/
  MyApp.Infrastructure/
tests/
  MyApp.Api.Tests/                  # Unit tests for API layer
  MyApp.Domain.Tests/               # Unit tests for domain logic
  MyApp.Infrastructure.Tests/       # Unit tests for infrastructure
  MyApp.Api.IntegrationTests/       # Integration tests (WebApplicationFactory)
  MyApp.FunctionalTests/            # End-to-end functional tests
```

Each test project `.csproj` should reference the appropriate packages:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.9.0" />
    <PackageReference Include="xunit" Version="2.7.0" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.5.7" />
    <PackageReference Include="Moq" Version="4.20.70" />
    <PackageReference Include="FluentAssertions" Version="6.12.0" />
    <PackageReference Include="coverlet.collector" Version="6.0.1" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp.Domain\MyApp.Domain.csproj" />
  </ItemGroup>
</Project>
```

For integration test projects, add:

```xml
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="8.0.2" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="8.0.2" />
```

---

## xUnit Fundamentals

### Fact - Simple Test Cases

Use `[Fact]` for tests that are always true and take no parameters.

```csharp
public class OrderServiceTests
{
    [Fact]
    public void CalculateTotal_WithValidItems_ReturnsSumOfItemPrices()
    {
        // Arrange
        var order = new Order();
        order.AddItem(new OrderItem("Widget", 10.00m, 2));
        order.AddItem(new OrderItem("Gadget", 25.00m, 1));

        // Act
        decimal total = order.CalculateTotal();

        // Assert
        Assert.Equal(45.00m, total);
    }

    [Fact]
    public void CalculateTotal_WithEmptyOrder_ReturnsZero()
    {
        var order = new Order();

        decimal total = order.CalculateTotal();

        Assert.Equal(0m, total);
    }
}
```

### Theory - Parameterized Tests

Use `[Theory]` with data attributes for tests that should hold true across multiple inputs.

#### InlineData

Best for a small number of simple parameters:

```csharp
public class EmailValidatorTests
{
    [Theory]
    [InlineData("user@example.com", true)]
    [InlineData("user@sub.example.com", true)]
    [InlineData("user+tag@example.com", true)]
    [InlineData("", false)]
    [InlineData("not-an-email", false)]
    [InlineData("@missing-local.com", false)]
    [InlineData("missing-domain@", false)]
    public void IsValid_ReturnsExpectedResult(string email, bool expected)
    {
        var validator = new EmailValidator();

        bool result = validator.IsValid(email);

        Assert.Equal(expected, result);
    }
}
```

#### MemberData

Use `MemberData` when test data is more complex or generated dynamically:

```csharp
public class DiscountCalculatorTests
{
    public static IEnumerable<object[]> DiscountTestCases()
    {
        yield return new object[] { CustomerTier.Bronze, 100m, 5m };
        yield return new object[] { CustomerTier.Silver, 100m, 10m };
        yield return new object[] { CustomerTier.Gold, 100m, 15m };
        yield return new object[] { CustomerTier.Platinum, 100m, 20m };
    }

    [Theory]
    [MemberData(nameof(DiscountTestCases))]
    public void Apply_ReturnsCorrectDiscount(
        CustomerTier tier, decimal orderTotal, decimal expectedDiscount)
    {
        var calculator = new DiscountCalculator();

        decimal discount = calculator.Apply(tier, orderTotal);

        Assert.Equal(expectedDiscount, discount);
    }
}
```

#### ClassData

Use `ClassData` when test data is reusable across test classes:

```csharp
public class CurrencyConversionTestData : IEnumerable<object[]>
{
    public IEnumerator<object[]> GetEnumerator()
    {
        yield return new object[] { "USD", "EUR", 100m, 92.50m };
        yield return new object[] { "GBP", "USD", 100m, 127.30m };
        yield return new object[] { "JPY", "USD", 10000m, 67.80m };
    }

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

public class CurrencyConverterTests
{
    [Theory]
    [ClassData(typeof(CurrencyConversionTestData))]
    public void Convert_ReturnsCorrectAmount(
        string from, string to, decimal amount, decimal expected)
    {
        var converter = new CurrencyConverter(new FixedRateProvider());

        decimal result = converter.Convert(from, to, amount);

        Assert.Equal(expected, result, precision: 2);
    }
}
```

### Async Tests

xUnit natively supports async test methods:

```csharp
[Fact]
public async Task GetOrderAsync_WithValidId_ReturnsOrder()
{
    var service = new OrderService(_mockRepository.Object);

    Order? result = await service.GetOrderAsync(orderId: 42);

    Assert.NotNull(result);
    Assert.Equal(42, result.Id);
}
```

### Skip and Trait

```csharp
[Fact(Skip = "Requires external API - run manually")]
public async Task ExternalApi_ReturnsValidResponse() { /* ... */ }

[Trait("Category", "Integration")]
[Fact]
public async Task Database_CanConnectAndQuery() { /* ... */ }
```

Filter by trait: `dotnet test --filter "Category=Integration"`

---

## Test Naming Conventions

Follow the pattern: `MethodUnderTest_Scenario_ExpectedBehavior`

```
CalculateTotal_WithEmptyCart_ReturnsZero
CreateUser_WithDuplicateEmail_ThrowsConflictException
GetById_WhenNotFound_ReturnsNull
ProcessPayment_WhenGatewayTimesOut_RetriesThreeTimes
```

Organize test classes to mirror production classes:

- `OrderService` -> `OrderServiceTests`
- `UserController` -> `UserControllerTests`
- `EmailValidator` -> `EmailValidatorTests`

For integration tests, name by feature or scenario:

- `OrderCreationIntegrationTests`
- `AuthenticationFlowTests`

---

## Moq for Mocking

### Basic Setup and Returns

```csharp
public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _mockRepository;
    private readonly Mock<IEmailService> _mockEmailService;
    private readonly Mock<ILogger<OrderService>> _mockLogger;
    private readonly OrderService _sut;

    public OrderServiceTests()
    {
        _mockRepository = new Mock<IOrderRepository>();
        _mockEmailService = new Mock<IEmailService>();
        _mockLogger = new Mock<ILogger<OrderService>>();
        _sut = new OrderService(
            _mockRepository.Object,
            _mockEmailService.Object,
            _mockLogger.Object);
    }

    [Fact]
    public async Task GetByIdAsync_WithExistingOrder_ReturnsOrder()
    {
        // Arrange
        var expectedOrder = new Order { Id = 1, CustomerId = 42, Total = 99.99m };
        _mockRepository
            .Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
            .ReturnsAsync(expectedOrder);

        // Act
        Order? result = await _sut.GetByIdAsync(1);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(42, result.CustomerId);
    }
}
```

### Argument Matchers

```csharp
// Exact value
_mockRepo.Setup(r => r.GetByIdAsync(42, default)).ReturnsAsync(order);

// Any value of type
_mockRepo.Setup(r => r.GetByIdAsync(It.IsAny<int>(), default)).ReturnsAsync(order);

// Matching predicate
_mockRepo
    .Setup(r => r.FindAsync(It.Is<OrderFilter>(f => f.Status == OrderStatus.Active), default))
    .ReturnsAsync(activeOrders);

// Range
_mockRepo
    .Setup(r => r.GetByIdAsync(It.IsInRange(1, 100, Moq.Range.Inclusive), default))
    .ReturnsAsync(order);
```

### Verify

Verify that specific interactions occurred:

```csharp
[Fact]
public async Task PlaceOrder_SendsConfirmationEmail()
{
    // Arrange
    var order = new Order { Id = 1, CustomerEmail = "alice@example.com" };
    _mockRepository
        .Setup(r => r.AddAsync(It.IsAny<Order>(), default))
        .ReturnsAsync(order);

    // Act
    await _sut.PlaceOrderAsync(order);

    // Assert
    _mockEmailService.Verify(
        e => e.SendOrderConfirmationAsync(
            "alice@example.com",
            It.Is<OrderConfirmation>(c => c.OrderId == 1)),
        Times.Once);

    _mockEmailService.Verify(
        e => e.SendOrderConfirmationAsync(
            It.IsAny<string>(),
            It.IsAny<OrderConfirmation>()),
        Times.Once);  // Ensure only one email was sent
}
```

### Callback

Use callbacks to capture arguments or trigger side effects:

```csharp
[Fact]
public async Task PlaceOrder_AssignsSequentialOrderNumber()
{
    Order? capturedOrder = null;
    _mockRepository
        .Setup(r => r.AddAsync(It.IsAny<Order>(), default))
        .Callback<Order, CancellationToken>((order, _) => capturedOrder = order)
        .ReturnsAsync((Order o, CancellationToken _) => o);

    var newOrder = new Order { CustomerEmail = "bob@example.com" };
    await _sut.PlaceOrderAsync(newOrder);

    Assert.NotNull(capturedOrder);
    Assert.False(string.IsNullOrEmpty(capturedOrder.OrderNumber));
}
```

### Sequential Returns and Exceptions

```csharp
// Return different values on consecutive calls
_mockRepo
    .SetupSequence(r => r.GetByIdAsync(1, default))
    .ReturnsAsync((Order?)null)       // First call returns null
    .ReturnsAsync(new Order { Id = 1 }) // Second call returns order
    .ThrowsAsync(new TimeoutException()); // Third call throws

// Setup to throw
_mockRepo
    .Setup(r => r.GetByIdAsync(-1, default))
    .ThrowsAsync(new ArgumentException("Invalid order ID"));
```

### Mock Properties

```csharp
var mockConfig = new Mock<IAppConfiguration>();
mockConfig.SetupGet(c => c.MaxRetryCount).Returns(3);
mockConfig.SetupGet(c => c.TimeoutSeconds).Returns(30);

// Auto-track property changes
var mockSession = new Mock<IUserSession>();
mockSession.SetupProperty(s => s.CurrentUserId);
mockSession.Object.CurrentUserId = 42;
Assert.Equal(42, mockSession.Object.CurrentUserId);
```

### Strict vs Loose Mocking

```csharp
// Loose (default) - unmatched calls return default values
var looseRepo = new Mock<IOrderRepository>(MockBehavior.Loose);

// Strict - unmatched calls throw MockException
var strictRepo = new Mock<IOrderRepository>(MockBehavior.Strict);
strictRepo.Setup(r => r.GetByIdAsync(1, default)).ReturnsAsync(order);
// Any other call to strictRepo will throw
```

---

## FluentAssertions

FluentAssertions provides readable, chainable assertions with informative failure messages.

### Basic Assertions

```csharp
using FluentAssertions;

[Fact]
public void Order_CalculateTotal_AppliesDiscountCorrectly()
{
    var order = new Order();
    order.AddItem(new OrderItem("Widget", 100m, 2));
    order.ApplyDiscount(0.10m);

    decimal total = order.CalculateTotal();

    total.Should().Be(180m);
    total.Should().BePositive();
    total.Should().BeInRange(170m, 190m);
}
```

### String Assertions

```csharp
string result = service.GenerateOrderNumber();

result.Should().StartWith("ORD-");
result.Should().HaveLength(12);
result.Should().MatchRegex(@"^ORD-\d{8}$");
result.Should().NotBeNullOrWhiteSpace();
```

### Collection Assertions

```csharp
List<Order> orders = await service.GetActiveOrdersAsync();

orders.Should().NotBeEmpty()
    .And.HaveCount(3)
    .And.OnlyContain(o => o.Status == OrderStatus.Active)
    .And.BeInAscendingOrder(o => o.CreatedAt);

orders.Should().ContainSingle(o => o.Id == 42);
orders.Should().NotContainNulls();
```

### Exception Assertions

```csharp
Func<Task> act = () => service.PlaceOrderAsync(null!);

await act.Should().ThrowAsync<ArgumentNullException>()
    .WithParameterName("order")
    .WithMessage("*cannot be null*");
```

### Object Graph Comparison

```csharp
var expected = new OrderDto { Id = 1, Total = 99.99m, Status = "Active" };

OrderDto result = mapper.Map(order);

result.Should().BeEquivalentTo(expected, options => options
    .Excluding(o => o.CreatedAt)    // Ignore volatile fields
    .Using<decimal>(ctx => ctx.Subject.Should().BeApproximately(ctx.Expectation, 0.01m))
    .WhenTypeIs<decimal>());
```

### Execution Time Assertions

```csharp
Action act = () => service.ProcessBatch(items);

act.ExecutionTime().Should().BeLessThan(TimeSpan.FromSeconds(5));
```

---

## Integration Testing with WebApplicationFactory

`WebApplicationFactory<TEntryPoint>` creates an in-memory test server for integration testing ASP.NET Core applications.

### Basic Usage

```csharp
using Microsoft.AspNetCore.Mvc.Testing;

public class OrdersApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public OrdersApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
            BaseAddress = new Uri("https://localhost")
        });
    }

    [Fact]
    public async Task GetOrders_ReturnsSuccessStatusCode()
    {
        HttpResponseMessage response = await _client.GetAsync("/api/orders");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task GetOrder_WithInvalidId_ReturnsNotFound()
    {
        HttpResponseMessage response = await _client.GetAsync("/api/orders/99999");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

Ensure `Program` is accessible by adding to your API project:

```csharp
// At the bottom of Program.cs or in a separate file
public partial class Program { }
```

---

## Custom WebApplicationFactory

Override services, databases, and configuration for isolated integration tests.

```csharp
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    private SqliteConnection? _connection;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureServices(services =>
        {
            // Remove the production DbContext registration
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<AppDbContext>();

            // Create and open a persistent SQLite in-memory connection
            _connection = new SqliteConnection("DataSource=:memory:");
            _connection.Open();

            // Register the test DbContext with SQLite
            services.AddDbContext<AppDbContext>(options =>
            {
                options.UseSqlite(_connection);
                options.EnableSensitiveDataLogging();
                options.EnableDetailedErrors();
            });

            // Replace external services with test doubles
            services.RemoveAll<IEmailService>();
            services.AddSingleton<IEmailService, FakeEmailService>();

            services.RemoveAll<IPaymentGateway>();
            services.AddSingleton<IPaymentGateway, FakePaymentGateway>();

            // Ensure the database schema is created
            using ServiceProvider sp = services.BuildServiceProvider();
            using IServiceScope scope = sp.CreateScope();
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Database.EnsureCreated();
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            _connection?.Dispose();
        }
    }
}
```

### Fake Service Implementations

```csharp
public sealed class FakeEmailService : IEmailService
{
    private readonly List<SentEmail> _sentEmails = [];

    public IReadOnlyList<SentEmail> SentEmails => _sentEmails.AsReadOnly();

    public Task SendOrderConfirmationAsync(
        string recipientEmail,
        OrderConfirmation confirmation,
        CancellationToken cancellationToken = default)
    {
        _sentEmails.Add(new SentEmail(recipientEmail, "OrderConfirmation", confirmation));
        return Task.CompletedTask;
    }

    public void Reset() => _sentEmails.Clear();
}

public sealed record SentEmail(string Recipient, string TemplateType, object Payload);

public sealed class FakePaymentGateway : IPaymentGateway
{
    public bool ShouldSucceed { get; set; } = true;

    public Task<PaymentResult> ChargeAsync(
        PaymentRequest request,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult(ShouldSucceed
            ? PaymentResult.Success(transactionId: Guid.NewGuid().ToString())
            : PaymentResult.Failure("Payment declined"));
    }
}
```

---

## Testing HTTP Endpoints

### Full CRUD Integration Tests

```csharp
public class OrdersEndpointTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly CustomWebApplicationFactory _factory;

    public OrdersEndpointTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task CreateOrder_WithValidPayload_ReturnsCreated()
    {
        // Arrange
        var request = new CreateOrderRequest
        {
            CustomerId = 1,
            Items =
            [
                new OrderItemRequest { ProductId = 10, Quantity = 2 },
                new OrderItemRequest { ProductId = 20, Quantity = 1 }
            ]
        };

        // Act
        HttpResponseMessage response = await _client.PostAsJsonAsync("/api/orders", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        OrderResponse? body = await response.Content.ReadFromJsonAsync<OrderResponse>();
        body.Should().NotBeNull();
        body!.Items.Should().HaveCount(2);
        body.Status.Should().Be("Pending");
    }

    [Fact]
    public async Task CreateOrder_WithEmptyItems_ReturnsBadRequest()
    {
        var request = new CreateOrderRequest
        {
            CustomerId = 1,
            Items = []
        };

        HttpResponseMessage response = await _client.PostAsJsonAsync("/api/orders", request);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        ValidationProblemDetails? problem =
            await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        problem.Should().NotBeNull();
        problem!.Errors.Should().ContainKey("Items");
    }

    [Fact]
    public async Task GetOrder_AfterCreate_ReturnsMatchingOrder()
    {
        // Arrange - create an order first
        var request = new CreateOrderRequest
        {
            CustomerId = 1,
            Items = [new OrderItemRequest { ProductId = 10, Quantity = 3 }]
        };
        HttpResponseMessage createResponse = await _client.PostAsJsonAsync("/api/orders", request);
        OrderResponse? created = await createResponse.Content.ReadFromJsonAsync<OrderResponse>();

        // Act
        HttpResponseMessage getResponse = await _client.GetAsync($"/api/orders/{created!.Id}");

        // Assert
        getResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        OrderResponse? fetched = await getResponse.Content.ReadFromJsonAsync<OrderResponse>();
        fetched.Should().BeEquivalentTo(created);
    }

    [Fact]
    public async Task DeleteOrder_WithExistingOrder_ReturnsNoContent()
    {
        // Arrange - seed via scoped service
        int orderId;
        using (IServiceScope scope = _factory.Services.CreateScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var order = new Order { CustomerId = 1, Status = OrderStatus.Pending };
            db.Orders.Add(order);
            await db.SaveChangesAsync();
            orderId = order.Id;
        }

        // Act
        HttpResponseMessage response = await _client.DeleteAsync($"/api/orders/{orderId}");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }
}
```

### Testing Authenticated Endpoints

```csharp
public class AuthenticatedEndpointTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public AuthenticatedEndpointTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    private HttpClient CreateAuthenticatedClient(string userId, string role)
    {
        return _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddAuthentication("Test")
                    .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(
                        "Test", options => { });

                services.AddSingleton<ITestClaimsProvider>(
                    new TestClaimsProvider(userId, role));
            });
        }).CreateClient();
    }

    [Fact]
    public async Task AdminEndpoint_WithAdminRole_ReturnsOk()
    {
        HttpClient client = CreateAuthenticatedClient("user-1", "Admin");

        HttpResponseMessage response = await client.GetAsync("/api/admin/dashboard");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task AdminEndpoint_WithUserRole_ReturnsForbidden()
    {
        HttpClient client = CreateAuthenticatedClient("user-2", "User");

        HttpResponseMessage response = await client.GetAsync("/api/admin/dashboard");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task ProtectedEndpoint_WithoutAuth_ReturnsUnauthorized()
    {
        HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/orders");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}

public sealed class TestClaimsProvider(string userId, string role) : ITestClaimsProvider
{
    public string UserId => userId;
    public string Role => role;
}
```

---

## Testing EF Core - In-Memory vs SQLite

### Why SQLite Over EF Core In-Memory Provider

| Aspect | EF In-Memory | SQLite In-Memory |
|--------|-------------|------------------|
| Foreign keys | Not enforced | Enforced |
| Transactions | Not supported | Supported |
| Raw SQL | Not supported | Supported |
| Constraint validation | Partial | Full |
| Behavior fidelity | Low | High |

The EF Core in-memory provider does not enforce relational constraints and behaves differently from real databases. Prefer SQLite in-memory for integration tests.

### SQLite In-Memory Test Database

```csharp
public abstract class DatabaseTestBase : IAsyncLifetime
{
    private SqliteConnection? _connection;
    protected AppDbContext DbContext { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        await _connection.OpenAsync();

        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(_connection)
            .EnableSensitiveDataLogging()
            .EnableDetailedErrors()
            .Options;

        DbContext = new AppDbContext(options);
        await DbContext.Database.EnsureCreatedAsync();

        await SeedAsync(DbContext);
    }

    protected virtual Task SeedAsync(AppDbContext context) => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        await DbContext.DisposeAsync();
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }
    }
}

public class OrderRepositoryTests : DatabaseTestBase
{
    protected override async Task SeedAsync(AppDbContext context)
    {
        context.Customers.Add(new Customer { Id = 1, Name = "Alice", Email = "alice@test.com" });
        context.Products.Add(new Product { Id = 10, Name = "Widget", Price = 25.00m });
        await context.SaveChangesAsync();
    }

    [Fact]
    public async Task AddAsync_PersistsOrderWithItems()
    {
        var repository = new OrderRepository(DbContext);
        var order = new Order
        {
            CustomerId = 1,
            Items = [new OrderItem { ProductId = 10, Quantity = 3, UnitPrice = 25.00m }]
        };

        Order result = await repository.AddAsync(order);

        result.Id.Should().BeGreaterThan(0);
        Order? persisted = await DbContext.Orders
            .Include(o => o.Items)
            .FirstOrDefaultAsync(o => o.Id == result.Id);
        persisted.Should().NotBeNull();
        persisted!.Items.Should().HaveCount(1);
        persisted.Items[0].Quantity.Should().Be(3);
    }

    [Fact]
    public async Task GetActiveOrdersAsync_ReturnsOnlyActiveOrders()
    {
        var repository = new OrderRepository(DbContext);
        DbContext.Orders.AddRange(
            new Order { CustomerId = 1, Status = OrderStatus.Active },
            new Order { CustomerId = 1, Status = OrderStatus.Cancelled },
            new Order { CustomerId = 1, Status = OrderStatus.Active });
        await DbContext.SaveChangesAsync();

        IReadOnlyList<Order> result = await repository.GetActiveOrdersAsync();

        result.Should().HaveCount(2);
        result.Should().OnlyContain(o => o.Status == OrderStatus.Active);
    }
}
```

### When to Use EF Core In-Memory

Only use for simple unit tests that test LINQ-to-Objects behavior where relational integrity is irrelevant:

```csharp
// Acceptable: testing a simple query filter method
var options = new DbContextOptionsBuilder<AppDbContext>()
    .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
    .Options;
```

---

## Test Fixtures

### IClassFixture - Shared Per Test Class

Use when setup is expensive and can be shared across all tests in a class:

```csharp
public sealed class DatabaseFixture : IAsyncLifetime
{
    public AppDbContext DbContext { get; private set; } = null!;
    private SqliteConnection? _connection;

    public async Task InitializeAsync()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        await _connection.OpenAsync();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(_connection)
            .Options;

        DbContext = new AppDbContext(options);
        await DbContext.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await DbContext.DisposeAsync();
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }
    }
}

public class ProductServiceTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _fixture;

    public ProductServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task GetAllProducts_ReturnsProducts()
    {
        var service = new ProductService(_fixture.DbContext);
        IReadOnlyList<Product> products = await service.GetAllAsync();
        products.Should().NotBeNull();
    }
}
```

### ICollectionFixture - Shared Across Test Classes

Use when multiple test classes need the same expensive fixture:

```csharp
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
    // This class has no code; it simply associates the fixture with the collection name.
}

[Collection("Database")]
public class OrderServiceTests
{
    private readonly DatabaseFixture _fixture;

    public OrderServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task CreateOrder_PersistsToDatabase()
    {
        // Tests share the same DatabaseFixture instance
        var service = new OrderService(new OrderRepository(_fixture.DbContext));
        // ...
    }
}

[Collection("Database")]
public class CustomerServiceTests
{
    private readonly DatabaseFixture _fixture;

    public CustomerServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task GetCustomer_ReturnsCustomer()
    {
        // Same DatabaseFixture instance as OrderServiceTests
        // ...
    }
}
```

### IAsyncLifetime for Async Setup/Teardown

```csharp
public class ExternalServiceTests : IAsyncLifetime
{
    private TestContainer? _container;

    public async Task InitializeAsync()
    {
        // Start a test container or initialize expensive resource
        _container = await TestContainerBuilder.CreatePostgresAsync();
    }

    public async Task DisposeAsync()
    {
        if (_container is not null)
        {
            await _container.DisposeAsync();
        }
    }

    [Fact]
    public async Task CanConnectToPostgres()
    {
        // Use _container.ConnectionString
    }
}
```

---

## Test Data Builders and Object Mothers

### Builder Pattern

Create fluent builders to construct test objects with sensible defaults:

```csharp
public sealed class OrderBuilder
{
    private int _customerId = 1;
    private OrderStatus _status = OrderStatus.Pending;
    private readonly List<OrderItem> _items = [];
    private decimal? _discountPercent;
    private DateTimeOffset _createdAt = DateTimeOffset.UtcNow;

    public OrderBuilder WithCustomerId(int customerId)
    {
        _customerId = customerId;
        return this;
    }

    public OrderBuilder WithStatus(OrderStatus status)
    {
        _status = status;
        return this;
    }

    public OrderBuilder WithItem(string product, decimal unitPrice, int quantity = 1)
    {
        _items.Add(new OrderItem
        {
            ProductName = product,
            UnitPrice = unitPrice,
            Quantity = quantity
        });
        return this;
    }

    public OrderBuilder WithDiscount(decimal percent)
    {
        _discountPercent = percent;
        return this;
    }

    public OrderBuilder CreatedAt(DateTimeOffset timestamp)
    {
        _createdAt = timestamp;
        return this;
    }

    public Order Build()
    {
        var order = new Order
        {
            CustomerId = _customerId,
            Status = _status,
            CreatedAt = _createdAt,
            Items = _items.Count > 0
                ? _items
                : [new OrderItem { ProductName = "Default Widget", UnitPrice = 10m, Quantity = 1 }]
        };

        if (_discountPercent.HasValue)
        {
            order.ApplyDiscount(_discountPercent.Value);
        }

        return order;
    }
}

// Usage in tests
[Fact]
public void Order_WithDiscount_CalculatesCorrectTotal()
{
    Order order = new OrderBuilder()
        .WithItem("Laptop", 999.99m, quantity: 1)
        .WithItem("Mouse", 29.99m, quantity: 2)
        .WithDiscount(0.10m)
        .Build();

    decimal total = order.CalculateTotal();

    total.Should().BeApproximately(953.97m, precision: 0.01m);
}
```

### Object Mother

Static factory methods for common test objects:

```csharp
public static class TestOrders
{
    public static Order PendingOrder(int customerId = 1) =>
        new OrderBuilder()
            .WithCustomerId(customerId)
            .WithStatus(OrderStatus.Pending)
            .WithItem("Widget", 25.00m, 2)
            .Build();

    public static Order CompletedOrder(int customerId = 1) =>
        new OrderBuilder()
            .WithCustomerId(customerId)
            .WithStatus(OrderStatus.Completed)
            .WithItem("Premium Widget", 99.99m)
            .Build();

    public static Order HighValueOrder(int customerId = 1) =>
        new OrderBuilder()
            .WithCustomerId(customerId)
            .WithItem("Server", 5000m, 3)
            .WithItem("License", 2000m, 10)
            .Build();

    public static Order CancelledOrder(int customerId = 1) =>
        new OrderBuilder()
            .WithCustomerId(customerId)
            .WithStatus(OrderStatus.Cancelled)
            .Build();
}

public static class TestCustomers
{
    public static Customer Alice() => new()
    {
        Id = 1, Name = "Alice Smith", Email = "alice@example.com", Tier = CustomerTier.Gold
    };

    public static Customer Bob() => new()
    {
        Id = 2, Name = "Bob Jones", Email = "bob@example.com", Tier = CustomerTier.Bronze
    };
}
```

---

## Testing Background Services

### Testing IHostedService / BackgroundService

```csharp
public sealed class OrderProcessingService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<OrderProcessingService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromMinutes(5);

    public OrderProcessingService(
        IServiceScopeFactory scopeFactory,
        ILogger<OrderProcessingService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using PeriodicTimer timer = new(_interval);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await ProcessPendingOrdersAsync(stoppingToken);
        }
    }

    public async Task ProcessPendingOrdersAsync(CancellationToken cancellationToken)
    {
        using IServiceScope scope = _scopeFactory.CreateScope();
        IOrderRepository repository = scope.ServiceProvider
            .GetRequiredService<IOrderRepository>();

        IReadOnlyList<Order> pendingOrders = await repository
            .GetByStatusAsync(OrderStatus.Pending, cancellationToken);

        foreach (Order order in pendingOrders)
        {
            order.Status = OrderStatus.Processing;
            await repository.UpdateAsync(order, cancellationToken);
            _logger.LogInformation("Processing order {OrderId}", order.Id);
        }
    }
}

// Test the business logic directly, not the timer
public class OrderProcessingServiceTests
{
    [Fact]
    public async Task ProcessPendingOrdersAsync_UpdatesStatusToProcessing()
    {
        // Arrange
        var pendingOrders = new List<Order>
        {
            new() { Id = 1, Status = OrderStatus.Pending },
            new() { Id = 2, Status = OrderStatus.Pending }
        };

        var mockRepo = new Mock<IOrderRepository>();
        mockRepo
            .Setup(r => r.GetByStatusAsync(OrderStatus.Pending, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pendingOrders);

        var mockScope = new Mock<IServiceScope>();
        var mockScopeFactory = new Mock<IServiceScopeFactory>();
        var mockServiceProvider = new Mock<IServiceProvider>();

        mockServiceProvider
            .Setup(sp => sp.GetService(typeof(IOrderRepository)))
            .Returns(mockRepo.Object);
        mockScope.Setup(s => s.ServiceProvider).Returns(mockServiceProvider.Object);
        mockScopeFactory.Setup(f => f.CreateScope()).Returns(mockScope.Object);

        var service = new OrderProcessingService(
            mockScopeFactory.Object,
            Mock.Of<ILogger<OrderProcessingService>>());

        // Act
        await service.ProcessPendingOrdersAsync(CancellationToken.None);

        // Assert
        mockRepo.Verify(
            r => r.UpdateAsync(It.Is<Order>(o => o.Status == OrderStatus.Processing),
                It.IsAny<CancellationToken>()),
            Times.Exactly(2));

        pendingOrders.Should().OnlyContain(o => o.Status == OrderStatus.Processing);
    }
}
```

### Testing BackgroundService Lifecycle via Integration Test

```csharp
[Fact]
public async Task BackgroundService_StartsAndStopsGracefully()
{
    await using CustomWebApplicationFactory factory = new();
    using HttpClient client = factory.CreateClient();

    // The hosted service starts automatically with the test server.
    // Trigger some testable side effect, then verify.

    // Seed pending orders
    using (IServiceScope scope = factory.Services.CreateScope())
    {
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Orders.Add(new Order { CustomerId = 1, Status = OrderStatus.Pending });
        await db.SaveChangesAsync();
    }

    // Wait briefly for the background service to process
    await Task.Delay(TimeSpan.FromSeconds(2));

    // Verify the order was processed
    using (IServiceScope scope = factory.Services.CreateScope())
    {
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Order? order = await db.Orders.FirstOrDefaultAsync();
        // Depending on timing, verify state or check logs
        order.Should().NotBeNull();
    }
}
```

---

## Code Coverage with Coverlet

### Running Coverage

```bash
# Run tests with coverage collection
dotnet test --collect:"XPlat Code Coverage"

# Generate human-readable report
dotnet tool install -g dotnet-reportgenerator-globaltool

reportgenerator \
  -reports:"**/coverage.cobertura.xml" \
  -targetdir:"coveragereport" \
  -reporttypes:"Html;Cobertura;TextSummary"
```

### Coverage Configuration

Add a `coverlet.runsettings` file:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat code coverage">
        <Configuration>
          <Format>cobertura</Format>
          <Exclude>
            [*.Tests]*
            [*]*.Migrations.*
            [*]*.Program
            [*]*.Startup
          </Exclude>
          <Include>
            [MyApp.Domain]*
            [MyApp.Api]*
            [MyApp.Infrastructure]*
          </Include>
          <ExcludeByAttribute>
            Obsolete,GeneratedCodeAttribute,CompilerGeneratedAttribute,ExcludeFromCodeCoverage
          </ExcludeByAttribute>
          <SingleHit>false</SingleHit>
          <UseSourceLink>true</UseSourceLink>
          <IncludeTestAssembly>false</IncludeTestAssembly>
          <SkipAutoProps>true</SkipAutoProps>
          <DeterministicReport>true</DeterministicReport>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

Run with settings:

```bash
dotnet test --settings coverlet.runsettings
```

### Per-Project Coverage Thresholds

Add to the test project `.csproj`:

```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura</CoverletOutputFormat>
  <Threshold>80</Threshold>
  <ThresholdType>line,branch</ThresholdType>
  <ThresholdStat>total</ThresholdStat>
</PropertyGroup>
```

---

## CI Integration and Parallel Test Execution

### GitHub Actions Workflow

```yaml
name: .NET Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Restore dependencies
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Run unit tests
        run: >
          dotnet test
          --no-build
          --configuration Release
          --logger "trx;LogFileName=test-results.trx"
          --collect:"XPlat Code Coverage"
          --settings coverlet.runsettings
          --filter "Category!=Integration"

      - name: Run integration tests
        run: >
          dotnet test
          --no-build
          --configuration Release
          --logger "trx;LogFileName=integration-results.trx"
          --filter "Category=Integration"

      - name: Generate coverage report
        if: always()
        run: |
          dotnet tool install -g dotnet-reportgenerator-globaltool
          reportgenerator \
            -reports:"**/coverage.cobertura.xml" \
            -targetdir:"coveragereport" \
            -reporttypes:"Cobertura;TextSummary"
          cat coveragereport/Summary.txt

      - name: Upload coverage to Codecov
        if: always()
        uses: codecov/codecov-action@v4
        with:
          files: "**/coverage.cobertura.xml"
          fail_ci_if_error: false

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: "**/test-results.trx"
```

### Controlling Parallel Execution

xUnit runs test classes in parallel by default, but tests within a class run sequentially.

Disable parallelism for integration tests that share state by creating `xunit.runner.json`:

```json
{
  "$schema": "https://xunit.net/schema/current/xunit.runner.schema.json",
  "parallelizeAssembly": false,
  "parallelizeTestCollections": true,
  "maxParallelThreads": 0
}
```

Reference in `.csproj`:

```xml
<ItemGroup>
  <Content Include="xunit.runner.json" CopyToOutputDirectory="PreserveNewest" />
</ItemGroup>
```

For specific collections that must not run in parallel, use the same `[Collection]` attribute -- tests within the same collection run sequentially:

```csharp
[Collection("Sequential Database Tests")]
public class OrderMigrationTests { /* ... */ }

[Collection("Sequential Database Tests")]
public class CustomerMigrationTests { /* ... */ }
```

### Filtering Tests in CI

```bash
# Run only unit tests
dotnet test --filter "FullyQualifiedName~UnitTests"

# Run by trait
dotnet test --filter "Category=Smoke"

# Run specific class
dotnet test --filter "ClassName=OrderServiceTests"

# Exclude slow tests
dotnet test --filter "Category!=Slow"

# Combine filters
dotnet test --filter "Category=Integration&Priority=High"
```

---

## Best Practices

1. **Arrange-Act-Assert (AAA)**: Structure every test with clearly separated sections. One Act per test.

2. **One assertion concept per test**: A test should verify a single logical concept. Multiple `Assert` calls are fine if they verify facets of the same result.

3. **Test behavior, not implementation**: Focus on what the code does, not how. Avoid tightly coupling to internal details.

4. **Use meaningful test names**: The name should describe the scenario and expected outcome without needing to read the test body.

5. **Prefer `IAsyncLifetime` over constructor/dispose for async setup**: xUnit constructors cannot be async. Use `IAsyncLifetime` for any initialization that requires `await`.

6. **Keep integration tests isolated**: Each test should create its own data and not depend on state from other tests. Use transactions or database resets between tests.

7. **Use `CancellationToken` in async tests**: Pass `CancellationToken` through to prevent tests from hanging indefinitely.

8. **Prefer SQLite over EF Core In-Memory**: SQLite enforces foreign keys, supports transactions, and behaves much closer to production databases.

9. **Use test data builders**: Avoid constructing complex objects inline. Builders make tests readable and maintain a single point of change when domain objects evolve.

10. **Minimize mocking depth**: If you need to mock more than two levels deep, reconsider the design. Excessive mocking is a code smell pointing to tight coupling.

11. **Test edge cases and error paths**: Happy path coverage alone is insufficient. Test nulls, empty collections, boundary values, concurrency issues, and exception scenarios.

12. **Run tests in CI on every push**: Automated test execution catches regressions early. Separate unit and integration test stages for faster feedback.

13. **Set coverage thresholds**: Use coverlet thresholds to prevent coverage regression. Target 80%+ line and branch coverage for business-critical code.

14. **Use `TimeProvider` for time-dependent code**: .NET 8 introduced `TimeProvider` as an abstraction. Inject it and use `FakeTimeProvider` in tests instead of mocking `DateTime.UtcNow`.

---

## Anti-Patterns

1. **Testing implementation details**: Do not verify that a private method was called or that an internal data structure has a specific shape. Test the public contract.

2. **Shared mutable state between tests**: Tests that depend on execution order or mutate shared fixtures without resetting are fragile and non-deterministic.

3. **Overusing `[Fact(Skip = "...")]`**: Skipped tests rot. Fix or remove them. Skipped tests accumulate and give false confidence in coverage.

4. **God test fixtures**: A single fixture class used by dozens of test classes becomes impossible to maintain. Keep fixtures focused and purpose-specific.

5. **Asserting on exact exception messages**: Messages are not part of the public API and change frequently. Assert on exception type and relevant properties instead.

6. **Using `Thread.Sleep` in tests**: Use `Task.Delay` in async tests. Better yet, redesign time-dependent code to accept `TimeProvider` so tests can advance time explicitly.

7. **Ignoring test output**: Flaky tests, slow tests, and warnings in test output signal design problems. Address them promptly.

8. **Not disposing resources**: Failing to dispose `HttpClient`, `DbContext`, or `SqliteConnection` leads to resource leaks and flaky tests. Implement `IAsyncLifetime` or `IDisposable`.

9. **Testing frameworks instead of your code**: Do not test that EF Core can save and load entities. Test your repository logic, query filters, and business rules.

10. **Mocking what you don't own**: Do not mock `HttpClient`, `DbContext`, or third-party libraries directly. Wrap them behind interfaces you control, then mock those interfaces.

11. **Using `new HttpClient()` in tests**: Always obtain `HttpClient` from `WebApplicationFactory.CreateClient()` for integration tests. Creating clients manually bypasses the test server.

12. **Hardcoded magic numbers**: Use constants or builder defaults instead of unexplained literal values scattered through test code.

---

## Sources & References

- [xUnit.net Documentation - Getting Started with .NET](https://xunit.net/docs/getting-started/netcore/cmdline)
- [Microsoft - Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-8.0)
- [Microsoft - Testing EF Core Applications](https://learn.microsoft.com/en-us/ef/core/testing/)
- [Moq Quickstart - GitHub](https://github.com/devlooped/moq/wiki/Quickstart)
- [FluentAssertions Documentation](https://fluentassertions.com/introduction)
- [Coverlet - Cross-platform code coverage for .NET](https://github.com/coverlet-coverage/coverlet)
- [Microsoft - Unit testing best practices with .NET](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices)
- [Andrew Lock - Creating a custom WebApplicationFactory](https://andrewlock.net/exploring-dotnet-6-part-6-supporting-integration-tests-with-webapplicationfactory-in-dotnet-6/)
