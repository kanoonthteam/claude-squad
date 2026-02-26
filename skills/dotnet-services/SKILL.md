---
name: dotnet-services
description: C# .NET service architecture — dependency injection, service interfaces, repository pattern with EF Core, BackgroundService, IHostedService, IHttpClientFactory, Options pattern, Channel<T> producer-consumer, decorator pattern with DI
---

# .NET Services, Dependency Injection & Background Processing

Production-grade patterns for .NET 8 service architecture. Covers the built-in DI container, service registration strategies, interface segregation, repository and unit of work patterns with EF Core, background and hosted services, typed HTTP clients, the Options pattern, Channel-based producer-consumer pipelines, and the decorator pattern wired through DI.

## Table of Contents

1. [Built-in DI Container](#built-in-di-container)
2. [Service Registration Patterns](#service-registration-patterns)
3. [Interface Segregation for Services](#interface-segregation-for-services)
4. [Repository Pattern with EF Core](#repository-pattern-with-ef-core)
5. [Unit of Work Pattern](#unit-of-work-pattern)
6. [BackgroundService and IHostedService](#backgroundservice-and-ihostedservice)
7. [Timed Background Services](#timed-background-services)
8. [Queue-Based Background Processing](#queue-based-background-processing)
9. [Channel T for Producer-Consumer Patterns](#channel-t-for-producer-consumer-patterns)
10. [IHttpClientFactory and Typed HTTP Clients](#ihttpclientfactory-and-typed-http-clients)
11. [Options Pattern](#options-pattern)
12. [Service Lifetime Management and Disposal](#service-lifetime-management-and-disposal)
13. [Decorator Pattern with DI](#decorator-pattern-with-di)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)
16. [Sources & References](#sources--references)

---

## Built-in DI Container

The .NET built-in DI container (`Microsoft.Extensions.DependencyInjection`) supports three service lifetimes that dictate when instances are created and disposed.

### Service Lifetimes

| Lifetime | Method | Instance Created | Disposed |
|---|---|---|---|
| Transient | `AddTransient<T>` | Every time it is requested | When the scope that resolved it is disposed |
| Scoped | `AddScoped<T>` | Once per scope (HTTP request in ASP.NET Core) | At the end of the scope |
| Singleton | `AddSingleton<T>` | Once for the application lifetime | When the application shuts down |

### Lifetime Selection Rules

- **Transient** -- lightweight, stateless services. Safe by default but creates the most allocations.
- **Scoped** -- services that hold per-request state (DbContext, current-user context). The default choice for data-access services.
- **Singleton** -- services that are thread-safe and expensive to create (caches, configuration readers, IHttpClientFactory internally). Must be thread-safe because all requests share the same instance.

### Captive Dependency Problem

A scoped or transient service injected into a singleton is "captured" and effectively lives as a singleton, which causes data corruption and concurrency bugs. The framework detects this in development via `ValidateScopes`:

```
// In Program.cs the default WebApplicationBuilder already enables scope validation in Development.
// For non-web hosts, enable it explicitly:
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddSingleton<MySingleton>();
builder.Services.AddScoped<MyScopedDep>();
// At runtime in Development this throws InvalidOperationException when
// MySingleton tries to consume MyScopedDep.
```

Always enable `ValidateScopes` and `ValidateOnBuild` in development.

---

## Service Registration Patterns

### Basic Registration

```csharp
// Program.cs — .NET 8 minimal hosting
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

// --- Lifetime registrations ---
builder.Services.AddTransient<IEmailSender, SmtpEmailSender>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddSingleton<ICacheService, MemoryCacheService>();

// --- Keyed services (.NET 8+) ---
builder.Services.AddKeyedSingleton<INotificationChannel, SlackChannel>("slack");
builder.Services.AddKeyedSingleton<INotificationChannel, TeamsChannel>("teams");

// --- Open generics ---
builder.Services.AddScoped(typeof(IRepository<>), typeof(Repository<>));

// --- Factory registrations ---
builder.Services.AddScoped<IPaymentGateway>(sp =>
{
    var config = sp.GetRequiredService<IOptions<PaymentOptions>>().Value;
    return config.Provider switch
    {
        "stripe" => new StripeGateway(config.ApiKey),
        "paypal" => new PayPalGateway(config.ApiKey),
        _ => throw new InvalidOperationException($"Unknown provider: {config.Provider}")
    };
});

var app = builder.Build();
app.Run();
```

### Extension Method Modules

Group related registrations into extension methods so `Program.cs` stays clean:

```csharp
// ServiceCollectionExtensions.cs
namespace MyApp.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers all persistence services (DbContext, repositories, Unit of Work).
    /// </summary>
    public static IServiceCollection AddPersistence(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException("Connection string 'Default' not found.");

        services.AddDbContext<AppDbContext>(options =>
            options.UseNpgsql(connectionString, npgsql =>
            {
                npgsql.EnableRetryOnFailure(
                    maxRetryCount: 3,
                    maxRetryDelay: TimeSpan.FromSeconds(5),
                    errorCodesToAdd: null);
                npgsql.MigrationsHistoryTable("__ef_migrations", "public");
            }));

        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped(typeof(IRepository<>), typeof(Repository<>));
        services.AddScoped<IOrderRepository, OrderRepository>();
        services.AddScoped<IProductRepository, ProductRepository>();

        return services;
    }

    /// <summary>
    /// Registers application-layer services (use cases / handlers).
    /// </summary>
    public static IServiceCollection AddApplicationServices(this IServiceCollection services)
    {
        services.AddScoped<IOrderService, OrderService>();
        services.AddScoped<IInventoryService, InventoryService>();
        services.AddScoped<IPricingService, PricingService>();

        return services;
    }

    /// <summary>
    /// Registers all background / hosted services.
    /// </summary>
    public static IServiceCollection AddBackgroundServices(this IServiceCollection services)
    {
        services.AddHostedService<OrderProcessingWorker>();
        services.AddHostedService<CacheWarmupService>();
        services.AddHostedService<MetricsPublisherService>();

        return services;
    }
}
```

Then in `Program.cs`:

```csharp
builder.Services
    .AddPersistence(builder.Configuration)
    .AddApplicationServices()
    .AddBackgroundServices();
```

### Assembly Scanning with Scrutor

For large codebases, use Scrutor to scan assemblies and register services by convention:

```csharp
// Install: dotnet add package Scrutor
builder.Services.Scan(scan => scan
    .FromAssemblyOf<OrderService>()            // scan the assembly containing OrderService
        .AddClasses(classes => classes
            .InNamespaces("MyApp.Application.Services"))
        .AsImplementedInterfaces()
        .WithScopedLifetime()
    .FromAssemblyOf<OrderRepository>()
        .AddClasses(classes => classes
            .AssignableTo(typeof(IRepository<>)))
        .AsImplementedInterfaces()
        .WithScopedLifetime()
    .FromAssemblyOf<SlackNotifier>()
        .AddClasses(classes => classes
            .AssignableTo<INotificationChannel>())
        .AsImplementedInterfaces()
        .WithSingletonLifetime());
```

---

## Interface Segregation for Services

Prefer narrow interfaces over wide "god" interfaces. Each interface should represent a single capability:

```csharp
// BAD: one giant interface
public interface IUserService
{
    Task<User?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<User>> SearchAsync(string query, CancellationToken ct = default);
    Task CreateAsync(User user, CancellationToken ct = default);
    Task UpdateAsync(User user, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);
    Task SendWelcomeEmailAsync(int userId, CancellationToken ct = default);
    Task ResetPasswordAsync(int userId, CancellationToken ct = default);
    Task<string> GenerateAvatarUrlAsync(int userId, CancellationToken ct = default);
}

// GOOD: segregated interfaces
public interface IUserReader
{
    Task<User?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<User>> SearchAsync(string query, CancellationToken ct = default);
}

public interface IUserWriter
{
    Task CreateAsync(User user, CancellationToken ct = default);
    Task UpdateAsync(User user, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);
}

public interface IUserNotifier
{
    Task SendWelcomeEmailAsync(int userId, CancellationToken ct = default);
    Task ResetPasswordAsync(int userId, CancellationToken ct = default);
}

public interface IAvatarService
{
    Task<string> GenerateUrlAsync(int userId, CancellationToken ct = default);
}
```

A single class may implement multiple interfaces and be registered multiple times:

```csharp
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<IUserReader>(sp => sp.GetRequiredService<UserService>());
builder.Services.AddScoped<IUserWriter>(sp => sp.GetRequiredService<UserService>());
```

This avoids creating multiple instances while keeping injection sites narrow.

---

## Repository Pattern with EF Core

### Generic Repository

```csharp
// Domain/Interfaces/IRepository.cs
namespace MyApp.Domain.Interfaces;

public interface IRepository<T> where T : class
{
    Task<T?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<T>> FindAsync(
        Expression<Func<T, bool>> predicate,
        CancellationToken ct = default);
    void Add(T entity);
    void Update(T entity);
    void Remove(T entity);
}

// Infrastructure/Persistence/Repository.cs
namespace MyApp.Infrastructure.Persistence;

public class Repository<T>(AppDbContext context) : IRepository<T>
    where T : class
{
    protected readonly DbSet<T> DbSet = context.Set<T>();

    public async Task<T?> GetByIdAsync(int id, CancellationToken ct = default)
        => await DbSet.FindAsync([id], ct);

    public async Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default)
        => await DbSet.AsNoTracking().ToListAsync(ct);

    public async Task<IReadOnlyList<T>> FindAsync(
        Expression<Func<T, bool>> predicate,
        CancellationToken ct = default)
        => await DbSet.AsNoTracking().Where(predicate).ToListAsync(ct);

    public void Add(T entity) => DbSet.Add(entity);

    public void Update(T entity) => DbSet.Update(entity);

    public void Remove(T entity) => DbSet.Remove(entity);
}
```

### Specialised Repository

Extend the generic repository for aggregate-specific queries:

```csharp
// Domain/Interfaces/IOrderRepository.cs
public interface IOrderRepository : IRepository<Order>
{
    Task<Order?> GetWithItemsAsync(int orderId, CancellationToken ct = default);
    Task<IReadOnlyList<Order>> GetByCustomerAsync(
        int customerId,
        DateOnly from,
        DateOnly to,
        CancellationToken ct = default);
}

// Infrastructure/Persistence/OrderRepository.cs
public class OrderRepository(AppDbContext context)
    : Repository<Order>(context), IOrderRepository
{
    public async Task<Order?> GetWithItemsAsync(int orderId, CancellationToken ct = default)
        => await DbSet
            .Include(o => o.Items)
            .ThenInclude(i => i.Product)
            .AsSplitQuery()
            .FirstOrDefaultAsync(o => o.Id == orderId, ct);

    public async Task<IReadOnlyList<Order>> GetByCustomerAsync(
        int customerId,
        DateOnly from,
        DateOnly to,
        CancellationToken ct = default)
        => await DbSet
            .AsNoTracking()
            .Where(o => o.CustomerId == customerId
                     && o.OrderDate >= from
                     && o.OrderDate <= to)
            .OrderByDescending(o => o.OrderDate)
            .ToListAsync(ct);
}
```

---

## Unit of Work Pattern

The Unit of Work coordinates saving changes across multiple repositories in a single transaction.

```csharp
// Domain/Interfaces/IUnitOfWork.cs
namespace MyApp.Domain.Interfaces;

public interface IUnitOfWork : IDisposable
{
    IOrderRepository Orders { get; }
    IProductRepository Products { get; }
    IRepository<Customer> Customers { get; }

    Task<int> SaveChangesAsync(CancellationToken ct = default);
    Task BeginTransactionAsync(CancellationToken ct = default);
    Task CommitTransactionAsync(CancellationToken ct = default);
    Task RollbackTransactionAsync(CancellationToken ct = default);
}

// Infrastructure/Persistence/UnitOfWork.cs
namespace MyApp.Infrastructure.Persistence;

public sealed class UnitOfWork(
    AppDbContext context,
    IOrderRepository orders,
    IProductRepository products,
    IRepository<Customer> customers) : IUnitOfWork
{
    private IDbContextTransaction? _transaction;

    public IOrderRepository Orders => orders;
    public IProductRepository Products => products;
    public IRepository<Customer> Customers => customers;

    public async Task<int> SaveChangesAsync(CancellationToken ct = default)
        => await context.SaveChangesAsync(ct);

    public async Task BeginTransactionAsync(CancellationToken ct = default)
    {
        _transaction = await context.Database.BeginTransactionAsync(ct);
    }

    public async Task CommitTransactionAsync(CancellationToken ct = default)
    {
        if (_transaction is null)
            throw new InvalidOperationException("No active transaction to commit.");

        await context.SaveChangesAsync(ct);
        await _transaction.CommitAsync(ct);
    }

    public async Task RollbackTransactionAsync(CancellationToken ct = default)
    {
        if (_transaction is not null)
        {
            await _transaction.RollbackAsync(ct);
        }
    }

    public void Dispose()
    {
        _transaction?.Dispose();
        context.Dispose();
    }
}
```

Usage in an application service:

```csharp
public class PlaceOrderHandler(IUnitOfWork uow, ILogger<PlaceOrderHandler> logger)
{
    public async Task<int> HandleAsync(PlaceOrderCommand command, CancellationToken ct)
    {
        await uow.BeginTransactionAsync(ct);
        try
        {
            var product = await uow.Products.GetByIdAsync(command.ProductId, ct)
                ?? throw new NotFoundException($"Product {command.ProductId} not found.");

            product.DecreaseStock(command.Quantity);
            uow.Products.Update(product);

            var order = Order.Create(command.CustomerId, product, command.Quantity);
            uow.Orders.Add(order);

            await uow.CommitTransactionAsync(ct);
            logger.LogInformation("Order {OrderId} placed for customer {CustomerId}",
                order.Id, command.CustomerId);

            return order.Id;
        }
        catch
        {
            await uow.RollbackTransactionAsync(ct);
            throw;
        }
    }
}
```

---

## BackgroundService and IHostedService

### IHostedService

`IHostedService` is the low-level contract. It has two methods: `StartAsync` and `StopAsync`. Use it only when you need full control over the start/stop lifecycle.

### BackgroundService

`BackgroundService` is the abstract base class that implements `IHostedService` and provides an `ExecuteAsync` method for long-running work. Prefer it for most use cases.

```csharp
// Workers/OrderProcessingWorker.cs
namespace MyApp.Workers;

public sealed class OrderProcessingWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OrderProcessingWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("OrderProcessingWorker starting");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Create a scope because BackgroundService is a singleton,
                // and scoped services (DbContext, repositories) cannot be injected directly.
                using var scope = scopeFactory.CreateScope();
                var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();

                await ProcessPendingOrdersAsync(uow, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Graceful shutdown — do not log as error.
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing orders, retrying in 10s");
                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
        }

        logger.LogInformation("OrderProcessingWorker stopped");
    }

    private async Task ProcessPendingOrdersAsync(IUnitOfWork uow, CancellationToken ct)
    {
        var pending = await uow.Orders.FindAsync(o => o.Status == OrderStatus.Pending, ct);
        foreach (var order in pending)
        {
            order.MarkProcessing();
            uow.Orders.Update(order);
        }
        await uow.SaveChangesAsync(ct);
    }
}
```

Registration:

```csharp
builder.Services.AddHostedService<OrderProcessingWorker>();
```

### Key Rules for BackgroundService

- Always use `IServiceScopeFactory` to create scopes when consuming scoped services.
- Always respect the `CancellationToken` passed to `ExecuteAsync`.
- Catch `OperationCanceledException` during shutdown to exit cleanly.
- Never let an unhandled exception escape `ExecuteAsync` -- it will terminate the host in .NET 8.

---

## Timed Background Services

Use `PeriodicTimer` (introduced in .NET 6) instead of `Task.Delay` loops for accurate, drift-free intervals:

```csharp
// Workers/MetricsPublisherService.cs
namespace MyApp.Workers;

public sealed class MetricsPublisherService(
    IServiceScopeFactory scopeFactory,
    IOptions<MetricsOptions> options,
    ILogger<MetricsPublisherService> logger) : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(options.Value.IntervalSeconds);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Metrics publisher running every {Interval}", _interval);

        using var timer = new PeriodicTimer(_interval);

        // Tick immediately on first run, then on every timer tick.
        do
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var metricsCollector = scope.ServiceProvider
                    .GetRequiredService<IMetricsCollector>();
                await metricsCollector.PublishAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to publish metrics");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

public sealed class MetricsOptions
{
    public const string SectionName = "Metrics";
    public int IntervalSeconds { get; init; } = 60;
}
```

---

## Queue-Based Background Processing

### In-Memory Queue with Channel-Based Dispatch

A simple `BackgroundTaskQueue` using `Channel<T>`:

```csharp
// Services/IBackgroundTaskQueue.cs
namespace MyApp.Services;

public interface IBackgroundTaskQueue
{
    ValueTask EnqueueAsync(
        Func<IServiceProvider, CancellationToken, ValueTask> workItem,
        CancellationToken ct = default);

    ValueTask<Func<IServiceProvider, CancellationToken, ValueTask>> DequeueAsync(
        CancellationToken ct);
}

// Services/BackgroundTaskQueue.cs
public sealed class BackgroundTaskQueue : IBackgroundTaskQueue
{
    private readonly Channel<Func<IServiceProvider, CancellationToken, ValueTask>> _queue;

    public BackgroundTaskQueue(int capacity = 100)
    {
        var options = new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.Wait
        };
        _queue = Channel.CreateBounded<Func<IServiceProvider, CancellationToken, ValueTask>>(options);
    }

    public async ValueTask EnqueueAsync(
        Func<IServiceProvider, CancellationToken, ValueTask> workItem,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(workItem);
        await _queue.Writer.WriteAsync(workItem, ct);
    }

    public async ValueTask<Func<IServiceProvider, CancellationToken, ValueTask>> DequeueAsync(
        CancellationToken ct)
    {
        return await _queue.Reader.ReadAsync(ct);
    }
}
```

### Queue Processing Worker

```csharp
// Workers/QueueProcessingWorker.cs
namespace MyApp.Workers;

public sealed class QueueProcessingWorker(
    IBackgroundTaskQueue taskQueue,
    IServiceScopeFactory scopeFactory,
    ILogger<QueueProcessingWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Queue processing worker started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var workItem = await taskQueue.DequeueAsync(stoppingToken);

                using var scope = scopeFactory.CreateScope();
                await workItem(scope.ServiceProvider, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error executing queued work item");
            }
        }
    }
}
```

Registration and usage from a controller:

```csharp
// Registration
builder.Services.AddSingleton<IBackgroundTaskQueue, BackgroundTaskQueue>();
builder.Services.AddHostedService<QueueProcessingWorker>();

// Usage in a controller / minimal API handler
app.MapPost("/orders/{id}/invoice", async (
    int id,
    IBackgroundTaskQueue queue,
    CancellationToken ct) =>
{
    await queue.EnqueueAsync(async (sp, token) =>
    {
        var invoiceService = sp.GetRequiredService<IInvoiceService>();
        await invoiceService.GenerateAndEmailAsync(id, token);
    }, ct);

    return Results.Accepted();
});
```

---

## Channel T for Producer-Consumer Patterns

`System.Threading.Channels.Channel<T>` provides a high-performance, lock-free, async-ready producer-consumer primitive. Use it when the producer and consumer run in different services or at different speeds.

### Bounded vs Unbounded

| Type | When to Use |
|---|---|
| `Channel.CreateBounded<T>(n)` | Production workloads. Apply backpressure when the consumer falls behind. |
| `Channel.CreateUnbounded<T>()` | Only when you can guarantee the producer is not faster than the consumer, or memory is not a concern. |

### Typed Channel Pipeline

```csharp
// Domain/Events/OrderPlacedEvent.cs
namespace MyApp.Domain.Events;

public sealed record OrderPlacedEvent(int OrderId, int CustomerId, decimal Total);

// Services/OrderEventChannel.cs
namespace MyApp.Services;

public sealed class OrderEventChannel
{
    private readonly Channel<OrderPlacedEvent> _channel;

    public OrderEventChannel(int capacity = 500)
    {
        var options = new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = false,
            SingleWriter = false
        };
        _channel = Channel.CreateBounded<OrderPlacedEvent>(options);
    }

    public ChannelWriter<OrderPlacedEvent> Writer => _channel.Writer;
    public ChannelReader<OrderPlacedEvent> Reader => _channel.Reader;
}

// Workers/OrderEventConsumer.cs
namespace MyApp.Workers;

public sealed class OrderEventConsumer(
    OrderEventChannel channel,
    IServiceScopeFactory scopeFactory,
    ILogger<OrderEventConsumer> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var evt in channel.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var handler = scope.ServiceProvider.GetRequiredService<IOrderPlacedHandler>();
                await handler.HandleAsync(evt, stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to process OrderPlacedEvent {OrderId}", evt.OrderId);
            }
        }
    }
}
```

Registration:

```csharp
builder.Services.AddSingleton<OrderEventChannel>();
builder.Services.AddHostedService<OrderEventConsumer>();
```

Publishing from application code:

```csharp
public class OrderService(OrderEventChannel channel, IUnitOfWork uow)
{
    public async Task<int> PlaceOrderAsync(PlaceOrderCommand cmd, CancellationToken ct)
    {
        var order = Order.Create(cmd.CustomerId, cmd.ProductId, cmd.Quantity);
        uow.Orders.Add(order);
        await uow.SaveChangesAsync(ct);

        await channel.Writer.WriteAsync(
            new OrderPlacedEvent(order.Id, order.CustomerId, order.Total), ct);

        return order.Id;
    }
}
```

---

## IHttpClientFactory and Typed HTTP Clients

### Why IHttpClientFactory

Creating `HttpClient` instances manually leads to socket exhaustion and DNS caching issues. `IHttpClientFactory` manages the underlying `HttpMessageHandler` pool.

### Named Clients

```csharp
builder.Services.AddHttpClient("github", client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.Add("Accept", "application/vnd.github+json");
    client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
});
```

### Typed Clients (Preferred)

```csharp
// Services/GitHubClient.cs
namespace MyApp.Services;

public sealed class GitHubClient(HttpClient httpClient, ILogger<GitHubClient> logger)
{
    public async Task<GitHubRepo?> GetRepoAsync(
        string owner,
        string repo,
        CancellationToken ct = default)
    {
        logger.LogDebug("Fetching repo {Owner}/{Repo}", owner, repo);

        var response = await httpClient.GetAsync($"repos/{owner}/{repo}", ct);

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return null;

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<GitHubRepo>(ct);
    }
}

public sealed record GitHubRepo(
    int Id,
    string FullName,
    string Description,
    int StargazersCount);
```

Registration with Polly resilience:

```csharp
builder.Services
    .AddHttpClient<GitHubClient>(client =>
    {
        client.BaseAddress = new Uri("https://api.github.com/");
        client.DefaultRequestHeaders.Add("Accept", "application/vnd.github+json");
        client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
    })
    .AddStandardResilienceHandler(); // Microsoft.Extensions.Http.Resilience (.NET 8+)
```

`AddStandardResilienceHandler` provides retry, circuit breaker, and timeout out of the box. For custom resilience, use `AddResilienceHandler` with Polly 8:

```csharp
builder.Services
    .AddHttpClient<PaymentGatewayClient>(client =>
    {
        client.BaseAddress = new Uri("https://api.payments.example.com/");
        client.Timeout = TimeSpan.FromSeconds(30);
    })
    .AddResilienceHandler("payment-pipeline", pipeline =>
    {
        pipeline.AddRetry(new HttpRetryStrategyOptions
        {
            MaxRetryAttempts = 3,
            BackoffType = DelayBackoffType.Exponential,
            UseJitter = true,
            Delay = TimeSpan.FromMilliseconds(500)
        });
        pipeline.AddCircuitBreaker(new HttpCircuitBreakerStrategyOptions
        {
            SamplingDuration = TimeSpan.FromSeconds(30),
            FailureRatio = 0.5,
            MinimumThroughput = 10,
            BreakDuration = TimeSpan.FromSeconds(15)
        });
        pipeline.AddTimeout(TimeSpan.FromSeconds(10));
    });
```

---

## Options Pattern

The Options pattern binds configuration sections to strongly-typed classes. .NET provides three interfaces with different reloading behaviours.

### The Three Interfaces

| Interface | Lifetime | Reloads on Config Change | Use When |
|---|---|---|---|
| `IOptions<T>` | Singleton | No | Settings are fixed for the app lifetime |
| `IOptionsSnapshot<T>` | Scoped | Yes (per scope / request) | Settings may change and you want per-request consistency |
| `IOptionsMonitor<T>` | Singleton | Yes (immediately via `OnChange`) | Singletons that must react to live config changes |

### Configuration and Registration

```csharp
// Options/SmtpOptions.cs
namespace MyApp.Options;

public sealed class SmtpOptions
{
    public const string SectionName = "Smtp";

    [Required, Url]
    public string Host { get; init; } = string.Empty;

    [Range(1, 65535)]
    public int Port { get; init; } = 587;

    [Required, EmailAddress]
    public string FromAddress { get; init; } = string.Empty;

    public string? Username { get; init; }
    public string? Password { get; init; }
    public bool UseSsl { get; init; } = true;
}

// Registration in Program.cs
builder.Services
    .AddOptionsWithValidateOnStart<SmtpOptions>()
    .BindConfiguration(SmtpOptions.SectionName)
    .ValidateDataAnnotations();
```

`AddOptionsWithValidateOnStart` eagerly validates on application start so misconfigurations fail fast instead of at the first request.

### Consuming Options

```csharp
// In a scoped service -- use IOptionsSnapshot for per-request reload
public class EmailSender(
    IOptionsSnapshot<SmtpOptions> options,
    ILogger<EmailSender> logger) : IEmailSender
{
    public async Task SendAsync(string to, string subject, string body, CancellationToken ct)
    {
        var smtp = options.Value;
        logger.LogDebug("Sending email via {Host}:{Port}", smtp.Host, smtp.Port);
        // ... use SmtpClient or MailKit
    }
}

// In a singleton -- use IOptionsMonitor for live updates
public class CacheWarmupService(
    IOptionsMonitor<CacheOptions> optionsMonitor,
    ILogger<CacheWarmupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        optionsMonitor.OnChange(newOptions =>
            logger.LogInformation("Cache options reloaded: TTL={Ttl}", newOptions.TtlMinutes));

        while (!stoppingToken.IsCancellationRequested)
        {
            var ttl = TimeSpan.FromMinutes(optionsMonitor.CurrentValue.TtlMinutes);
            // ... warm cache
            await Task.Delay(ttl, stoppingToken);
        }
    }
}
```

### Named Options

Use named options when you have multiple instances of the same options type:

```csharp
builder.Services.Configure<ApiClientOptions>("github", builder.Configuration.GetSection("Clients:GitHub"));
builder.Services.Configure<ApiClientOptions>("jira", builder.Configuration.GetSection("Clients:Jira"));

// Consume with IOptionsSnapshot<T>.Get(name)
public class MultiApiClient(IOptionsSnapshot<ApiClientOptions> optionsSnapshot)
{
    public ApiClientOptions GitHub => optionsSnapshot.Get("github");
    public ApiClientOptions Jira => optionsSnapshot.Get("jira");
}
```

---

## Service Lifetime Management and Disposal

### Disposal Rules

- The DI container automatically disposes any registered service that implements `IDisposable` or `IAsyncDisposable`.
- Services resolved from a scope are disposed when the scope is disposed.
- Singletons are disposed when the application host shuts down.

### IAsyncDisposable

Prefer `IAsyncDisposable` for services that hold async resources:

```csharp
public sealed class DatabaseConnectionPool : IDatabaseConnectionPool, IAsyncDisposable
{
    private readonly SemaphoreSlim _semaphore = new(maxCount: 50);
    private readonly ConcurrentBag<NpgsqlConnection> _connections = [];
    private bool _disposed;

    public async ValueTask<NpgsqlConnection> AcquireAsync(CancellationToken ct)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _semaphore.WaitAsync(ct);

        if (_connections.TryTake(out var existing))
            return existing;

        var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        return conn;
    }

    public void Release(NpgsqlConnection connection)
    {
        _connections.Add(connection);
        _semaphore.Release();
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;

        while (_connections.TryTake(out var conn))
        {
            await conn.DisposeAsync();
        }
        _semaphore.Dispose();
    }
}
```

### Factory-Registered Instances

When registering via a factory (`AddSingleton<T>(sp => ...)`) the container manages disposal only if the returned object implements `IDisposable`/`IAsyncDisposable`. If you register an existing instance with `AddSingleton<T>(instance)`, the container does NOT dispose it -- you must manage its lifetime yourself.

```csharp
// Container-managed: the factory result is disposed on shutdown.
builder.Services.AddSingleton<ICacheClient>(sp =>
    new RedisCacheClient(sp.GetRequiredService<IOptions<RedisOptions>>().Value.ConnectionString));

// NOT container-managed: you own the lifetime.
var sharedClient = new RedisCacheClient("localhost:6379");
builder.Services.AddSingleton<ICacheClient>(sharedClient);
// You must dispose sharedClient yourself when the app shuts down.
```

---

## Decorator Pattern with DI

The decorator pattern wraps an existing service to add cross-cutting concerns (logging, caching, retry, metrics) without modifying the original implementation.

### Manual Decorator Registration

```csharp
// Domain/Interfaces/IProductService.cs
public interface IProductService
{
    Task<Product?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default);
}

// Application/Services/ProductService.cs
public sealed class ProductService(IProductRepository repository) : IProductService
{
    public async Task<Product?> GetByIdAsync(int id, CancellationToken ct = default)
        => await repository.GetByIdAsync(id, ct);

    public async Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default)
        => await repository.GetAllAsync(ct);
}

// Infrastructure/Decorators/CachingProductService.cs
public sealed class CachingProductService(
    IProductService inner,
    IDistributedCache cache,
    ILogger<CachingProductService> logger) : IProductService
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(5);

    public async Task<Product?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        var cacheKey = $"product:{id}";
        var cached = await cache.GetStringAsync(cacheKey, ct);

        if (cached is not null)
        {
            logger.LogDebug("Cache hit for {CacheKey}", cacheKey);
            return JsonSerializer.Deserialize<Product>(cached);
        }

        var product = await inner.GetByIdAsync(id, ct);

        if (product is not null)
        {
            await cache.SetStringAsync(
                cacheKey,
                JsonSerializer.Serialize(product),
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = CacheDuration },
                ct);
        }

        return product;
    }

    public async Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default)
        => await inner.GetAllAsync(ct); // skip cache for list queries
}

// Infrastructure/Decorators/LoggingProductService.cs
public sealed class LoggingProductService(
    IProductService inner,
    ILogger<LoggingProductService> logger) : IProductService
{
    public async Task<Product?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        logger.LogInformation("Getting product {ProductId}", id);
        var sw = Stopwatch.StartNew();
        var result = await inner.GetByIdAsync(id, ct);
        sw.Stop();
        logger.LogInformation("Got product {ProductId} in {Elapsed}ms (found={Found})",
            id, sw.ElapsedMilliseconds, result is not null);
        return result;
    }

    public async Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default)
    {
        logger.LogInformation("Getting all products");
        var result = await inner.GetAllAsync(ct);
        logger.LogInformation("Retrieved {Count} products", result.Count);
        return result;
    }
}
```

### Registration: Manual Chaining

```csharp
// The outermost decorator is resolved by consumers.
// Chain: LoggingProductService -> CachingProductService -> ProductService
builder.Services.AddScoped<ProductService>();
builder.Services.AddScoped<IProductService>(sp =>
{
    var inner = sp.GetRequiredService<ProductService>();
    var cache = sp.GetRequiredService<IDistributedCache>();
    var cacheLogger = sp.GetRequiredService<ILogger<CachingProductService>>();
    var cached = new CachingProductService(inner, cache, cacheLogger);

    var outerLogger = sp.GetRequiredService<ILogger<LoggingProductService>>();
    return new LoggingProductService(cached, outerLogger);
});
```

### Registration: Scrutor Decoration

Scrutor simplifies decorator chaining:

```csharp
builder.Services.AddScoped<IProductService, ProductService>();
builder.Services.Decorate<IProductService, CachingProductService>();
builder.Services.Decorate<IProductService, LoggingProductService>();
// Resolution order: LoggingProductService -> CachingProductService -> ProductService
```

Each `Decorate` call wraps the previous registration. The last decorator registered is the outermost layer.

---

## Best Practices

### DI Registration

1. **Use extension methods to organise registrations** -- group by layer (persistence, application, infrastructure) to keep `Program.cs` under 50 lines.
2. **Prefer constructor injection** -- avoid `IServiceProvider` as a service locator. The only exception is factory lambdas in registration code.
3. **Use keyed services for multi-implementation scenarios** -- .NET 8's `[FromKeyedServices("name")]` attribute is cleaner than named registrations with manual resolution.
4. **Enable `ValidateOnBuild`** -- catches missing registrations at startup, not at runtime.
5. **Use `AddOptionsWithValidateOnStart`** -- validates configuration objects eagerly rather than on first access.

### Repository Pattern

6. **Keep the generic repository thin** -- it should only have CRUD. Aggregate-specific queries belong in specialised repository interfaces.
7. **Use `AsNoTracking()` for read-only queries** -- reduces memory allocation and improves performance.
8. **Use `AsSplitQuery()` for multi-level includes** -- avoids cartesian explosion in queries with multiple `Include` calls.
9. **Let the Unit of Work own the transaction boundary** -- individual repositories should not call `SaveChanges`.

### Background Services

10. **Always create scopes for scoped services** -- `BackgroundService` is a singleton; inject `IServiceScopeFactory` and create a scope per unit of work.
11. **Use `PeriodicTimer` over `Task.Delay`** -- it compensates for execution time, giving accurate intervals without drift.
12. **Use `Channel<T>` with bounded capacity** -- unbounded channels can cause unbounded memory growth under load.
13. **Handle `OperationCanceledException` gracefully** -- check `stoppingToken.IsCancellationRequested` and exit the loop cleanly.
14. **Use `stoppingToken` on every async call** -- propagate the cancellation token to all I/O operations inside `ExecuteAsync`.

### HTTP Clients

15. **Always use `IHttpClientFactory`** -- never create `new HttpClient()` directly in service code.
16. **Prefer typed clients over named clients** -- typed clients enforce a single responsibility per HTTP dependency.
17. **Add resilience policies** -- use `AddStandardResilienceHandler()` or custom `AddResilienceHandler()` for retries and circuit breakers.

### Options Pattern

18. **Validate options on start** -- use `ValidateDataAnnotations()` and `ValidateOnStart()` so bad config fails fast.
19. **Use `IOptionsMonitor<T>` in singletons** -- `IOptionsSnapshot<T>` is scoped and cannot be injected into singletons.
20. **Avoid injecting `IConfiguration` directly** -- bind sections to typed options for compile-time safety and validation.

---

## Anti-Patterns

### Captive Dependency

```csharp
// WRONG: Scoped service injected into a singleton.
// The DbContext will be reused across all requests, causing concurrency bugs.
public class MySingleton(AppDbContext context) { }
builder.Services.AddSingleton<MySingleton>();
builder.Services.AddDbContext<AppDbContext>(); // Scoped by default

// FIX: Use IServiceScopeFactory
public class MySingleton(IServiceScopeFactory scopeFactory)
{
    public async Task DoWorkAsync(CancellationToken ct)
    {
        using var scope = scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        // safe: context is scoped to this unit of work
    }
}
```

### Service Locator

```csharp
// WRONG: Resolving services via IServiceProvider in business logic.
public class OrderService(IServiceProvider provider)
{
    public async Task PlaceAsync()
    {
        var repo = provider.GetRequiredService<IOrderRepository>(); // service locator
    }
}

// FIX: Inject the dependency directly.
public class OrderService(IOrderRepository repository)
{
    public async Task PlaceAsync()
    {
        // use repository directly
    }
}
```

### Leaking DbContext Across Threads

```csharp
// WRONG: Passing a scoped DbContext into a background thread.
app.MapPost("/orders", async (AppDbContext context) =>
{
    _ = Task.Run(async () =>
    {
        // DbContext is NOT thread-safe. This will corrupt state.
        var orders = await context.Orders.ToListAsync();
    });
    return Results.Ok();
});

// FIX: Enqueue work via IBackgroundTaskQueue, resolve a new scope in the worker.
```

### Swallowing Cancellation

```csharp
// WRONG: Catching OperationCanceledException and continuing.
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (true) // never stops
    {
        try
        {
            await DoWorkAsync(stoppingToken);
        }
        catch (Exception) // swallows OperationCanceledException
        {
            await Task.Delay(5000); // also ignores stoppingToken
        }
    }
}

// FIX: Re-throw or break on cancellation.
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        try
        {
            await DoWorkAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            break; // graceful shutdown
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Work failed");
            await Task.Delay(5000, stoppingToken);
        }
    }
}
```

### Unbounded Channel Without Backpressure

```csharp
// WRONG: Unbounded channel in production -- memory can grow without limit.
var channel = Channel.CreateUnbounded<WorkItem>();

// FIX: Use bounded channel with explicit backpressure strategy.
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(1000)
{
    FullMode = BoundedChannelFullMode.Wait // or DropOldest depending on use case
});
```

### Disposing IHttpClientFactory-Managed Clients

```csharp
// WRONG: Disposing the HttpClient from a typed client.
public class MyApiClient(HttpClient client) : IDisposable
{
    public void Dispose() => client.Dispose(); // breaks the handler pool
}

// FIX: Never dispose HttpClient instances managed by IHttpClientFactory.
// The factory manages the handler lifetime automatically.
```

### Registering a Concrete Instance and Expecting Disposal

```csharp
// WRONG: Registering an existing instance -- container will NOT dispose it.
var client = new ExpensiveClient();
builder.Services.AddSingleton(client);
// client.Dispose() is never called.

// FIX: Use the factory overload so the container owns the instance.
builder.Services.AddSingleton<IExpensiveClient>(sp => new ExpensiveClient());
```

---

## Sources & References

- [Dependency injection in ASP.NET Core -- Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection)
- [Background tasks with hosted services in ASP.NET Core -- Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services)
- [Make HTTP requests using IHttpClientFactory in ASP.NET Core -- Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests)
- [Options pattern in ASP.NET Core -- Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/options)
- [System.Threading.Channels -- .NET API Reference](https://learn.microsoft.com/en-us/dotnet/api/system.threading.channels)
- [Implementing the Repository and Unit of Work Patterns -- Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/mvc/overview/older-versions/getting-started-with-ef-5-using-mvc-4/implementing-the-repository-and-unit-of-work-patterns-in-an-asp-net-mvc-application)
- [Scrutor -- GitHub Repository](https://github.com/khellang/Scrutor)
- [Build resilient HTTP apps with Microsoft.Extensions.Http.Resilience -- Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience)
