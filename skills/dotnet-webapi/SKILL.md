---
name: dotnet-webapi
description: ASP.NET Core 8 Web API patterns including controllers, minimal APIs, middleware pipeline, model binding, validation, configuration, error handling, CORS, file uploads, versioning, health checks, rate limiting, and Kestrel/IIS hosting
---

# ASP.NET Core 8 Web API Development

## Table of Contents

- [Purpose](#purpose)
- [Project Structure](#project-structure)
- [Controller-Based APIs vs Minimal APIs](#controller-based-apis-vs-minimal-apis)
- [Model Binding and Validation](#model-binding-and-validation)
- [Middleware Pipeline](#middleware-pipeline)
- [Configuration System](#configuration-system)
- [Error Handling](#error-handling)
- [CORS Configuration](#cors-configuration)
- [File Upload Handling](#file-upload-handling)
- [Content Negotiation and Output Formatters](#content-negotiation-and-output-formatters)
- [API Versioning](#api-versioning)
- [Health Checks](#health-checks)
- [Rate Limiting](#rate-limiting)
- [Kestrel Server Configuration](#kestrel-server-configuration)
- [IIS Hosting](#iis-hosting)
- [Best Practices](#best-practices)
- [Anti-Patterns](#anti-patterns)
- [Sources & References](#sources--references)

## Purpose

Guide agents in building production-ready ASP.NET Core 8 Web APIs. Covers the full lifecycle from project structure through hosting, with emphasis on correct middleware ordering, validation patterns, configuration management, and server tuning. All code targets C# 12 / .NET 8 with nullable reference types enabled.

## Project Structure

A well-organized ASP.NET Core 8 Web API follows a layered architecture that separates concerns cleanly.

### Recommended Layout

```
src/
  MyApp.Api/
    Controllers/           # Controller classes
    Endpoints/             # Minimal API endpoint definitions
    Filters/               # Action filters, exception filters
    Middleware/             # Custom middleware components
    Models/
      Requests/            # Incoming DTOs / request models
      Responses/           # Outgoing DTOs / response models
    Validators/            # FluentValidation validators
    Extensions/            # IServiceCollection / IApplicationBuilder extensions
    Options/               # Strongly-typed configuration classes
    Program.cs             # Entry point + service registration + pipeline
    appsettings.json
    appsettings.Development.json
    appsettings.Production.json
  MyApp.Core/
    Entities/              # Domain entities
    Interfaces/            # Repository and service contracts
    Services/              # Business logic
    Exceptions/            # Custom domain exceptions
  MyApp.Infrastructure/
    Data/                  # EF Core DbContext, migrations
    Repositories/          # Repository implementations
    ExternalServices/      # HTTP clients, third-party integrations
```

### Program.cs Entry Point

In .NET 8 the top-level statement style is the default. All service registration and middleware configuration lives in `Program.cs`.

```csharp
using MyApp.Api.Extensions;
using MyApp.Api.Middleware;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Service registration
// ---------------------------------------------------------------------------
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy =
            System.Text.Json.JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.DefaultIgnoreCondition =
            System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull;
    });

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddProblemDetails();

// Register application services (extension method keeps Program.cs clean)
builder.Services.AddApplicationServices(builder.Configuration);

// ---------------------------------------------------------------------------
// Build the app
// ---------------------------------------------------------------------------
var app = builder.Build();

// ---------------------------------------------------------------------------
// Middleware pipeline (ORDER MATTERS)
// ---------------------------------------------------------------------------
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseExceptionHandler();         // 1. Global error handler
app.UseStatusCodePages();          // 2. Status code error pages
app.UseHsts();                     // 3. HSTS (production only)
app.UseHttpsRedirection();         // 4. HTTPS redirect
app.UseCors("DefaultPolicy");      // 5. CORS
app.UseAuthentication();           // 6. Authentication
app.UseAuthorization();            // 7. Authorization
app.UseRateLimiter();              // 8. Rate limiting
app.UseResponseCaching();          // 9. Response caching
app.UseMiddleware<RequestTimingMiddleware>(); // 10. Custom middleware

app.MapControllers();              // Map attribute-routed controllers
app.MapHealthChecks("/healthz");   // Health check endpoint

app.Run();
```

### .csproj Configuration

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <InvariantGlobalization>false</InvariantGlobalization>
  </PropertyGroup>
</Project>
```

Always enable `<Nullable>enable</Nullable>` and treat all warnings as errors in CI builds with `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`.

## Controller-Based APIs vs Minimal APIs

### Controller-Based APIs

Controllers are the traditional approach. They group related endpoints into a class, support filters, model binding attributes, and are well-suited for large APIs with many endpoints.

```csharp
using Microsoft.AspNetCore.Mvc;
using MyApp.Api.Models.Requests;
using MyApp.Api.Models.Responses;
using MyApp.Core.Interfaces;

namespace MyApp.Api.Controllers;

[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[Produces("application/json")]
public sealed class ProductsController : ControllerBase
{
    private readonly IProductService _productService;
    private readonly ILogger<ProductsController> _logger;

    public ProductsController(
        IProductService productService,
        ILogger<ProductsController> logger)
    {
        _productService = productService;
        _logger = logger;
    }

    /// <summary>
    /// Retrieves a paginated list of products.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResponse<ProductResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        if (page < 1) page = 1;
        if (pageSize is < 1 or > 100) pageSize = 20;

        var result = await _productService.GetPagedAsync(page, pageSize, cancellationToken);

        return Ok(new PagedResponse<ProductResponse>
        {
            Items = result.Items.Select(p => p.ToResponse()).ToList(),
            Page = result.Page,
            PageSize = result.PageSize,
            TotalCount = result.TotalCount
        });
    }

    /// <summary>
    /// Retrieves a product by its unique identifier.
    /// </summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ProductResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        var product = await _productService.GetByIdAsync(id, cancellationToken);
        if (product is null)
        {
            return Problem(
                title: "Product not found",
                detail: $"No product exists with ID {id}.",
                statusCode: StatusCodes.Status404NotFound);
        }

        return Ok(product.ToResponse());
    }

    /// <summary>
    /// Creates a new product.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ProductResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Create(
        [FromBody] CreateProductRequest request,
        CancellationToken cancellationToken = default)
    {
        var product = await _productService.CreateAsync(request, cancellationToken);
        var response = product.ToResponse();

        return CreatedAtAction(
            nameof(GetById),
            new { id = response.Id },
            response);
    }

    /// <summary>
    /// Deletes a product.
    /// </summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        var deleted = await _productService.DeleteAsync(id, cancellationToken);
        if (!deleted)
        {
            return Problem(
                title: "Product not found",
                detail: $"No product exists with ID {id}.",
                statusCode: StatusCodes.Status404NotFound);
        }

        return NoContent();
    }
}
```

### Minimal APIs

Minimal APIs reduce ceremony and are suitable for microservices, small APIs, or individual endpoint groups. They support filters starting in .NET 7 and have full OpenAPI support in .NET 8.

```csharp
using Microsoft.AspNetCore.Http.HttpResults;
using MyApp.Api.Models.Requests;
using MyApp.Api.Models.Responses;
using MyApp.Core.Interfaces;

namespace MyApp.Api.Endpoints;

public static class ProductEndpoints
{
    public static void MapProductEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/v1/products")
            .WithTags("Products")
            .RequireAuthorization()
            .WithOpenApi();

        group.MapGet("/", GetAll)
            .WithName("GetAllProducts")
            .WithSummary("Retrieves a paginated list of products");

        group.MapGet("/{id:guid}", GetById)
            .WithName("GetProductById")
            .WithSummary("Retrieves a product by its unique identifier");

        group.MapPost("/", Create)
            .WithName("CreateProduct")
            .WithSummary("Creates a new product")
            .AddEndpointFilter<ValidationFilter<CreateProductRequest>>();

        group.MapDelete("/{id:guid}", Delete)
            .WithName("DeleteProduct")
            .WithSummary("Deletes a product");
    }

    private static async Task<Ok<PagedResponse<ProductResponse>>> GetAll(
        [AsParameters] PaginationQuery query,
        IProductService productService,
        CancellationToken cancellationToken)
    {
        var result = await productService.GetPagedAsync(
            query.Page ?? 1,
            query.PageSize ?? 20,
            cancellationToken);

        return TypedResults.Ok(new PagedResponse<ProductResponse>
        {
            Items = result.Items.Select(p => p.ToResponse()).ToList(),
            Page = result.Page,
            PageSize = result.PageSize,
            TotalCount = result.TotalCount
        });
    }

    private static async Task<Results<Ok<ProductResponse>, NotFound<ProblemDetails>>> GetById(
        Guid id,
        IProductService productService,
        CancellationToken cancellationToken)
    {
        var product = await productService.GetByIdAsync(id, cancellationToken);
        if (product is null)
        {
            return TypedResults.NotFound(new ProblemDetails
            {
                Title = "Product not found",
                Detail = $"No product exists with ID {id}.",
                Status = StatusCodes.Status404NotFound
            });
        }

        return TypedResults.Ok(product.ToResponse());
    }

    private static async Task<Created<ProductResponse>> Create(
        CreateProductRequest request,
        IProductService productService,
        CancellationToken cancellationToken)
    {
        var product = await productService.CreateAsync(request, cancellationToken);
        var response = product.ToResponse();
        return TypedResults.Created($"/api/v1/products/{response.Id}", response);
    }

    private static async Task<Results<NoContent, NotFound>> Delete(
        Guid id,
        IProductService productService,
        CancellationToken cancellationToken)
    {
        var deleted = await productService.DeleteAsync(id, cancellationToken);
        return deleted ? TypedResults.NoContent() : TypedResults.NotFound();
    }
}
```

### When to Choose Which

| Criteria | Controllers | Minimal APIs |
|----------|------------|--------------|
| Large API surface | Preferred | Possible but messy |
| Microservice with few endpoints | Overkill | Ideal |
| Complex filter/attribute logic | Strong support | Limited (endpoint filters) |
| OpenAPI generation | Built-in | Built-in (.NET 8) |
| Testability | Good (can mock) | Good (delegate testing) |
| Performance | Slightly slower | Slightly faster (less overhead) |

## Model Binding and Validation

### Binding Sources

ASP.NET Core can bind data from multiple sources. The `[ApiController]` attribute enables automatic binding inference.

| Attribute | Source | Default for |
|-----------|--------|-------------|
| `[FromBody]` | Request body (JSON) | Complex types |
| `[FromRoute]` | Route template `{id}` | Route parameters |
| `[FromQuery]` | Query string `?page=1` | Simple types |
| `[FromHeader]` | HTTP header | Explicit only |
| `[FromForm]` | Form data | IFormFile, form models |
| `[FromServices]` | DI container | Explicit only |
| `[AsParameters]` | Multiple sources | Minimal API parameter objects |

### DataAnnotations Validation

```csharp
using System.ComponentModel.DataAnnotations;

namespace MyApp.Api.Models.Requests;

public sealed class CreateProductRequest
{
    [Required(ErrorMessage = "Product name is required.")]
    [StringLength(200, MinimumLength = 1, ErrorMessage = "Name must be between 1 and 200 characters.")]
    public required string Name { get; init; }

    [StringLength(2000, ErrorMessage = "Description cannot exceed 2000 characters.")]
    public string? Description { get; init; }

    [Required(ErrorMessage = "Price is required.")]
    [Range(0.01, 999_999.99, ErrorMessage = "Price must be between 0.01 and 999999.99.")]
    public required decimal Price { get; init; }

    [Required(ErrorMessage = "SKU is required.")]
    [RegularExpression(@"^[A-Z]{2,4}-\d{4,8}$", ErrorMessage = "SKU must match pattern XX-0000 (2-4 uppercase letters, dash, 4-8 digits).")]
    public required string Sku { get; init; }

    [Required(ErrorMessage = "Category ID is required.")]
    public required Guid CategoryId { get; init; }

    [Url(ErrorMessage = "Image URL must be a valid URL.")]
    public string? ImageUrl { get; init; }
}
```

With `[ApiController]`, validation failures automatically return a `400 Bad Request` with `ValidationProblemDetails`. No manual `ModelState.IsValid` check is needed.

### FluentValidation

For complex validation logic that goes beyond attribute capabilities, use FluentValidation.

Install the package:

```
dotnet add package FluentValidation.DependencyInjectionExtensions
```

Define a validator:

```csharp
using FluentValidation;
using MyApp.Api.Models.Requests;

namespace MyApp.Api.Validators;

public sealed class CreateProductRequestValidator : AbstractValidator<CreateProductRequest>
{
    public CreateProductRequestValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Product name is required.")
            .MaximumLength(200).WithMessage("Name cannot exceed 200 characters.")
            .Must(name => !name.Contains("<script", StringComparison.OrdinalIgnoreCase))
            .WithMessage("Name contains potentially unsafe content.");

        RuleFor(x => x.Price)
            .GreaterThan(0).WithMessage("Price must be greater than zero.")
            .PrecisionScale(8, 2, ignoreTrailingZeros: true)
            .WithMessage("Price must have at most 2 decimal places.");

        RuleFor(x => x.Sku)
            .NotEmpty().WithMessage("SKU is required.")
            .Matches(@"^[A-Z]{2,4}-\d{4,8}$").WithMessage("SKU format is invalid.");

        RuleFor(x => x.CategoryId)
            .NotEqual(Guid.Empty).WithMessage("Category ID must not be empty.");

        When(x => x.ImageUrl is not null, () =>
        {
            RuleFor(x => x.ImageUrl!)
                .Must(url => Uri.TryCreate(url, UriKind.Absolute, out var uri)
                    && (uri.Scheme == Uri.UriSchemeHttps))
                .WithMessage("Image URL must be a valid HTTPS URL.");
        });
    }
}
```

Register validators and add automatic validation via a filter:

```csharp
// In Program.cs or a service extension
using FluentValidation;

builder.Services.AddValidatorsFromAssemblyContaining<Program>();
```

Create an action filter for automatic validation:

```csharp
using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace MyApp.Api.Filters;

public sealed class FluentValidationFilter : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(
        ActionExecutingContext context,
        ActionExecutionDelegate next)
    {
        foreach (var (_, value) in context.ActionArguments)
        {
            if (value is null) continue;

            var validatorType = typeof(IValidator<>).MakeGenericType(value.GetType());
            if (context.HttpContext.RequestServices.GetService(validatorType)
                is not IValidator validator)
            {
                continue;
            }

            var validationContext = new ValidationContext<object>(value);
            var result = await validator.ValidateAsync(validationContext);

            if (!result.IsValid)
            {
                foreach (var error in result.Errors)
                {
                    context.ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
                }

                context.Result = new BadRequestObjectResult(
                    new ValidationProblemDetails(context.ModelState));
                return;
            }
        }

        await next();
    }
}
```

Register the filter globally:

```csharp
builder.Services.AddControllers(options =>
{
    options.Filters.Add<FluentValidationFilter>();
});
```

## Middleware Pipeline

### Pipeline Order

Middleware executes in the order it is registered. The order is critical for correctness and security.

```
Request
  --> ExceptionHandler        (catches all unhandled exceptions)
  --> HSTS                    (strict transport security header)
  --> HttpsRedirection        (redirect HTTP to HTTPS)
  --> Static Files            (serve wwwroot content, short-circuit)
  --> Routing                 (match endpoint, set RouteData)
  --> CORS                    (apply CORS headers)
  --> Authentication          (populate HttpContext.User)
  --> Authorization           (enforce [Authorize] policies)
  --> Rate Limiting           (enforce rate limit policies)
  --> Custom Middleware        (request logging, timing, etc.)
  --> Endpoint Execution      (controller action / minimal API handler)
Response
  <-- (reverse order through middleware)
```

### Custom Middleware

Custom middleware must follow the convention of accepting `RequestDelegate` and implementing `InvokeAsync`.

```csharp
using System.Diagnostics;

namespace MyApp.Api.Middleware;

public sealed class RequestTimingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestTimingMiddleware> _logger;

    public RequestTimingMiddleware(
        RequestDelegate next,
        ILogger<RequestTimingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();
        var requestId = Activity.Current?.Id ?? context.TraceIdentifier;

        context.Response.OnStarting(() =>
        {
            context.Response.Headers["X-Request-Id"] = requestId;
            context.Response.Headers["X-Response-Time-Ms"] =
                stopwatch.ElapsedMilliseconds.ToString();
            return Task.CompletedTask;
        });

        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            var elapsedMs = stopwatch.ElapsedMilliseconds;
            var statusCode = context.Response.StatusCode;

            if (elapsedMs > 500)
            {
                _logger.LogWarning(
                    "Slow request: {Method} {Path} responded {StatusCode} in {ElapsedMs}ms [RequestId={RequestId}]",
                    context.Request.Method,
                    context.Request.Path,
                    statusCode,
                    elapsedMs,
                    requestId);
            }
            else
            {
                _logger.LogInformation(
                    "{Method} {Path} responded {StatusCode} in {ElapsedMs}ms",
                    context.Request.Method,
                    context.Request.Path,
                    statusCode,
                    elapsedMs);
            }
        }
    }
}
```

### Conditional Middleware

Use `IWebHostEnvironment` to conditionally add middleware:

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/error");
    app.UseHsts();
}
```

### Short-Circuiting Middleware

Middleware can short-circuit the pipeline by not calling `_next`. This is useful for health probes, maintenance mode, or IP blocking.

```csharp
public sealed class MaintenanceModeMiddleware
{
    private readonly RequestDelegate _next;
    private readonly IOptionsMonitor<MaintenanceOptions> _options;

    public MaintenanceModeMiddleware(
        RequestDelegate next,
        IOptionsMonitor<MaintenanceOptions> options)
    {
        _next = next;
        _options = options;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (_options.CurrentValue.IsEnabled
            && !context.Request.Path.StartsWithSegments("/healthz"))
        {
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            context.Response.Headers.RetryAfter = "300";
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Title = "Service Unavailable",
                Detail = "The service is undergoing scheduled maintenance.",
                Status = StatusCodes.Status503ServiceUnavailable
            });
            return; // Short-circuit: do NOT call _next
        }

        await _next(context);
    }
}
```

## Configuration System

### Configuration Sources (Priority Order)

ASP.NET Core loads configuration from multiple sources. Later sources override earlier ones:

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. User secrets (Development only)
4. Environment variables
5. Command-line arguments

### appsettings.json Example

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=MyApp;Trusted_Connection=true;TrustServerCertificate=true"
  },
  "JwtSettings": {
    "Issuer": "https://myapp.example.com",
    "Audience": "https://myapp.example.com",
    "ExpirationMinutes": 60
  },
  "CorsSettings": {
    "AllowedOrigins": [
      "https://app.example.com",
      "https://admin.example.com"
    ]
  },
  "RateLimiting": {
    "PermitLimit": 100,
    "WindowSeconds": 60,
    "QueueLimit": 10
  },
  "FileUpload": {
    "MaxFileSizeBytes": 10485760,
    "AllowedExtensions": [".jpg", ".jpeg", ".png", ".pdf"]
  }
}
```

### Strongly-Typed Configuration with IOptions

Define configuration classes:

```csharp
namespace MyApp.Api.Options;

public sealed class JwtSettings
{
    public const string SectionName = "JwtSettings";

    public required string Issuer { get; init; }
    public required string Audience { get; init; }
    public required int ExpirationMinutes { get; init; }
    public string? SigningKey { get; init; } // Loaded from secrets/env vars
}

public sealed class CorsSettings
{
    public const string SectionName = "CorsSettings";

    public required string[] AllowedOrigins { get; init; }
}

public sealed class RateLimitingOptions
{
    public const string SectionName = "RateLimiting";

    public int PermitLimit { get; init; } = 100;
    public int WindowSeconds { get; init; } = 60;
    public int QueueLimit { get; init; } = 10;
}

public sealed class FileUploadOptions
{
    public const string SectionName = "FileUpload";

    public long MaxFileSizeBytes { get; init; } = 10 * 1024 * 1024; // 10 MB
    public string[] AllowedExtensions { get; init; } = [".jpg", ".jpeg", ".png", ".pdf"];
}
```

Register and bind in `Program.cs`:

```csharp
builder.Services
    .AddOptions<JwtSettings>()
    .BindConfiguration(JwtSettings.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<CorsSettings>()
    .BindConfiguration(CorsSettings.SectionName)
    .ValidateOnStart();

builder.Services.Configure<RateLimitingOptions>(
    builder.Configuration.GetSection(RateLimitingOptions.SectionName));

builder.Services.Configure<FileUploadOptions>(
    builder.Configuration.GetSection(FileUploadOptions.SectionName));
```

### IOptions vs IOptionsSnapshot vs IOptionsMonitor

| Interface | Lifetime | Reloads | Use When |
|-----------|----------|---------|----------|
| `IOptions<T>` | Singleton | No | Config never changes at runtime |
| `IOptionsSnapshot<T>` | Scoped | Per request | Config may change, need per-request consistency |
| `IOptionsMonitor<T>` | Singleton | On change callback | Background services, singleton consumers |

### Environment Variables

Environment variables override `appsettings.json` values. Use double underscores for nested keys:

```bash
# Maps to ConnectionStrings:DefaultConnection
export ConnectionStrings__DefaultConnection="Server=prod-server;..."

# Maps to JwtSettings:SigningKey
export JwtSettings__SigningKey="your-secret-key-here"
```

## Error Handling

### Global Exception Middleware with ProblemDetails (RFC 7807)

.NET 8 has built-in ProblemDetails support. Configure it in `Program.cs`:

```csharp
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Instance =
            $"{context.HttpContext.Request.Method} {context.HttpContext.Request.Path}";
        context.ProblemDetails.Extensions["traceId"] =
            context.HttpContext.TraceIdentifier;
        context.ProblemDetails.Extensions["nodeId"] =
            Environment.MachineName;
    };
});

// Use the built-in exception handler that produces ProblemDetails
app.UseExceptionHandler();
app.UseStatusCodePages();
```

### Custom Exception Handler for Domain Exceptions

For more control, create a custom `IExceptionHandler`:

```csharp
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using MyApp.Core.Exceptions;

namespace MyApp.Api.Middleware;

public sealed class DomainExceptionHandler : IExceptionHandler
{
    private readonly ILogger<DomainExceptionHandler> _logger;

    public DomainExceptionHandler(ILogger<DomainExceptionHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        var (statusCode, title, detail) = exception switch
        {
            NotFoundException e => (
                StatusCodes.Status404NotFound,
                "Resource Not Found",
                e.Message),
            ConflictException e => (
                StatusCodes.Status409Conflict,
                "Conflict",
                e.Message),
            ValidationException e => (
                StatusCodes.Status422UnprocessableEntity,
                "Validation Failed",
                e.Message),
            UnauthorizedAccessException => (
                StatusCodes.Status403Forbidden,
                "Forbidden",
                "You do not have permission to perform this action."),
            _ => (0, string.Empty, string.Empty)
        };

        if (statusCode == 0)
        {
            // Not a domain exception; let the next handler deal with it
            return false;
        }

        _logger.LogWarning(
            exception,
            "Domain exception: {Title} - {Detail}",
            title,
            detail);

        httpContext.Response.StatusCode = statusCode;
        await httpContext.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Title = title,
            Detail = detail,
            Status = statusCode,
            Instance = $"{httpContext.Request.Method} {httpContext.Request.Path}",
            Extensions =
            {
                ["traceId"] = httpContext.TraceIdentifier
            }
        }, cancellationToken);

        return true; // Exception was handled
    }
}
```

Register the handler before the built-in one:

```csharp
builder.Services.AddExceptionHandler<DomainExceptionHandler>();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>(); // fallback for unhandled
builder.Services.AddProblemDetails();
```

### ProblemDetails Response Format

All error responses conform to RFC 7807:

```json
{
  "type": "https://tools.ietf.org/html/rfc7807",
  "title": "Resource Not Found",
  "status": 404,
  "detail": "No product exists with ID 3fa85f64-5717-4562-b3fc-2c963f66afa6.",
  "instance": "GET /api/v1/products/3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "traceId": "00-abc123-def456-01"
}
```

## CORS Configuration

### Basic CORS Setup

```csharp
builder.Services.AddCors(options =>
{
    options.AddPolicy("DefaultPolicy", policy =>
    {
        var allowedOrigins = builder.Configuration
            .GetSection("CorsSettings:AllowedOrigins")
            .Get<string[]>() ?? [];

        policy
            .WithOrigins(allowedOrigins)
            .WithMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
            .WithHeaders("Content-Type", "Authorization", "X-Request-Id")
            .WithExposedHeaders("X-Pagination", "X-Request-Id", "X-Response-Time-Ms")
            .SetPreflightMaxAge(TimeSpan.FromMinutes(10))
            .AllowCredentials();
    });

    // Restrictive policy for public endpoints
    options.AddPolicy("PublicReadOnly", policy =>
    {
        policy
            .AllowAnyOrigin()
            .WithMethods("GET", "HEAD", "OPTIONS")
            .WithHeaders("Content-Type")
            .SetPreflightMaxAge(TimeSpan.FromHours(1));
    });
});

// In the pipeline (MUST be between Routing and Authentication)
app.UseCors("DefaultPolicy");
```

### Per-Endpoint CORS

```csharp
[EnableCors("PublicReadOnly")]
[HttpGet("public/catalog")]
public IActionResult GetPublicCatalog() { /* ... */ }

[DisableCors]
[HttpPost("internal/sync")]
public IActionResult InternalSync() { /* ... */ }
```

### CORS Pitfalls

- `AllowAnyOrigin()` and `AllowCredentials()` cannot be combined -- the CORS specification forbids it.
- CORS middleware must come after `UseRouting()` but before `UseAuthentication()` and `UseAuthorization()`.
- Preflight `OPTIONS` requests must succeed without authentication. Ensure `UseAuthentication()` comes after `UseCors()`.

## File Upload Handling

### Small File Upload with IFormFile

```csharp
[HttpPost("upload")]
[RequestSizeLimit(10 * 1024 * 1024)] // 10 MB
[ProducesResponseType(typeof(FileUploadResponse), StatusCodes.Status200OK)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<IActionResult> UploadFile(
    IFormFile file,
    [FromServices] IOptions<FileUploadOptions> options,
    CancellationToken cancellationToken)
{
    var config = options.Value;

    if (file.Length == 0)
    {
        return Problem(
            title: "Invalid file",
            detail: "The uploaded file is empty.",
            statusCode: StatusCodes.Status400BadRequest);
    }

    if (file.Length > config.MaxFileSizeBytes)
    {
        return Problem(
            title: "File too large",
            detail: $"Maximum file size is {config.MaxFileSizeBytes / (1024 * 1024)} MB.",
            statusCode: StatusCodes.Status400BadRequest);
    }

    var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
    if (!config.AllowedExtensions.Contains(extension))
    {
        return Problem(
            title: "Invalid file type",
            detail: $"Allowed extensions: {string.Join(", ", config.AllowedExtensions)}",
            statusCode: StatusCodes.Status400BadRequest);
    }

    // Generate a safe filename
    var fileName = $"{Guid.NewGuid()}{extension}";
    var filePath = Path.Combine("uploads", fileName);

    await using var stream = new FileStream(filePath, FileMode.Create);
    await file.CopyToAsync(stream, cancellationToken);

    return Ok(new FileUploadResponse
    {
        FileName = fileName,
        SizeBytes = file.Length,
        ContentType = file.ContentType
    });
}
```

### Streaming Large File Uploads

For files larger than the default Kestrel body limit, use streaming to avoid buffering the entire file in memory.

```csharp
[HttpPost("upload/large")]
[DisableFormValueModelBinding] // Custom attribute to disable model binding
[RequestSizeLimit(500 * 1024 * 1024)] // 500 MB
public async Task<IActionResult> UploadLargeFile(
    CancellationToken cancellationToken)
{
    if (!MultipartRequestHelper.IsMultipartContentType(Request.ContentType))
    {
        return Problem(
            title: "Invalid content type",
            detail: "Expected multipart/form-data.",
            statusCode: StatusCodes.Status415UnsupportedMediaType);
    }

    var boundary = MultipartRequestHelper.GetBoundary(
        MediaTypeHeaderValue.Parse(Request.ContentType));

    var reader = new MultipartReader(boundary, HttpContext.Request.Body);
    var section = await reader.ReadNextSectionAsync(cancellationToken);

    while (section is not null)
    {
        if (ContentDispositionHeaderValue.TryParse(
                section.ContentDisposition, out var contentDisposition)
            && contentDisposition.DispositionType.Equals("form-data")
            && !string.IsNullOrEmpty(contentDisposition.FileName.Value))
        {
            var trustedFileName = $"{Guid.NewGuid()}{Path.GetExtension(contentDisposition.FileName.Value)}";
            var filePath = Path.Combine("uploads", trustedFileName);

            await using var targetStream = new FileStream(filePath, FileMode.Create);
            await section.Body.CopyToAsync(targetStream, cancellationToken);
        }

        section = await reader.ReadNextSectionAsync(cancellationToken);
    }

    return Ok();
}
```

Key considerations for file uploads:
- Always generate server-side filenames. Never trust `file.FileName` for storage.
- Validate file content (magic bytes), not just extension.
- Set `RequestSizeLimit` per endpoint rather than globally.
- For large files, use streaming to prevent `OutOfMemoryException`.
- Store files outside the web root or use blob storage (Azure Blob, S3).

## Content Negotiation and Output Formatters

### Default Behavior

ASP.NET Core supports content negotiation via the `Accept` header. JSON is the default. To add XML support:

```csharp
builder.Services.AddControllers()
    .AddXmlSerializerFormatters()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy =
            System.Text.Json.JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.Converters.Add(
            new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
```

### Custom Output Formatter

Create a CSV output formatter for reporting endpoints:

```csharp
using System.Text;
using Microsoft.AspNetCore.Mvc.Formatters;
using Microsoft.Net.Http.Headers;

namespace MyApp.Api.Formatters;

public sealed class CsvOutputFormatter : TextOutputFormatter
{
    public CsvOutputFormatter()
    {
        SupportedMediaTypes.Add(MediaTypeHeaderValue.Parse("text/csv"));
        SupportedEncodings.Add(Encoding.UTF8);
    }

    protected override bool CanWriteType(Type? type)
    {
        return type is not null
            && (typeof(System.Collections.IEnumerable).IsAssignableFrom(type)
                || type.IsGenericType);
    }

    public override async Task WriteResponseBodyAsync(
        OutputFormatterWriteContext context,
        Encoding selectedEncoding)
    {
        var response = context.HttpContext.Response;

        if (context.Object is not System.Collections.IEnumerable items)
        {
            return;
        }

        var sb = new StringBuilder();
        var first = true;

        foreach (var item in items)
        {
            var itemType = item.GetType();
            var properties = itemType.GetProperties();

            if (first)
            {
                sb.AppendLine(string.Join(",", properties.Select(p => p.Name)));
                first = false;
            }

            var values = properties.Select(p =>
            {
                var value = p.GetValue(item)?.ToString() ?? string.Empty;
                return value.Contains(',') ? $"\"{value}\"" : value;
            });

            sb.AppendLine(string.Join(",", values));
        }

        await response.WriteAsync(sb.ToString(), selectedEncoding);
    }
}
```

Register the formatter:

```csharp
builder.Services.AddControllers(options =>
{
    options.OutputFormatters.Add(new CsvOutputFormatter());
    options.RespectBrowserAcceptHeader = true;
    options.ReturnHttpNotAcceptable = true; // Return 406 for unsupported Accept headers
});
```

## API Versioning

### Setup

Install the versioning packages:

```
dotnet add package Asp.Versioning.Mvc
dotnet add package Asp.Versioning.Mvc.ApiExplorer
```

Configure versioning in `Program.cs`:

```csharp
builder.Services
    .AddApiVersioning(options =>
    {
        options.DefaultApiVersion = new Asp.Versioning.ApiVersion(1, 0);
        options.AssumeDefaultVersionWhenUnspecified = true;
        options.ReportApiVersions = true; // Adds api-supported-versions header

        // Support multiple versioning schemes simultaneously
        options.ApiVersionReader = Asp.Versioning.ApiVersionReader.Combine(
            new Asp.Versioning.UrlSegmentApiVersionReader(),          // /api/v1/products
            new Asp.Versioning.HeaderApiVersionReader("X-Api-Version"), // X-Api-Version: 1.0
            new Asp.Versioning.QueryStringApiVersionReader("api-version")); // ?api-version=1.0
    })
    .AddApiExplorer(options =>
    {
        options.GroupNameFormat = "'v'VVV";
        options.SubstituteApiVersionInUrl = true;
    });
```

### Versioned Controllers

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0")]
public sealed class ProductsV1Controller : ControllerBase
{
    [HttpGet("{id:guid}")]
    public IActionResult GetById(Guid id)
    {
        // V1 response shape
        return Ok(new { id, name = "Widget", price = 9.99m });
    }
}

[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("2.0")]
public sealed class ProductsV2Controller : ControllerBase
{
    [HttpGet("{id:guid}")]
    public IActionResult GetById(Guid id)
    {
        // V2 response with additional fields
        return Ok(new
        {
            id,
            name = "Widget",
            pricing = new { amount = 9.99m, currency = "USD" },
            metadata = new { createdAt = DateTime.UtcNow }
        });
    }
}
```

### Deprecating a Version

```csharp
[ApiVersion("1.0", Deprecated = true)]
public sealed class ProductsV1Controller : ControllerBase
{
    // Clients receive Sunset and Deprecation headers
}
```

## Health Checks

### Basic Health Checks

```csharp
builder.Services.AddHealthChecks()
    .AddSqlServer(
        connectionString: builder.Configuration.GetConnectionString("DefaultConnection")!,
        name: "sqlserver",
        tags: ["db", "ready"])
    .AddRedis(
        redisConnectionString: builder.Configuration.GetConnectionString("Redis")!,
        name: "redis",
        tags: ["cache", "ready"])
    .AddUrlGroup(
        uri: new Uri("https://api.external-service.com/health"),
        name: "external-api",
        tags: ["external", "ready"])
    .AddCheck<DiskSpaceHealthCheck>("disk-space", tags: ["infra", "ready"]);
```

### Custom Health Check

```csharp
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MyApp.Api.HealthChecks;

public sealed class DiskSpaceHealthCheck : IHealthCheck
{
    private const long MinimumFreeBytes = 512 * 1024 * 1024; // 512 MB

    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var driveInfo = new DriveInfo(Path.GetPathRoot(AppContext.BaseDirectory)!);
        var freeBytes = driveInfo.AvailableFreeSpace;

        var data = new Dictionary<string, object>
        {
            ["drive"] = driveInfo.Name,
            ["freeSpaceMb"] = freeBytes / (1024 * 1024),
            ["totalSizeMb"] = driveInfo.TotalSize / (1024 * 1024)
        };

        if (freeBytes < MinimumFreeBytes)
        {
            return Task.FromResult(HealthCheckResult.Unhealthy(
                $"Low disk space: {freeBytes / (1024 * 1024)} MB remaining.",
                data: data));
        }

        return Task.FromResult(HealthCheckResult.Healthy(
            $"Disk space OK: {freeBytes / (1024 * 1024)} MB free.",
            data: data));
    }
}
```

### Health Check Endpoints

Map separate liveness and readiness probes for Kubernetes:

```csharp
// Liveness: is the process alive? No dependency checks.
app.MapHealthChecks("/healthz/live", new HealthCheckOptions
{
    Predicate = _ => false // No checks, just "am I running?"
});

// Readiness: can the app serve traffic?
app.MapHealthChecks("/healthz/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready"),
    ResponseWriter = WriteHealthCheckResponse
});

// Detailed status for monitoring dashboards
app.MapHealthChecks("/healthz/detail", new HealthCheckOptions
{
    ResponseWriter = WriteHealthCheckResponse
}).RequireAuthorization("AdminPolicy"); // Protect detailed info
```

Custom response writer for structured output:

```csharp
static async Task WriteHealthCheckResponse(
    HttpContext context,
    HealthReport report)
{
    context.Response.ContentType = "application/json";

    var response = new
    {
        status = report.Status.ToString(),
        duration = report.TotalDuration.TotalMilliseconds,
        checks = report.Entries.Select(e => new
        {
            name = e.Key,
            status = e.Value.Status.ToString(),
            description = e.Value.Description,
            duration = e.Value.Duration.TotalMilliseconds,
            data = e.Value.Data,
            exception = e.Value.Exception?.Message
        })
    };

    await context.Response.WriteAsJsonAsync(response);
}
```

## Rate Limiting

### Built-in .NET 8 Rate Limiter

.NET 8 provides built-in rate limiting middleware with four algorithms: fixed window, sliding window, token bucket, and concurrency limiter.

```csharp
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;

builder.Services.AddRateLimiter(options =>
{
    // Global rate limit rejection handler
    options.OnRejected = async (context, cancellationToken) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.Headers.RetryAfter =
            context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter)
                ? ((int)retryAfter.TotalSeconds).ToString()
                : "60";

        await context.HttpContext.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Title = "Too Many Requests",
            Detail = "Rate limit exceeded. Please try again later.",
            Status = StatusCodes.Status429TooManyRequests
        }, cancellationToken);
    };

    // Fixed window: 100 requests per 60 seconds per authenticated user
    options.AddPolicy("authenticated", context =>
    {
        var userId = context.User?.FindFirst("sub")?.Value
            ?? context.Connection.RemoteIpAddress?.ToString()
            ?? "anonymous";

        return RateLimitPartition.GetFixedWindowLimiter(userId,
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromSeconds(60),
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit = 10
            });
    });

    // Sliding window for sensitive endpoints
    options.AddPolicy("strict", context =>
    {
        var ip = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";

        return RateLimitPartition.GetSlidingWindowLimiter(ip,
            _ => new SlidingWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                SegmentsPerWindow = 6, // 10-second segments
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit = 2
            });
    });

    // Token bucket for API keys (allows bursts)
    options.AddPolicy("apikey", context =>
    {
        var apiKey = context.Request.Headers["X-Api-Key"].ToString();
        if (string.IsNullOrEmpty(apiKey)) apiKey = "no-key";

        return RateLimitPartition.GetTokenBucketLimiter(apiKey,
            _ => new TokenBucketRateLimiterOptions
            {
                TokenLimit = 50,
                ReplenishmentPeriod = TimeSpan.FromSeconds(10),
                TokensPerPeriod = 10,
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit = 5,
                AutoReplenishment = true
            });
    });

    // Concurrency limiter for resource-intensive endpoints
    options.AddPolicy("expensive", _ =>
    {
        return RateLimitPartition.GetConcurrencyLimiter("global",
            _ => new ConcurrencyLimiterOptions
            {
                PermitLimit = 5,
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit = 10
            });
    });
});
```

Apply rate limiting:

```csharp
// In pipeline
app.UseRateLimiter();

// On controllers or actions
[EnableRateLimiting("strict")]
[HttpPost("login")]
public IActionResult Login(LoginRequest request) { /* ... */ }

// On minimal API endpoints
app.MapPost("/api/v1/auth/login", HandleLogin)
    .RequireRateLimiting("strict");
```

## Kestrel Server Configuration

### Kestrel in Program.cs

```csharp
builder.WebHost.ConfigureKestrel(options =>
{
    // Listen on specific ports
    options.ListenAnyIP(5000); // HTTP
    options.ListenAnyIP(5001, listenOptions =>
    {
        listenOptions.UseHttps(); // HTTPS with dev certificate
    });

    // Global limits
    options.Limits.MaxConcurrentConnections = 1000;
    options.Limits.MaxConcurrentUpgradedConnections = 1000;
    options.Limits.MaxRequestBodySize = 50 * 1024 * 1024; // 50 MB global default
    options.Limits.MinRequestBodyDataRate = new MinDataRate(
        bytesPerSecond: 100, gracePeriod: TimeSpan.FromSeconds(10));
    options.Limits.MinResponseDataRate = new MinDataRate(
        bytesPerSecond: 100, gracePeriod: TimeSpan.FromSeconds(10));
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(2);
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(30);

    // HTTP/2 settings
    options.Limits.Http2.MaxStreamsPerConnection = 100;
    options.Limits.Http2.HeaderTableSize = 4096;
    options.Limits.Http2.MaxFrameSize = 16384;
    options.Limits.Http2.MaxRequestHeaderFieldSize = 8192;
    options.Limits.Http2.InitialConnectionWindowSize = 128 * 1024;
    options.Limits.Http2.InitialStreamWindowSize = 96 * 1024;
});
```

### Kestrel via appsettings.json

```json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://*:5000"
      },
      "Https": {
        "Url": "https://*:5001",
        "Certificate": {
          "Path": "/certs/myapp.pfx",
          "Password": ""
        }
      }
    },
    "Limits": {
      "MaxConcurrentConnections": 1000,
      "MaxRequestBodySize": 52428800,
      "KeepAliveTimeout": "00:02:00",
      "RequestHeadersTimeout": "00:00:30"
    }
  }
}
```

### Kestrel Behind a Reverse Proxy

When Kestrel sits behind nginx, Apache, or a cloud load balancer, configure forwarded headers:

```csharp
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders =
        ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// Must be first in pipeline
app.UseForwardedHeaders();
```

## IIS Hosting

### In-Process Hosting (Recommended)

In-process hosting runs the app inside the IIS worker process (w3wp.exe) for better performance.

```xml
<!-- In .csproj -->
<PropertyGroup>
  <AspNetCoreHostingModel>InProcess</AspNetCoreHostingModel>
</PropertyGroup>
```

`web.config` is generated automatically on publish:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*"
             modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet" arguments=".\MyApp.Api.dll"
                  stdoutLogEnabled="false" stdoutLogFile=".\logs\stdout"
                  hostingModel="inprocess">
        <environmentVariables>
          <environmentVariable name="ASPNETCORE_ENVIRONMENT" value="Production" />
        </environmentVariables>
      </aspNetCore>
    </system.webServer>
  </location>
</configuration>
```

### Out-of-Process Hosting

Out-of-process hosting runs Kestrel as a separate process behind IIS acting as a reverse proxy. Use this when you need process isolation or when deploying alongside legacy IIS apps.

```xml
<PropertyGroup>
  <AspNetCoreHostingModel>OutOfProcess</AspNetCoreHostingModel>
</PropertyGroup>
```

### IIS-Specific Limits

```csharp
builder.Services.Configure<IISServerOptions>(options =>
{
    options.MaxRequestBodySize = 50 * 1024 * 1024; // 50 MB
    options.AutomaticAuthentication = false;
    options.AllowSynchronousIO = false; // Keep disabled for performance
});
```

For file uploads exceeding the default IIS limit (30 MB), also set in `web.config`:

```xml
<system.webServer>
  <security>
    <requestFiltering>
      <requestLimits maxAllowedContentLength="524288000" /> <!-- 500 MB -->
    </requestFiltering>
  </security>
</system.webServer>
```

## Best Practices

### General

1. **Always use `CancellationToken`** -- Accept `CancellationToken` in every async controller action and pass it through to all async calls. This allows graceful request cancellation.

2. **Use `sealed` on classes that are not designed for inheritance** -- Sealed classes are faster for the JIT to optimize and make intent clear. Controllers, middleware, services, and validators should all be `sealed` unless extension is explicitly needed.

3. **Enable nullable reference types project-wide** -- Set `<Nullable>enable</Nullable>` in the `.csproj` file and use `required` keyword for properties that must be set.

4. **Prefer `record` types for DTOs** -- Request and response models are ideal as records or classes with `init`-only properties. They signal immutability and reduce boilerplate.

5. **Return `IActionResult` or typed results, not domain entities** -- Never expose EF Core entities directly. Map to response DTOs to control serialization and decouple your API contract from your database schema.

6. **Use extension methods for service registration** -- Keep `Program.cs` clean by moving registration logic into static extension method classes (e.g., `AddApplicationServices`, `AddInfrastructureServices`).

7. **Use `TimeProvider` for testability** -- .NET 8 provides `TimeProvider` as an abstract class. Inject it instead of using `DateTime.UtcNow` or `DateTimeOffset.UtcNow` directly.

8. **Configure JSON serialization once, globally** -- Set `PropertyNamingPolicy`, `DefaultIgnoreCondition`, and enum converters in `AddJsonOptions` rather than per-endpoint.

### Security

9. **Never log sensitive data** -- Do not log request bodies, authorization headers, passwords, tokens, or PII. Use structured logging with explicit property selection.

10. **Use HTTPS everywhere** -- Configure HSTS in production. Redirect HTTP to HTTPS. Set `Secure` flag on cookies.

11. **Validate file uploads thoroughly** -- Check file size, extension, content type, and magic bytes. Generate server-side filenames. Store outside the web root.

12. **Use the Options pattern for secrets** -- Load secrets from environment variables or Azure Key Vault, never from `appsettings.json` committed to source control.

### Performance

13. **Use `AsNoTracking` for read-only queries** -- When returning data that will not be modified, use `AsNoTracking()` on EF Core queries to skip change tracking.

14. **Use response compression** -- Enable response compression middleware for text-based content types (JSON, XML, HTML).

15. **Set appropriate cache headers** -- Use `[ResponseCache]` attributes or middleware to set `Cache-Control` headers. Use ETags for conditional requests.

16. **Use `IAsyncEnumerable<T>` for large result sets** -- Stream results to the client instead of buffering entire collections in memory.

### Middleware

17. **Keep middleware focused** -- Each middleware should do one thing. Do not combine logging, authentication, and rate limiting into a single middleware.

18. **Respect pipeline order** -- Exception handling must be first. Authentication before authorization. CORS before authentication. Rate limiting after authorization.

19. **Avoid `app.Use()` for production middleware** -- Inline delegates are fine for prototyping but create a named middleware class for anything that will run in production.

## Anti-Patterns

### 1. Fat Controllers

**Problem:** Controllers that contain business logic, data access, and validation directly.

```csharp
// BAD: Controller doing everything
[HttpPost]
public async Task<IActionResult> Create(CreateOrderRequest request)
{
    // Validation logic in controller
    if (string.IsNullOrEmpty(request.CustomerEmail))
        return BadRequest("Email required");

    // Business logic in controller
    var discount = request.Total > 100 ? 0.1m : 0;

    // Data access in controller
    var order = new Order { /* ... */ };
    _dbContext.Orders.Add(order);
    await _dbContext.SaveChangesAsync();

    // Email sending in controller
    await _emailService.SendConfirmation(request.CustomerEmail);

    return Ok(order);
}
```

**Fix:** Move logic to services. Controller only handles HTTP concerns (binding, status codes, routing).

### 2. Exposing Entity Framework Entities

**Problem:** Returning EF Core entities directly from controllers.

```csharp
// BAD: Exposes navigation properties, database schema, and may cause circular references
[HttpGet("{id}")]
public async Task<IActionResult> Get(int id)
{
    var user = await _dbContext.Users.Include(u => u.Orders).FirstAsync(u => u.Id == id);
    return Ok(user); // Serializes the entire entity graph
}
```

**Fix:** Map to response DTOs. Never return entities directly.

### 3. Synchronous I/O in Middleware

**Problem:** Using `AllowSynchronousIO = true` or blocking on async calls.

```csharp
// BAD: Blocking the thread pool
public void Invoke(HttpContext context)
{
    var body = new StreamReader(context.Request.Body).ReadToEnd(); // Sync I/O
    var result = _service.ProcessAsync(body).Result; // Blocking on async
}
```

**Fix:** Always use `async Task InvokeAsync()` and `await` all I/O operations.

### 4. Catching All Exceptions Silently

**Problem:** Swallowing exceptions with empty catch blocks.

```csharp
// BAD: Silent failure
try
{
    await _service.ProcessAsync();
}
catch (Exception)
{
    // Silently swallowed -- bugs become invisible
}
```

**Fix:** Use `IExceptionHandler` for global handling. Log every exception. Return appropriate ProblemDetails.

### 5. Hardcoded Configuration Values

**Problem:** Embedding connection strings, URLs, and settings directly in code.

```csharp
// BAD: Hardcoded values
var connectionString = "Server=prod-db;Database=MyApp;Password=secret123";
var client = new HttpClient { BaseAddress = new Uri("https://api.example.com") };
```

**Fix:** Use `IConfiguration`, `IOptions<T>`, environment variables, and secret management.

### 6. Incorrect Middleware Order

**Problem:** Placing authentication after authorization, or CORS after authentication.

```csharp
// BAD: Wrong order causes subtle failures
app.UseAuthorization();    // Checks policies before user is known
app.UseAuthentication();   // Too late -- authorization already ran
app.UseCors();             // Preflight OPTIONS rejected by auth
```

**Fix:** Follow the documented middleware order. Exception handler first, then HSTS, HTTPS redirect, static files, routing, CORS, authentication, authorization, rate limiting, then endpoint execution.

### 7. Missing CancellationToken Propagation

**Problem:** Not passing `CancellationToken` through the call chain.

```csharp
// BAD: Client disconnects but server keeps working
[HttpGet]
public async Task<IActionResult> GetReport()
{
    var data = await _reportService.GenerateAsync(); // No cancellation token
    return Ok(data);
}
```

**Fix:** Accept `CancellationToken cancellationToken = default` in every async action and pass it to all downstream async calls.

### 8. Using `AddTransient` for Database Contexts

**Problem:** Registering `DbContext` as transient when scoped lifetime is correct.

```csharp
// BAD: Creates a new DbContext for every injection, breaking unit of work
builder.Services.AddTransient<AppDbContext>();
```

**Fix:** Use `AddDbContext<T>` which registers as scoped by default, maintaining one context per HTTP request.

### 9. Over-Relying on `AllowAnyOrigin` in CORS

**Problem:** Using wildcard CORS in production APIs that handle authentication.

```csharp
// BAD: Allows any website to make authenticated requests
options.AddDefaultPolicy(builder => builder
    .AllowAnyOrigin()
    .AllowAnyMethod()
    .AllowAnyHeader());
```

**Fix:** Specify exact allowed origins. Use separate CORS policies for public vs authenticated endpoints.

### 10. Not Using ProblemDetails for Errors

**Problem:** Returning inconsistent error shapes across endpoints.

```csharp
// BAD: Every endpoint returns errors differently
return BadRequest("Something went wrong");
return BadRequest(new { error = "bad input" });
return StatusCode(500, new { message = "oops" });
```

**Fix:** Use ProblemDetails (RFC 7807) consistently. Configure `AddProblemDetails()` and `UseExceptionHandler()` for a uniform error contract.

## Sources & References

- [ASP.NET Core Web API documentation](https://learn.microsoft.com/en-us/aspnet/core/web-api/?view=aspnetcore-8.0) -- Official Microsoft documentation covering controllers, minimal APIs, model binding, and API conventions.
- [ASP.NET Core Middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/?view=aspnetcore-8.0) -- Middleware pipeline architecture, ordering, and custom middleware authoring.
- [Rate limiting middleware in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit?view=aspnetcore-8.0) -- Built-in .NET 8 rate limiting with fixed window, sliding window, token bucket, and concurrency algorithms.
- [Kestrel web server configuration](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/options?view=aspnetcore-8.0) -- Kestrel endpoints, HTTPS, limits, HTTP/2, and performance tuning options.
- [Configuration in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-8.0) -- Configuration providers, options pattern, secret management, and environment-specific settings.
- [Health checks in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-8.0) -- Liveness and readiness probes, custom health checks, and Kubernetes integration.
- [Handle errors in ASP.NET Core web APIs](https://learn.microsoft.com/en-us/aspnet/core/web-api/handle-errors?view=aspnetcore-8.0) -- ProblemDetails, IExceptionHandler, and RFC 7807 compliance.
- [FluentValidation documentation](https://docs.fluentvalidation.net/en/latest/aspnet.html) -- Integrating FluentValidation with ASP.NET Core for complex validation scenarios.
- [API versioning in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/web-api/advanced/conventions?view=aspnetcore-8.0) -- URL segment, header, and query string versioning strategies with Asp.Versioning.
