---
name: dotnet-logging
description: >
  Comprehensive guide to structured logging in .NET 8 / C# 12 applications using Serilog.
  Covers sink configuration (Console, File, Seq, Elasticsearch, Application Insights),
  log enrichment, correlation IDs, request tracing middleware, destructuring policies,
  performance best practices, sensitive data filtering, and appsettings.json configuration.
---

# .NET Structured Logging with Serilog

## Table of Contents

1. [Overview](#overview)
2. [Serilog Setup in ASP.NET Core 8](#serilog-setup-in-aspnet-core-8)
   - [Package Installation](#package-installation)
   - [Bootstrap Logger and Host Configuration](#bootstrap-logger-and-host-configuration)
3. [Structured Logging Concepts](#structured-logging-concepts)
   - [Message Templates](#message-templates)
   - [Semantic Properties](#semantic-properties)
4. [Sinks Configuration](#sinks-configuration)
   - [Console Sink](#console-sink)
   - [File Sink](#file-sink)
   - [Seq Sink](#seq-sink)
   - [Elasticsearch Sink](#elasticsearch-sink)
   - [Application Insights Sink](#application-insights-sink)
5. [Log Enrichment](#log-enrichment)
   - [Built-in Enrichers](#built-in-enrichers)
   - [Custom Enrichers](#custom-enrichers)
   - [Enrich.FromLogContext](#enrichfromlogcontext)
6. [Correlation IDs and Request Tracing](#correlation-ids-and-request-tracing)
   - [Correlation ID Middleware](#correlation-id-middleware)
   - [Propagating Correlation IDs to Downstream Services](#propagating-correlation-ids-to-downstream-services)
7. [Log Levels and Filtering](#log-levels-and-filtering)
   - [MinimumLevel Configuration](#minimumlevel-configuration)
   - [Override for Specific Namespaces](#override-for-specific-namespaces)
   - [Dynamic Level Switching](#dynamic-level-switching)
8. [Destructuring Policies for Complex Objects](#destructuring-policies-for-complex-objects)
   - [The @ Destructuring Operator](#the--destructuring-operator)
   - [Custom Destructuring Policies](#custom-destructuring-policies)
9. [Performance Considerations](#performance-considerations)
   - [Using ILogger of T](#using-ilogger-of-t)
   - [Avoiding String Interpolation](#avoiding-string-interpolation)
   - [Source Generators for High-Performance Logging](#source-generators-for-high-performance-logging)
   - [Conditional Logging Checks](#conditional-logging-checks)
10. [Diagnostic Context](#diagnostic-context)
    - [LogContext.PushProperty](#logcontextpushproperty)
    - [Scoped Diagnostic Context](#scoped-diagnostic-context)
11. [Configuration via appsettings.json](#configuration-via-appsettingsjson)
    - [Full Configuration Example](#full-configuration-example)
    - [Environment-Specific Overrides](#environment-specific-overrides)
12. [Log Aggregation and Searching Patterns](#log-aggregation-and-searching-patterns)
    - [Structured Query Patterns](#structured-query-patterns)
    - [Dashboard and Alerting](#dashboard-and-alerting)
13. [Health Check Logging](#health-check-logging)
14. [Sensitive Data Filtering](#sensitive-data-filtering)
    - [Destructure.ByTransforming](#destructurebytransforming)
    - [Custom Masking Enricher](#custom-masking-enricher)
15. [Best Practices](#best-practices)
16. [Anti-Patterns](#anti-patterns)
17. [Sources & References](#sources--references)

---

## Overview

Structured logging replaces free-form text log messages with machine-readable events composed
of named properties. Instead of interpolating values into a string, structured logging
captures both the message template and the individual property values, enabling powerful
querying, filtering, and aggregation in downstream log stores.

Serilog is the dominant structured logging library in the .NET ecosystem. It integrates
seamlessly with the `Microsoft.Extensions.Logging` abstraction, allowing library authors to
log through `ILogger<T>` while application authors control the sink pipeline, enrichment,
filtering, and formatting.

This skill document targets ASP.NET Core 8 with C# 12 and nullable reference types enabled.
All examples assume `<Nullable>enable</Nullable>` and `<ImplicitUsings>enable</ImplicitUsings>`
in the project file.

---

## Serilog Setup in ASP.NET Core 8

### Package Installation

The following NuGet packages form the foundation of a Serilog-based logging pipeline:

```
dotnet add package Serilog.AspNetCore
dotnet add package Serilog.Sinks.Console
dotnet add package Serilog.Sinks.File
dotnet add package Serilog.Sinks.Seq
dotnet add package Serilog.Enrichers.Environment
dotnet add package Serilog.Enrichers.Thread
dotnet add package Serilog.Enrichers.Process
dotnet add package Serilog.Expressions
dotnet add package Serilog.Settings.Configuration
```

`Serilog.AspNetCore` pulls in `Serilog.Extensions.Hosting` which provides the
`UseSerilog()` extension method on `IHostBuilder`, and also includes the
`SerilogRequestLogging` middleware for HTTP request/response logging.

### Bootstrap Logger and Host Configuration

Serilog should be configured as early as possible so that startup errors are captured.
The recommended pattern uses a two-phase initialization: a bootstrap logger that captures
any errors during host building, and the final logger configured from the host's
configuration and DI container.

```csharp
// Program.cs — ASP.NET Core 8 minimal hosting with Serilog two-phase init

using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;

// Phase 1: Bootstrap logger — captures startup errors before the host is built.
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Information)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting web application");

    WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

    // Phase 2: Replace the bootstrap logger with the final configuration.
    builder.Host.UseSerilog((context, services, configuration) =>
    {
        configuration
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Enrich.WithMachineName()
            .Enrich.WithThreadId()
            .Enrich.WithProperty("Application", "MyService")
            .WriteTo.Console(new RenderedCompactJsonFormatter())
            .WriteTo.File(
                path: "logs/myservice-.log",
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 30,
                fileSizeLimitBytes: 100_000_000,
                shared: true,
                flushToDiskInterval: TimeSpan.FromSeconds(1))
            .WriteTo.Seq("http://localhost:5341");
    });

    // Register services
    builder.Services.AddControllers();
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen();
    builder.Services.AddHealthChecks();

    WebApplication app = builder.Build();

    // Serilog request logging replaces the default Microsoft request logging.
    // It produces a single log event per request with timing, status, and path.
    app.UseSerilogRequestLogging(options =>
    {
        options.MessageTemplate =
            "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";

        // Attach additional properties to the request completion event.
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            diagnosticContext.Set("RequestHost", httpContext.Request.Host.Value);
            diagnosticContext.Set("UserAgent",
                httpContext.Request.Headers.UserAgent.ToString());
        };

        // Do not log health-check endpoints at Information level.
        options.GetLevel = (httpContext, elapsed, ex) =>
        {
            if (httpContext.Request.Path.StartsWithSegments("/healthz"))
                return LogEventLevel.Verbose;

            return ex is not null || httpContext.Response.StatusCode >= 500
                ? LogEventLevel.Error
                : LogEventLevel.Information;
        };
    });

    app.UseHttpsRedirection();
    app.UseAuthorization();
    app.MapControllers();
    app.MapHealthChecks("/healthz");

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
```

Key points in this setup:

- `CreateBootstrapLogger()` provides a temporary logger that Serilog replaces once the
  host is fully built.
- `UseSerilog()` replaces the default `Microsoft.Extensions.Logging` providers, so all
  `ILogger<T>` calls flow through Serilog.
- `ReadFrom.Configuration(context.Configuration)` enables JSON-based configuration in
  `appsettings.json`, which supports runtime changes.
- `ReadFrom.Services(services)` allows sinks and enrichers to resolve services from DI.
- The `finally` block ensures all buffered log events are flushed before process exit.

---

## Structured Logging Concepts

### Message Templates

Serilog message templates use named placeholders enclosed in braces. These placeholders are
not positional format strings; they are named properties that become first-class fields in
the structured log event.

```
Log.Information("Order {OrderId} placed by {CustomerId} for {Amount:C}", orderId, customerId, amount);
```

This produces a log event with three properties: `OrderId`, `CustomerId`, and `Amount`.
The `:C` format specifier applies only to the rendered text output; the underlying property
retains its original type.

Rules for message templates:

- Property names should be PascalCase to follow .NET conventions.
- Use `{@Property}` to destructure an object into its constituent properties.
- Use `{$Property}` to stringify an object (call `.ToString()`).
- Do not embed logic or method calls inside placeholders.
- The number of placeholders must match the number of arguments.

### Semantic Properties

Properties captured through message templates are semantic: they carry type information and
can be queried structurally. For example, in Seq you can write:

```
OrderId = 42 and Amount > 100
```

This is fundamentally different from searching a plain-text log for the substring "42".
Structured properties enable precise filtering without false positives from coincidental
string matches.

---

## Sinks Configuration

Sinks determine where log events are delivered. Serilog supports a rich ecosystem of sinks,
and multiple sinks can be active simultaneously.

### Console Sink

The console sink is essential for local development and container environments where stdout
is collected by an orchestrator (Docker, Kubernetes).

For production containers, use `CompactJsonFormatter` or `RenderedCompactJsonFormatter` so
that each log line is a single JSON object parseable by log collectors:

```csharp
.WriteTo.Console(new RenderedCompactJsonFormatter())
```

For local development, the default colored text output is more readable:

```csharp
.WriteTo.Console(
    outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
```

### File Sink

The file sink writes to local disk with optional rolling by time interval or file size:

```csharp
.WriteTo.File(
    path: "logs/app-.log",
    rollingInterval: RollingInterval.Day,
    retainedFileCountLimit: 14,
    fileSizeLimitBytes: 50_000_000,
    rollOnFileSizeLimit: true,
    shared: true,
    flushToDiskInterval: TimeSpan.FromSeconds(2),
    formatter: new CompactJsonFormatter())
```

Parameters explained:

- `rollingInterval`: Creates a new file each day (appends the date to the filename).
- `retainedFileCountLimit`: Automatically deletes old log files.
- `fileSizeLimitBytes`: Caps individual file size.
- `rollOnFileSizeLimit`: Creates a new segment when the size limit is reached.
- `shared`: Allows multiple processes to write to the same file.
- `flushToDiskInterval`: Periodic flush for durability.

### Seq Sink

Seq is a purpose-built structured log server with a powerful query language. It is the
best option for teams that want a self-hosted structured log search UI:

```csharp
.WriteTo.Seq(
    serverUrl: "http://seq.internal:5341",
    apiKey: "your-api-key",
    batchPostingLimit: 50,
    period: TimeSpan.FromSeconds(2),
    restrictedToMinimumLevel: LogEventLevel.Debug)
```

Seq accepts events over HTTP and stores them in a compact indexed format. Its query
language allows filtering by any property, computing aggregates, and building dashboards.

### Elasticsearch Sink

For teams running the ELK stack (Elasticsearch, Logstash, Kibana):

```
dotnet add package Serilog.Sinks.Elasticsearch
```

```csharp
.WriteTo.Elasticsearch(new ElasticsearchSinkOptions(new Uri("http://elk:9200"))
{
    IndexFormat = "myservice-{0:yyyy.MM.dd}",
    AutoRegisterTemplate = true,
    AutoRegisterTemplateVersion = AutoRegisterTemplateVersion.ESv7,
    NumberOfShards = 2,
    NumberOfReplicas = 1,
    BatchAction = ElasticOpType.Create,
    ModifyConnectionSettings = conn => conn.BasicAuthentication("user", "pass")
})
```

The sink batches events and posts them to Elasticsearch using the bulk API. The
`IndexFormat` creates date-based indices for efficient lifecycle management.

### Application Insights Sink

For Azure-hosted applications, Application Insights provides integrated logging, tracing,
and metrics:

```
dotnet add package Serilog.Sinks.ApplicationInsights
```

```csharp
.WriteTo.ApplicationInsights(
    services.GetRequiredService<TelemetryConfiguration>(),
    TelemetryConverter.Traces)
```

Because this sink requires the `TelemetryConfiguration` from DI, it must be configured
inside the `UseSerilog` callback that receives the `services` parameter. The
`TelemetryConverter.Traces` converter maps Serilog events to Application Insights trace
telemetry, preserving all structured properties as custom dimensions.

---

## Log Enrichment

Enrichers add contextual properties to every log event passing through the pipeline.

### Built-in Enrichers

```csharp
.Enrich.WithMachineName()         // Serilog.Enrichers.Environment
.Enrich.WithEnvironmentName()     // Serilog.Enrichers.Environment
.Enrich.WithThreadId()            // Serilog.Enrichers.Thread
.Enrich.WithProcessId()           // Serilog.Enrichers.Process
.Enrich.WithProcessName()         // Serilog.Enrichers.Process
.Enrich.WithProperty("Service", "OrderApi")  // Static property
```

These enrichers add properties like `MachineName`, `ThreadId`, and `ProcessId` to every
event, which is invaluable when searching logs from multiple instances behind a load
balancer.

### Custom Enrichers

A custom enricher implements `ILogEventEnricher`:

```csharp
// Enrichers/OperationIdEnricher.cs

using Serilog.Core;
using Serilog.Events;
using System.Diagnostics;

namespace MyService.Enrichers;

/// <summary>
/// Enriches log events with the current Activity's trace ID, linking Serilog events
/// to distributed traces from OpenTelemetry or Application Insights.
/// </summary>
public sealed class ActivityTraceEnricher : ILogEventEnricher
{
    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        Activity? activity = Activity.Current;
        if (activity is null)
            return;

        logEvent.AddPropertyIfAbsent(
            propertyFactory.CreateProperty("TraceId", activity.TraceId.ToString()));
        logEvent.AddPropertyIfAbsent(
            propertyFactory.CreateProperty("SpanId", activity.SpanId.ToString()));
        logEvent.AddPropertyIfAbsent(
            propertyFactory.CreateProperty("ParentSpanId", activity.ParentSpanId.ToString()));
    }
}
```

Register the enricher in the pipeline:

```csharp
.Enrich.With<ActivityTraceEnricher>()
```

### Enrich.FromLogContext

`Enrich.FromLogContext()` enables the ambient `LogContext` — a stack-based mechanism for
attaching properties to all events emitted within a scope. This is the foundation for
correlation IDs, user identity, and request-scoped metadata.

```csharp
using (LogContext.PushProperty("OrderId", orderId))
{
    // Every log event within this block will carry the OrderId property.
    _logger.LogInformation("Processing order");
    _logger.LogInformation("Validating payment");
    _logger.LogInformation("Order confirmed");
}
```

---

## Correlation IDs and Request Tracing

Correlation IDs link all log events belonging to a single logical operation, typically an
HTTP request, across service boundaries. This is essential for debugging in distributed
systems.

### Correlation ID Middleware

The following middleware extracts or generates a correlation ID for each request and pushes
it into the Serilog `LogContext`:

```csharp
// Middleware/CorrelationIdMiddleware.cs

using Serilog.Context;

namespace MyService.Middleware;

/// <summary>
/// Extracts or generates a correlation ID for each HTTP request and enriches
/// the Serilog LogContext so that all log events within the request carry the ID.
/// Also sets the correlation ID on the response for downstream tracing.
/// </summary>
public sealed class CorrelationIdMiddleware
{
    private const string CorrelationIdHeader = "X-Correlation-ID";
    private readonly RequestDelegate _next;

    public CorrelationIdMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        string correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault()
            ?? Guid.NewGuid().ToString("D");

        // Store in HttpContext.Items for access by other middleware/services.
        context.Items["CorrelationId"] = correlationId;

        // Set on the response so the caller can trace the request.
        context.Response.OnStarting(() =>
        {
            context.Response.Headers.TryAdd(CorrelationIdHeader, correlationId);
            return Task.CompletedTask;
        });

        // Push into Serilog's LogContext so every log event in this request scope
        // automatically carries the CorrelationId property.
        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            await _next(context);
        }
    }
}

// Extension method for clean registration in Program.cs
public static class CorrelationIdMiddlewareExtensions
{
    public static IApplicationBuilder UseCorrelationId(this IApplicationBuilder builder)
    {
        return builder.UseMiddleware<CorrelationIdMiddleware>();
    }
}
```

Register the middleware before `UseSerilogRequestLogging()` so that the correlation ID is
available when the request completion event is logged:

```csharp
app.UseCorrelationId();
app.UseSerilogRequestLogging();
```

### Propagating Correlation IDs to Downstream Services

When calling other services via `HttpClient`, propagate the correlation ID using a
`DelegatingHandler`:

```csharp
// Handlers/CorrelationIdDelegatingHandler.cs

namespace MyService.Handlers;

/// <summary>
/// Propagates the correlation ID from the current HTTP context to outgoing
/// HttpClient requests, maintaining trace continuity across service boundaries.
/// </summary>
public sealed class CorrelationIdDelegatingHandler : DelegatingHandler
{
    private const string CorrelationIdHeader = "X-Correlation-ID";
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CorrelationIdDelegatingHandler(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        if (_httpContextAccessor.HttpContext?.Items["CorrelationId"] is string correlationId)
        {
            request.Headers.TryAddWithoutValidation(CorrelationIdHeader, correlationId);
        }

        return base.SendAsync(request, cancellationToken);
    }
}
```

Register with `IHttpClientFactory`:

```csharp
builder.Services.AddHttpContextAccessor();
builder.Services.AddTransient<CorrelationIdDelegatingHandler>();

builder.Services.AddHttpClient("DownstreamApi", client =>
{
    client.BaseAddress = new Uri("https://api.downstream.internal");
})
.AddHttpMessageHandler<CorrelationIdDelegatingHandler>();
```

---

## Log Levels and Filtering

Serilog supports the standard log levels in ascending order of severity:
`Verbose`, `Debug`, `Information`, `Warning`, `Error`, `Fatal`.

### MinimumLevel Configuration

```csharp
.MinimumLevel.Information()
.MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
.MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
.MinimumLevel.Override("System", LogEventLevel.Warning)
.MinimumLevel.Override("Microsoft.EntityFrameworkCore.Database.Command", LogEventLevel.Warning)
```

The `Override` method applies a different minimum level to events from a specific source
context (namespace). This is critical for suppressing noisy framework-level logging while
keeping your application logs at `Debug` or `Information`.

### Override for Specific Namespaces

Common overrides for a clean log output:

| Source Context                                         | Recommended Level |
|-------------------------------------------------------|-------------------|
| `Microsoft.AspNetCore`                                | Warning           |
| `Microsoft.Hosting.Lifetime`                          | Information       |
| `Microsoft.EntityFrameworkCore.Database.Command`      | Warning           |
| `Microsoft.EntityFrameworkCore.Infrastructure`        | Warning           |
| `System.Net.Http.HttpClient`                          | Warning           |
| `Microsoft.AspNetCore.Authentication`                 | Information       |

### Dynamic Level Switching

For production debugging, you can change the minimum level at runtime without restarting
the application:

```csharp
LoggingLevelSwitch levelSwitch = new(LogEventLevel.Information);

// Use the switch in configuration:
.MinimumLevel.ControlledBy(levelSwitch)

// Expose an endpoint (secured!) to change the level:
app.MapPost("/admin/log-level", (string level) =>
{
    if (Enum.TryParse<LogEventLevel>(level, true, out LogEventLevel parsed))
    {
        levelSwitch.MinimumLevel = parsed;
        return Results.Ok($"Log level changed to {parsed}");
    }
    return Results.BadRequest("Invalid log level");
}).RequireAuthorization("AdminPolicy");
```

This is useful for temporarily enabling `Debug` logging in production to diagnose an issue,
then reverting to `Information` without a deployment.

---

## Destructuring Policies for Complex Objects

### The @ Destructuring Operator

The `@` operator tells Serilog to destructure an object, capturing its public properties
as a structured object in the log event rather than calling `.ToString()`:

```csharp
var order = new Order { Id = 42, Total = 99.95m, Status = OrderStatus.Confirmed };
_logger.LogInformation("Order processed: {@Order}", order);
```

This produces a log event where `Order` is a structured object with `Id`, `Total`, and
`Status` properties, enabling queries like `Order.Total > 50` in Seq.

Without `@`, Serilog calls `.ToString()` on the object, which typically produces something
unhelpful like `MyService.Models.Order`.

### Custom Destructuring Policies

For fine-grained control over how objects are destructured, implement
`IDestructuringPolicy`:

```csharp
// Logging/OrderDestructuringPolicy.cs

using Serilog.Core;
using Serilog.Events;

namespace MyService.Logging;

/// <summary>
/// Controls how Order objects are destructured in log events,
/// including only the fields needed for debugging and excluding
/// any sensitive or overly large properties.
/// </summary>
public sealed class OrderDestructuringPolicy : IDestructuringPolicy
{
    public bool TryDestructure(
        object value,
        ILogEventPropertyValueFactory propertyValueFactory,
        [System.Diagnostics.CodeAnalysis.NotNullWhen(true)] out LogEventPropertyValue? result)
    {
        if (value is not Order order)
        {
            result = null;
            return false;
        }

        result = new StructureValue(
        [
            new LogEventProperty("Id", new ScalarValue(order.Id)),
            new LogEventProperty("Status", new ScalarValue(order.Status.ToString())),
            new LogEventProperty("Total", new ScalarValue(order.Total)),
            new LogEventProperty("ItemCount", new ScalarValue(order.Items?.Count ?? 0)),
        ], typeTag: "Order");

        return true;
    }
}
```

Register it:

```csharp
.Destructure.With<OrderDestructuringPolicy>()
```

You can also use the simpler fluent API for common cases:

```csharp
.Destructure.ByTransforming<Order>(o => new
{
    o.Id,
    o.Status,
    o.Total,
    ItemCount = o.Items?.Count ?? 0
})
```

Setting a maximum destructuring depth and collection size prevents excessively large log
events:

```csharp
.Destructure.ToMaximumDepth(4)
.Destructure.ToMaximumStringLength(1024)
.Destructure.ToMaximumCollectionCount(32)
```

---

## Performance Considerations

### Using ILogger of T

Always inject `ILogger<T>` rather than `ILogger` or `Serilog.ILogger` directly. This
ensures each class has a distinct source context, enabling per-namespace filtering:

```csharp
public sealed class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger)
    {
        _logger = logger;
    }

    public async Task<Order> ProcessOrderAsync(int orderId, CancellationToken ct)
    {
        _logger.LogInformation("Processing order {OrderId}", orderId);
        // ...
    }
}
```

### Avoiding String Interpolation

Never use string interpolation (`$"..."`) or `string.Format` with Serilog. This destroys
structured data and allocates strings unnecessarily:

```csharp
// BAD: String interpolation — loses structure, always allocates
_logger.LogInformation($"Processing order {orderId}");

// BAD: String.Format — same problems
_logger.LogInformation(string.Format("Processing order {0}", orderId));

// GOOD: Message template — preserves structure, deferred rendering
_logger.LogInformation("Processing order {OrderId}", orderId);
```

With message templates, Serilog only renders the string if the event passes the minimum
level filter. With interpolation, the string is always allocated regardless of whether the
event will be logged.

### Source Generators for High-Performance Logging

.NET 8 supports compile-time source generation for logging methods, which eliminates the
overhead of parsing message templates at runtime:

```csharp
// Logging/LogMessages.cs

using Microsoft.Extensions.Logging;

namespace MyService.Logging;

/// <summary>
/// Compile-time generated logging methods for the OrderService.
/// These eliminate runtime template parsing and enable zero-allocation
/// logging when the log level is disabled.
/// </summary>
public static partial class LogMessages
{
    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Information,
        Message = "Processing order {OrderId} for customer {CustomerId}")]
    public static partial void OrderProcessing(
        this ILogger logger, int orderId, string customerId);

    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Warning,
        Message = "Order {OrderId} payment retry attempt {RetryCount}")]
    public static partial void PaymentRetry(
        this ILogger logger, int orderId, int retryCount);

    [LoggerMessage(
        EventId = 1002,
        Level = LogLevel.Error,
        Message = "Order {OrderId} processing failed")]
    public static partial void OrderFailed(
        this ILogger logger, int orderId, Exception exception);

    [LoggerMessage(
        EventId = 1003,
        Level = LogLevel.Debug,
        Message = "Order {OrderId} inventory check: {AvailableQuantity} units available")]
    public static partial void InventoryCheck(
        this ILogger logger, int orderId, int availableQuantity);
}
```

Usage:

```csharp
_logger.OrderProcessing(orderId, customerId);
_logger.OrderFailed(orderId, ex);
```

Source-generated logging is the highest-performance option because:
- The message template is parsed at compile time.
- The `IsEnabled` check is inlined.
- No boxing of value types occurs.
- No array allocation for parameters.

### Conditional Logging Checks

For `Debug` or `Verbose` events that involve expensive computation to produce the log data,
guard with an explicit level check:

```csharp
if (_logger.IsEnabled(LogLevel.Debug))
{
    string? serialized = JsonSerializer.Serialize(complexObject);
    _logger.LogDebug("Complex state: {State}", serialized);
}
```

This avoids the serialization cost when debug logging is disabled.

---

## Diagnostic Context

### LogContext.PushProperty

`LogContext.PushProperty` pushes a property onto an ambient async-local stack. All log
events emitted within the scope carry the property:

```csharp
using Serilog.Context;

public async Task ProcessBatchAsync(string batchId, IReadOnlyList<Order> orders)
{
    using (LogContext.PushProperty("BatchId", batchId))
    using (LogContext.PushProperty("BatchSize", orders.Count))
    {
        _logger.LogInformation("Starting batch processing");

        foreach (Order order in orders)
        {
            using (LogContext.PushProperty("OrderId", order.Id))
            {
                await ProcessSingleOrderAsync(order);
            }
        }

        _logger.LogInformation("Batch processing complete");
    }
}
```

Every event within the outer `using` block carries `BatchId` and `BatchSize`. Events
inside the loop additionally carry `OrderId`. When the `using` block exits, the properties
are automatically removed from the context.

### Scoped Diagnostic Context

For `ILogger<T>`, you can use `BeginScope` which integrates with Serilog's `LogContext`:

```csharp
using IDisposable scope = _logger.BeginScope(
    new Dictionary<string, object>
    {
        ["TenantId"] = tenantId,
        ["UserId"] = userId,
    });

_logger.LogInformation("User action initiated");
// TenantId and UserId are attached to this event.
```

---

## Configuration via appsettings.json

### Full Configuration Example

Serilog can be fully configured from `appsettings.json` using the
`Serilog.Settings.Configuration` package. This is the preferred approach for production
because it supports environment-specific overrides and runtime changes.

```json
{
  "Serilog": {
    "Using": [
      "Serilog.Sinks.Console",
      "Serilog.Sinks.File",
      "Serilog.Sinks.Seq",
      "Serilog.Enrichers.Environment",
      "Serilog.Enrichers.Thread"
    ],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information",
        "Microsoft.EntityFrameworkCore": "Warning",
        "System": "Warning",
        "System.Net.Http.HttpClient": "Warning"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "formatter": "Serilog.Formatting.Compact.RenderedCompactJsonFormatter, Serilog.Formatting.Compact"
        }
      },
      {
        "Name": "File",
        "Args": {
          "path": "logs/myservice-.log",
          "rollingInterval": "Day",
          "retainedFileCountLimit": 30,
          "fileSizeLimitBytes": 104857600,
          "rollOnFileSizeLimit": true,
          "shared": true,
          "flushToDiskInterval": "00:00:02",
          "formatter": "Serilog.Formatting.Compact.CompactJsonFormatter, Serilog.Formatting.Compact"
        }
      },
      {
        "Name": "Seq",
        "Args": {
          "serverUrl": "http://seq.internal:5341",
          "apiKey": ""
        }
      }
    ],
    "Enrich": [
      "FromLogContext",
      "WithMachineName",
      "WithThreadId"
    ],
    "Properties": {
      "Application": "MyService",
      "Environment": "Production"
    },
    "Destructure": [
      {
        "Name": "ToMaximumDepth",
        "Args": { "maximumDestructuringDepth": 4 }
      },
      {
        "Name": "ToMaximumStringLength",
        "Args": { "maximumStringLength": 1024 }
      },
      {
        "Name": "ToMaximumCollectionCount",
        "Args": { "maximumCollectionCount": 32 }
      }
    ]
  }
}
```

### Environment-Specific Overrides

Use `appsettings.Development.json` to override settings for local development:

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Debug",
      "Override": {
        "Microsoft": "Information",
        "Microsoft.EntityFrameworkCore.Database.Command": "Information"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}{NewLine}  {Message:lj}{NewLine}{Exception}"
        }
      }
    ]
  }
}
```

In development you likely want human-readable console output and more verbose logging,
including EF Core SQL commands, while in production you want compact JSON and stricter
filtering.

---

## Log Aggregation and Searching Patterns

### Structured Query Patterns

When using a structured log store like Seq or Elasticsearch, design your log events for
queryability:

- Use consistent property names across services (`CorrelationId`, `UserId`, `TenantId`).
- Prefer enum-like string values over boolean flags (`PaymentStatus = "Declined"` vs
  `PaymentFailed = true`).
- Log entry and exit points of business operations with the same property set so you can
  correlate them.
- Use event IDs (via `[LoggerMessage]` or a convention) to identify specific log statements
  across code versions.

Example Seq queries:

```
# All errors for a specific correlation ID
CorrelationId = '550e8400-e29b-41d4-a716-446655440000' and @Level = 'Error'

# Slow requests (> 1 second)
Elapsed > 1000 and @MessageTemplate like 'HTTP%'

# Orders over $500 for a specific customer
Order.Total > 500 and CustomerId = 'C-12345'

# Failed health checks in the last hour
RequestPath like '/healthz%' and StatusCode >= 500
```

### Dashboard and Alerting

Structure your log events so that dashboards and alerts can be built on them:

- Log a single summary event at the end of each business operation with all relevant
  metrics (duration, count, status).
- Use consistent `EventId` values so dashboards can count specific event types.
- Emit structured events for anomalies that alerting systems can match on.

For example, a payment processing summary event:

```csharp
_logger.LogInformation(
    "Payment processed: {PaymentId} {PaymentStatus} in {ElapsedMs}ms for {Amount:C}",
    paymentId, status, stopwatch.ElapsedMilliseconds, amount);
```

This single event can power a dashboard showing payment success rates, latency percentiles,
and total transaction volume.

---

## Health Check Logging

Health checks are typically polled at high frequency by load balancers and orchestrators.
Logging every health check at `Information` level creates noise. The Serilog request
logging middleware supports a custom `GetLevel` delegate to suppress these:

```csharp
app.UseSerilogRequestLogging(options =>
{
    options.GetLevel = (httpContext, elapsed, ex) =>
    {
        // Suppress health check noise
        if (httpContext.Request.Path.StartsWithSegments("/healthz") ||
            httpContext.Request.Path.StartsWithSegments("/ready"))
        {
            return ex is not null
                ? LogEventLevel.Error
                : LogEventLevel.Verbose;
        }

        // Elevate slow requests
        if (elapsed > 3000)
            return LogEventLevel.Warning;

        // Elevate server errors
        if (httpContext.Response.StatusCode >= 500)
            return LogEventLevel.Error;

        return LogEventLevel.Information;
    };
});
```

For custom health check implementations that need to log their internal status:

```csharp
// HealthChecks/DatabaseHealthCheck.cs

using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MyService.HealthChecks;

/// <summary>
/// Health check that verifies database connectivity and logs diagnostic details
/// only when the check fails, avoiding log noise during normal operation.
/// </summary>
public sealed class DatabaseHealthCheck : IHealthCheck
{
    private readonly IDbConnectionFactory _connectionFactory;
    private readonly ILogger<DatabaseHealthCheck> _logger;

    public DatabaseHealthCheck(
        IDbConnectionFactory connectionFactory,
        ILogger<DatabaseHealthCheck> logger)
    {
        _connectionFactory = connectionFactory;
        _logger = logger;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = await _connectionFactory.CreateConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            await command.ExecuteScalarAsync(cancellationToken);

            return HealthCheckResult.Healthy("Database connection is healthy.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Database health check failed");
            return HealthCheckResult.Unhealthy(
                "Database connection failed.",
                exception: ex);
        }
    }
}
```

---

## Sensitive Data Filtering

Production logs must never contain passwords, tokens, credit card numbers, or personally
identifiable information (PII). Serilog provides several mechanisms to prevent leakage.

### Destructure.ByTransforming

Use `Destructure.ByTransforming<T>` to control exactly which properties of sensitive types
are logged:

```csharp
// In Serilog configuration:
.Destructure.ByTransforming<UserProfile>(u => new
{
    u.Id,
    u.Username,
    Email = MaskEmail(u.Email),
    // Password, SSN, and other sensitive fields are excluded entirely.
})
.Destructure.ByTransforming<PaymentRequest>(p => new
{
    p.OrderId,
    p.Amount,
    p.Currency,
    CardNumber = MaskCardNumber(p.CardNumber),
    // CVV and full card number are never logged.
})

// Masking helpers:
static string MaskEmail(string? email)
{
    if (string.IsNullOrEmpty(email)) return "***";
    int atIndex = email.IndexOf('@');
    if (atIndex <= 1) return "***";
    return string.Concat(email.AsSpan(0, 1), "***", email.AsSpan(atIndex));
}

static string MaskCardNumber(string? cardNumber)
{
    if (string.IsNullOrEmpty(cardNumber) || cardNumber.Length < 4) return "****";
    return $"****-****-****-{cardNumber[^4..]}";
}
```

### Custom Masking Enricher

For a more comprehensive approach, a custom enricher can scan all properties and mask
values matching sensitive patterns:

```csharp
// Enrichers/SensitiveDataMaskingEnricher.cs

using System.Text.RegularExpressions;
using Serilog.Core;
using Serilog.Events;

namespace MyService.Enrichers;

/// <summary>
/// Scans all scalar string properties in a log event and masks values that match
/// known sensitive data patterns (credit cards, SSNs, bearer tokens).
/// This serves as a safety net beyond the type-specific Destructure.ByTransforming
/// configurations.
/// </summary>
public sealed partial class SensitiveDataMaskingEnricher : ILogEventEnricher
{
    // Property names that should be fully redacted regardless of value.
    private static readonly HashSet<string> RedactedPropertyNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "Password", "Secret", "Token", "ApiKey", "ConnectionString",
        "Authorization", "Credential", "AccessToken", "RefreshToken",
    };

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        List<LogEventProperty>? updates = null;

        foreach (KeyValuePair<string, LogEventPropertyValue> property in logEvent.Properties)
        {
            if (RedactedPropertyNames.Contains(property.Key))
            {
                updates ??= [];
                updates.Add(new LogEventProperty(property.Key, new ScalarValue("[REDACTED]")));
                continue;
            }

            if (property.Value is ScalarValue { Value: string stringValue })
            {
                string masked = MaskSensitivePatterns(stringValue);
                if (!ReferenceEquals(masked, stringValue))
                {
                    updates ??= [];
                    updates.Add(new LogEventProperty(property.Key, new ScalarValue(masked)));
                }
            }
        }

        if (updates is not null)
        {
            foreach (LogEventProperty update in updates)
            {
                logEvent.AddOrUpdateProperty(update);
            }
        }
    }

    private static string MaskSensitivePatterns(string value)
    {
        // Mask credit card numbers (simple 16-digit pattern).
        value = CreditCardRegex().Replace(value, "****-****-****-$4");

        // Mask SSN patterns.
        value = SsnRegex().Replace(value, "***-**-$3");

        // Mask bearer tokens.
        value = BearerTokenRegex().Replace(value, "Bearer [REDACTED]");

        return value;
    }

    [GeneratedRegex(@"\b(\d{4})[\s-]?(\d{4})[\s-]?(\d{4})[\s-]?(\d{4})\b")]
    private static partial Regex CreditCardRegex();

    [GeneratedRegex(@"\b(\d{3})[\s-](\d{2})[\s-](\d{4})\b")]
    private static partial Regex SsnRegex();

    [GeneratedRegex(@"Bearer\s+[A-Za-z0-9\-._~+/]+=*", RegexOptions.IgnoreCase)]
    private static partial Regex BearerTokenRegex();
}
```

Register the masking enricher as the last enricher in the pipeline so it runs after all
other enrichers have added their properties:

```csharp
.Enrich.With<SensitiveDataMaskingEnricher>()
```

---

## Best Practices

1. **Use structured message templates, not string interpolation.** Message templates
   preserve semantic properties and enable structured queries. String interpolation
   produces flat text and always allocates, even when the event is filtered out.

2. **Configure Serilog as the first thing in Program.cs.** Use the two-phase bootstrap
   pattern to capture startup errors. Wrap the entire host builder in a try-catch-finally
   with `Log.CloseAndFlush()` in the finally block.

3. **Inject `ILogger<T>`, not `Serilog.ILogger`.** Using the Microsoft abstraction keeps
   your code decoupled from Serilog and enables per-class source context filtering.

4. **Enrich events with correlation IDs.** Use middleware to push a correlation ID into
   `LogContext` so that every event within a request is traceable across services.

5. **Suppress noisy framework logs.** Use `MinimumLevel.Override` to set Microsoft and
   System namespaces to `Warning` while keeping your application namespaces at
   `Information` or `Debug`.

6. **Use `Destructure.ByTransforming` for sensitive types.** Never log passwords, tokens,
   credit card numbers, or PII. Configure destructuring policies for domain types that
   may contain sensitive data.

7. **Set destructuring limits.** Always configure `ToMaximumDepth`, `ToMaximumStringLength`,
   and `ToMaximumCollectionCount` to prevent oversized log events from consuming excessive
   storage and memory.

8. **Use source-generated logging for hot paths.** The `[LoggerMessage]` attribute
   generates zero-allocation logging methods with compile-time template parsing.

9. **Log at the right level.** Use `Debug` for developer diagnostics, `Information` for
   business-relevant events, `Warning` for recoverable anomalies, `Error` for failures
   that require attention, and `Fatal` only for unrecoverable situations.

10. **Use a single request completion event.** Replace the verbose default ASP.NET Core
    request logging with `UseSerilogRequestLogging()`, which produces one event per request
    with timing, status code, and path.

11. **Configure rolling file retention.** Always set `retainedFileCountLimit` and
    `fileSizeLimitBytes` to prevent disk exhaustion in production.

12. **Use JSON formatting in production.** `CompactJsonFormatter` or
    `RenderedCompactJsonFormatter` produces machine-parseable output suitable for log
    collectors (Fluentd, Filebeat, Promtail).

13. **Test your logging configuration.** Write integration tests that verify critical log
    events are emitted with the expected properties. Use `Serilog.Sinks.InMemory` or a
    custom test sink.

14. **Implement dynamic level switching.** Use `LoggingLevelSwitch` with a secured endpoint
    so you can increase verbosity in production without redeploying.

15. **Push contextual properties with LogContext.PushProperty.** Use the ambient diagnostic
    context for properties that should apply to all events within a scope (batch ID,
    tenant ID, user ID) rather than adding them to every individual log call.

---

## Anti-Patterns

1. **String interpolation in log messages.**
   ```csharp
   // WRONG: Destroys structure, always allocates.
   _logger.LogInformation($"User {userId} logged in from {ipAddress}");
   ```
   ```csharp
   // CORRECT: Preserves structure, deferred rendering.
   _logger.LogInformation("User {UserId} logged in from {IpAddress}", userId, ipAddress);
   ```

2. **Logging sensitive data without filtering.**
   ```csharp
   // WRONG: Logs the entire request body including passwords and tokens.
   _logger.LogDebug("Request body: {@RequestBody}", requestBody);
   ```
   ```csharp
   // CORRECT: Use a destructuring policy that excludes sensitive fields.
   .Destructure.ByTransforming<LoginRequest>(r => new { r.Username, Password = "[REDACTED]" })
   ```

3. **Catching and logging exceptions at every layer.**
   ```csharp
   // WRONG: The same exception is logged three times as it bubbles up.
   try { DoWork(); }
   catch (Exception ex)
   {
       _logger.LogError(ex, "Error in DoWork");
       throw; // The caller also catches and logs this.
   }
   ```
   Log exceptions at the boundary (controller, middleware, message handler) and let inner
   layers throw without catching-and-rethrowing just to log.

4. **Using `ToString()` on complex objects.**
   ```csharp
   // WRONG: Produces meaningless type name like "MyService.Models.Order".
   _logger.LogInformation("Processing order {Order}", order);
   ```
   ```csharp
   // CORRECT: Destructure to capture properties.
   _logger.LogInformation("Processing order {@Order}", order);
   ```

5. **Logging in tight loops without level guards.**
   ```csharp
   // WRONG: Allocates strings and params arrays 10,000 times even if Debug is disabled.
   foreach (var item in items) // 10,000 items
   {
       _logger.LogDebug("Processing item {ItemId} with value {Value}", item.Id, item.Value);
   }
   ```
   ```csharp
   // CORRECT: Guard with IsEnabled or use source-generated logging.
   bool debugEnabled = _logger.IsEnabled(LogLevel.Debug);
   foreach (var item in items)
   {
       if (debugEnabled)
           _logger.LogDebug("Processing item {ItemId} with value {Value}", item.Id, item.Value);
   }
   ```

6. **Not flushing logs on shutdown.**
   Serilog sinks buffer events for performance. Without `Log.CloseAndFlush()` in a
   `finally` block, the last batch of events may be lost when the process exits.

7. **Logging health checks at Information level.**
   Health check endpoints are hit every few seconds by load balancers. Logging them at
   `Information` creates enormous log volume. Use a custom `GetLevel` delegate in
   `UseSerilogRequestLogging` to demote them to `Verbose`.

8. **Hardcoding sink configuration in code.**
   ```csharp
   // WRONG: Requires recompilation to change log configuration.
   .WriteTo.Seq("http://seq:5341")
   ```
   ```csharp
   // CORRECT: Read from configuration so it can be changed per environment.
   .ReadFrom.Configuration(context.Configuration)
   ```

9. **Using camelCase for property names.**
   ```csharp
   // WRONG: Inconsistent with .NET naming conventions.
   _logger.LogInformation("Processing order {orderId}", orderId);
   ```
   ```csharp
   // CORRECT: PascalCase property names.
   _logger.LogInformation("Processing order {OrderId}", orderId);
   ```

10. **Excessive destructuring depth.**
    Destructuring deep object graphs without limits can produce enormous log events that
    overwhelm sinks and consume excessive storage. Always configure
    `Destructure.ToMaximumDepth(4)` or similar.

---

## Sources & References

- [Serilog Official Documentation](https://serilog.net/)
  Core documentation for the Serilog logging library, including API reference, configuration
  guide, and sink catalog.

- [Serilog.AspNetCore GitHub Repository](https://github.com/serilog/serilog-aspnetcore)
  Integration package for ASP.NET Core, including `UseSerilog()`, request logging middleware,
  and configuration examples.

- [Serilog.Settings.Configuration GitHub Repository](https://github.com/serilog/serilog-settings-configuration)
  Documentation for configuring Serilog via `Microsoft.Extensions.Configuration` (appsettings.json),
  including sink arguments, enrichers, destructuring, and minimum level overrides.

- [Microsoft .NET High-Performance Logging with Source Generators](https://learn.microsoft.com/en-us/dotnet/core/extensions/high-performance-logging)
  Official Microsoft documentation on the `[LoggerMessage]` source generator attribute for
  compile-time logging code generation.

- [Seq Structured Log Server Documentation](https://docs.datalust.co/docs)
  Documentation for the Seq structured log server, including query language, dashboards,
  alerting, and Serilog sink configuration.

- [Serilog Best Practices by Nicholas Blumhardt](https://benfoster.io/blog/serilog-best-practices/)
  Community guide to Serilog best practices covering message templates, enrichment,
  configuration patterns, and common pitfalls.

- [Serilog.Sinks.Elasticsearch GitHub Repository](https://github.com/serilog-contrib/serilog-sinks-elasticsearch)
  Sink for shipping structured log events to Elasticsearch, with index management,
  template registration, and bulk posting configuration.

- [Application Insights Serilog Sink](https://github.com/serilog-contrib/serilog-sinks-applicationinsights)
  Sink for sending Serilog events to Azure Application Insights as traces or exceptions,
  with custom dimension mapping.
