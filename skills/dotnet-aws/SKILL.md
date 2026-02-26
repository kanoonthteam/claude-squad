---
name: dotnet-aws
description: Production-grade AWS S3 patterns for C# .NET 8 -- AWSSDK.S3, presigned URLs, multipart uploads, DI integration, and S3 file operations
---

# AWS S3 for .NET -- Staff Engineer Patterns

Production-ready patterns for Amazon S3 operations in C# 12 / .NET 8 using AWSSDK.S3, AWSSDK.Extensions.NETCore.Setup, presigned URLs, TransferUtility, and IAM credential management.

## Table of Contents
1. [Package Setup and DI Integration](#package-setup-and-di-integration)
2. [IAmazonS3 Interface and Core Operations](#iamazons3-interface-and-core-operations)
3. [Presigned URL Generation](#presigned-url-generation)
4. [Multipart Uploads with TransferUtility](#multipart-uploads-with-transferutility)
5. [Stream-Based Uploads and Downloads](#stream-based-uploads-and-downloads)
6. [Bucket Operations](#bucket-operations)
7. [CORS Configuration](#cors-configuration)
8. [Credential Management](#credential-management)
9. [Error Handling Patterns](#error-handling-patterns)
10. [S3 Event Notifications](#s3-event-notifications)
11. [Testing with LocalStack and Mocks](#testing-with-localstack-and-mocks)
12. [Performance Optimization](#performance-optimization)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)
15. [Sources & References](#sources--references)

---

## Package Setup and DI Integration

### NuGet Packages

The two essential packages for S3 work in .NET 8:

- **AWSSDK.S3** -- Provides `IAmazonS3`, request/response models, and the `TransferUtility` class for all S3 operations.
- **AWSSDK.Extensions.NETCore.Setup** -- Bridges the AWS SDK into Microsoft.Extensions.DependencyInjection, enabling `builder.Services.AddAWSService<IAmazonS3>()` with configuration binding from `appsettings.json` or environment variables.

```xml
<PackageReference Include="AWSSDK.S3" Version="3.7.*" />
<PackageReference Include="AWSSDK.Extensions.NETCore.Setup" Version="3.7.*" />
```

### Registering IAmazonS3 in DI

The `AWSSDK.Extensions.NETCore.Setup` package reads AWS configuration from the `IConfiguration` pipeline. This means `appsettings.json`, environment variables, user secrets, and AWS profiles all feed into the SDK automatically.

```csharp
using Amazon.Extensions.NETCore.Setup;
using Amazon.S3;

var builder = WebApplication.CreateBuilder(args);

// Option 1: Auto-discover credentials and region from config/environment
builder.Services.AddAWSService<IAmazonS3>();

// Option 2: Explicit configuration override
builder.Services.AddAWSService<IAmazonS3>(new AWSOptions
{
    Region = Amazon.RegionEndpoint.APSoutheast1,
    Profile = "my-profile"
});

// Option 3: Bind from a named configuration section
builder.Services.AddAWSService<IAmazonS3>(
    builder.Configuration.GetAWSOptions("S3Config")
);

var app = builder.Build();
```

Corresponding `appsettings.json` for Option 3:

```json
{
  "S3Config": {
    "Region": "ap-southeast-1",
    "Profile": "my-profile"
  }
}
```

### Service Lifetime

`AddAWSService<IAmazonS3>()` registers the client as a **singleton** by default. The underlying `AmazonS3Client` manages its own `HttpClient` and connection pool, so a singleton lifetime is correct. Do not register it as transient or scoped -- that defeats connection reuse and causes socket exhaustion.

---

## IAmazonS3 Interface and Core Operations

The `IAmazonS3` interface is the primary abstraction for all S3 operations. It exposes async methods for object CRUD, bucket management, and metadata queries.

### PutObjectAsync -- Uploading Objects

```csharp
using Amazon.S3;
using Amazon.S3.Model;

namespace MyApp.Services;

public sealed class S3StorageService
{
    private readonly IAmazonS3 _s3;
    private readonly string _bucketName;

    public S3StorageService(IAmazonS3 s3, IConfiguration config)
    {
        _s3 = s3;
        _bucketName = config["S3:BucketName"]
            ?? throw new InvalidOperationException("S3:BucketName is not configured.");
    }

    /// <summary>
    /// Upload a byte array to S3 with content type and metadata.
    /// </summary>
    public async Task<string> UploadAsync(
        string key,
        byte[] content,
        string contentType,
        IDictionary<string, string>? metadata = null,
        CancellationToken ct = default)
    {
        var request = new PutObjectRequest
        {
            BucketName = _bucketName,
            Key = key,
            ContentType = contentType,
            InputStream = new MemoryStream(content),
            AutoCloseStream = true,
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
        };

        if (metadata is not null)
        {
            foreach (var (k, v) in metadata)
            {
                request.Metadata.Add(k, v);
            }
        }

        var response = await _s3.PutObjectAsync(request, ct);

        if (response.HttpStatusCode != System.Net.HttpStatusCode.OK)
        {
            throw new InvalidOperationException(
                $"S3 PutObject returned {response.HttpStatusCode} for key '{key}'.");
        }

        return response.ETag;
    }

    /// <summary>
    /// Download an object from S3 and return its content as a byte array.
    /// </summary>
    public async Task<(byte[] Content, string ContentType)> DownloadAsync(
        string key,
        CancellationToken ct = default)
    {
        var request = new GetObjectRequest
        {
            BucketName = _bucketName,
            Key = key
        };

        using var response = await _s3.GetObjectAsync(request, ct);
        using var ms = new MemoryStream();
        await response.ResponseStream.CopyToAsync(ms, ct);

        return (ms.ToArray(), response.Headers.ContentType);
    }

    /// <summary>
    /// Delete an object from S3. Succeeds even if the key does not exist.
    /// </summary>
    public async Task DeleteAsync(string key, CancellationToken ct = default)
    {
        var request = new DeleteObjectRequest
        {
            BucketName = _bucketName,
            Key = key
        };

        await _s3.DeleteObjectAsync(request, ct);
    }

    /// <summary>
    /// Check whether an object exists by issuing a HEAD request.
    /// </summary>
    public async Task<bool> ExistsAsync(string key, CancellationToken ct = default)
    {
        try
        {
            var request = new GetObjectMetadataRequest
            {
                BucketName = _bucketName,
                Key = key
            };
            await _s3.GetObjectMetadataAsync(request, ct);
            return true;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    /// <summary>
    /// List objects with a given prefix. Returns all keys (handles pagination).
    /// </summary>
    public async Task<IReadOnlyList<string>> ListKeysAsync(
        string prefix,
        CancellationToken ct = default)
    {
        var keys = new List<string>();
        string? continuationToken = null;

        do
        {
            var request = new ListObjectsV2Request
            {
                BucketName = _bucketName,
                Prefix = prefix,
                ContinuationToken = continuationToken
            };

            var response = await _s3.ListObjectsV2Async(request, ct);
            keys.AddRange(response.S3Objects.Select(o => o.Key));
            continuationToken = response.IsTruncated ? response.NextContinuationToken : null;
        }
        while (continuationToken is not null);

        return keys;
    }

    /// <summary>
    /// Copy an object within the same bucket (or across buckets).
    /// </summary>
    public async Task CopyAsync(
        string sourceKey,
        string destinationKey,
        string? destinationBucket = null,
        CancellationToken ct = default)
    {
        var request = new CopyObjectRequest
        {
            SourceBucket = _bucketName,
            SourceKey = sourceKey,
            DestinationBucket = destinationBucket ?? _bucketName,
            DestinationKey = destinationKey,
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
        };

        await _s3.CopyObjectAsync(request, ct);
    }
}
```

### Batch Delete

For deleting multiple objects efficiently, use `DeleteObjectsAsync` instead of calling `DeleteObjectAsync` in a loop:

```csharp
public async Task DeleteBatchAsync(
    IEnumerable<string> keys,
    CancellationToken ct = default)
{
    var keyList = keys.ToList();
    // S3 allows up to 1000 keys per batch delete request
    const int batchSize = 1000;

    for (int i = 0; i < keyList.Count; i += batchSize)
    {
        var batch = keyList
            .Skip(i)
            .Take(batchSize)
            .Select(k => new KeyVersion { Key = k })
            .ToList();

        var request = new DeleteObjectsRequest
        {
            BucketName = _bucketName,
            Objects = batch,
            Quiet = true // suppress individual success responses
        };

        var response = await _s3.DeleteObjectsAsync(request, ct);

        if (response.DeleteErrors.Count > 0)
        {
            var errors = string.Join(", ",
                response.DeleteErrors.Select(e => $"{e.Key}: {e.Message}"));
            throw new InvalidOperationException(
                $"Failed to delete {response.DeleteErrors.Count} objects: {errors}");
        }
    }
}
```

---

## Presigned URL Generation

Presigned URLs allow clients to upload or download objects directly from S3 without proxying through your API server. The URL encodes the credentials, expiration, and allowed operation in query parameters signed with your AWS credentials.

### GetPreSignedURL for Downloads

```csharp
/// <summary>
/// Generate a time-limited download URL for an S3 object.
/// </summary>
public string GenerateDownloadUrl(string key, TimeSpan expiry)
{
    if (expiry > TimeSpan.FromDays(7))
    {
        throw new ArgumentOutOfRangeException(
            nameof(expiry),
            "Presigned URL expiry cannot exceed 7 days for IAM user credentials.");
    }

    var request = new GetPreSignedUrlRequest
    {
        BucketName = _bucketName,
        Key = key,
        Expires = DateTime.UtcNow.Add(expiry),
        Verb = HttpVerb.GET,
        Protocol = Protocol.HTTPS
    };

    // Optionally force a specific content disposition for browser downloads
    request.ResponseHeaderOverrides.ContentDisposition =
        $"attachment; filename=\"{Path.GetFileName(key)}\"";

    return _s3.GetPreSignedURL(request);
}
```

### GetPreSignedURL for Uploads

```csharp
/// <summary>
/// Generate a time-limited upload URL for direct client-to-S3 uploads.
/// Returns the URL and required headers the client must send.
/// </summary>
public (string Url, IDictionary<string, string> Headers) GenerateUploadUrl(
    string key,
    string contentType,
    long maxContentLength,
    TimeSpan expiry)
{
    var request = new GetPreSignedUrlRequest
    {
        BucketName = _bucketName,
        Key = key,
        Expires = DateTime.UtcNow.Add(expiry),
        Verb = HttpVerb.PUT,
        Protocol = Protocol.HTTPS,
        ContentType = contentType,
        ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
    };

    request.Metadata.Add("uploaded-by", "presigned");

    var url = _s3.GetPreSignedURL(request);

    var headers = new Dictionary<string, string>
    {
        ["Content-Type"] = contentType,
        ["x-amz-server-side-encryption"] = "AES256",
        ["x-amz-meta-uploaded-by"] = "presigned"
    };

    return (url, headers);
}
```

### Presigned URL Expiry Limits

- **IAM user credentials**: Maximum 7 days (604800 seconds).
- **STS temporary credentials (IAM role / AssumeRole)**: Maximum duration equals the remaining session lifetime, up to 36 hours.
- **IAM Identity Center (SSO)**: Maximum duration equals the remaining session lifetime.

Always validate the expiry before generating the URL; `AmazonS3Client` silently accepts longer durations but the URL will fail at request time.

---

## Multipart Uploads with TransferUtility

`TransferUtility` wraps the low-level multipart upload API into a simple, high-level interface. It automatically splits files larger than 16 MB into parts, uploads them in parallel, and handles retries.

```csharp
using Amazon.S3.Transfer;

public sealed class LargeFileUploader : IDisposable
{
    private readonly TransferUtility _transfer;
    private readonly string _bucketName;

    public LargeFileUploader(IAmazonS3 s3, IConfiguration config)
    {
        _bucketName = config["S3:BucketName"]
            ?? throw new InvalidOperationException("S3:BucketName is not configured.");

        _transfer = new TransferUtility(s3, new TransferUtilityConfig
        {
            ConcurrentServiceRequests = 10, // parallel part uploads
            MinSizeBeforePartUpload = 16 * 1024 * 1024 // 16 MB threshold
        });
    }

    /// <summary>
    /// Upload a large file from disk with progress tracking.
    /// </summary>
    public async Task UploadLargeFileAsync(
        string filePath,
        string key,
        string contentType,
        IProgress<long>? progress = null,
        CancellationToken ct = default)
    {
        var request = new TransferUtilityUploadRequest
        {
            BucketName = _bucketName,
            Key = key,
            FilePath = filePath,
            ContentType = contentType,
            PartSize = 64 * 1024 * 1024, // 64 MB parts for large files
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256,
            StorageClass = S3StorageClass.IntelligentTiering,
            AutoCloseStream = true,
            AutoResetStreamPosition = true
        };

        // Track upload progress
        long totalBytesTransferred = 0;
        request.UploadProgressEvent += (sender, args) =>
        {
            totalBytesTransferred = args.TransferredBytes;
            progress?.Report(totalBytesTransferred);
        };

        await _transfer.UploadAsync(request, ct);
    }

    /// <summary>
    /// Upload a stream (e.g., from an HTTP request body) as a multipart upload.
    /// </summary>
    public async Task UploadStreamAsync(
        Stream inputStream,
        string key,
        string contentType,
        CancellationToken ct = default)
    {
        var request = new TransferUtilityUploadRequest
        {
            BucketName = _bucketName,
            Key = key,
            InputStream = inputStream,
            ContentType = contentType,
            PartSize = 32 * 1024 * 1024,
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256,
            AutoCloseStream = false // caller owns the stream
        };

        await _transfer.UploadAsync(request, ct);
    }

    /// <summary>
    /// Download a large file directly to disk.
    /// </summary>
    public async Task DownloadToFileAsync(
        string key,
        string filePath,
        CancellationToken ct = default)
    {
        var request = new TransferUtilityDownloadRequest
        {
            BucketName = _bucketName,
            Key = key,
            FilePath = filePath
        };

        await _transfer.DownloadAsync(request, ct);
    }

    /// <summary>
    /// Upload an entire local directory to an S3 prefix.
    /// </summary>
    public async Task UploadDirectoryAsync(
        string localDirectoryPath,
        string s3KeyPrefix,
        CancellationToken ct = default)
    {
        var request = new TransferUtilityUploadDirectoryRequest
        {
            BucketName = _bucketName,
            Directory = localDirectoryPath,
            KeyPrefix = s3KeyPrefix,
            SearchOption = SearchOption.AllDirectories,
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
        };

        await _transfer.UploadDirectoryAsync(request, ct);
    }

    public void Dispose() => _transfer.Dispose();
}
```

---

## Stream-Based Uploads and Downloads

For large files in web APIs, avoid loading entire files into memory. Instead, stream data directly between the HTTP request/response and S3.

### Streaming Upload from IFormFile

```csharp
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/[controller]")]
public sealed class FilesController : ControllerBase
{
    private readonly IAmazonS3 _s3;
    private readonly string _bucketName;

    public FilesController(IAmazonS3 s3, IConfiguration config)
    {
        _s3 = s3;
        _bucketName = config["S3:BucketName"]!;
    }

    [HttpPost("upload")]
    [RequestSizeLimit(500 * 1024 * 1024)] // 500 MB
    public async Task<IActionResult> Upload(
        IFormFile file,
        CancellationToken ct)
    {
        if (file.Length == 0)
            return BadRequest("Empty file.");

        var key = $"uploads/{Guid.NewGuid()}/{file.FileName}";

        await using var stream = file.OpenReadStream();

        var request = new PutObjectRequest
        {
            BucketName = _bucketName,
            Key = key,
            InputStream = stream,
            ContentType = file.ContentType,
            AutoCloseStream = false,
            ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256
        };

        request.Metadata.Add("original-filename", file.FileName);
        request.Metadata.Add("upload-timestamp", DateTime.UtcNow.ToString("O"));

        await _s3.PutObjectAsync(request, ct);

        return Ok(new { key, file.Length });
    }

    [HttpGet("download/{*key}")]
    public async Task<IActionResult> Download(string key, CancellationToken ct)
    {
        try
        {
            var response = await _s3.GetObjectAsync(
                new GetObjectRequest { BucketName = _bucketName, Key = key }, ct);

            return File(
                response.ResponseStream,
                response.Headers.ContentType,
                Path.GetFileName(key));
        }
        catch (AmazonS3Exception ex)
            when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return NotFound();
        }
    }
}
```

### Streaming Download with Range Requests

For supporting resume-capable downloads and byte-range requests:

```csharp
public async Task<Stream> DownloadRangeAsync(
    string key,
    long start,
    long end,
    CancellationToken ct = default)
{
    var request = new GetObjectRequest
    {
        BucketName = _bucketName,
        Key = key,
        ByteRange = new ByteRange(start, end)
    };

    var response = await _s3.GetObjectAsync(request, ct);
    return response.ResponseStream;
}
```

---

## Bucket Operations

### Create Bucket

```csharp
public async Task CreateBucketAsync(
    string bucketName,
    string region,
    CancellationToken ct = default)
{
    var request = new PutBucketRequest
    {
        BucketName = bucketName,
        BucketRegionName = region,
        ObjectOwnership = ObjectOwnership.BucketOwnerEnforced // disable ACLs
    };

    await _s3.PutBucketAsync(request, ct);

    // Enable versioning
    await _s3.PutBucketVersioningAsync(new PutBucketVersioningRequest
    {
        BucketName = bucketName,
        VersioningConfig = new S3BucketVersioningConfig
        {
            Status = VersionStatus.Enabled
        }
    }, ct);

    // Block all public access
    await _s3.PutPublicAccessBlockAsync(new PutPublicAccessBlockRequest
    {
        BucketName = bucketName,
        PublicAccessBlockConfiguration = new PublicAccessBlockConfiguration
        {
            BlockPublicAcls = true,
            BlockPublicPolicy = true,
            IgnorePublicAcls = true,
            RestrictPublicBuckets = true
        }
    }, ct);

    // Enable default encryption
    await _s3.PutBucketEncryptionAsync(new PutBucketEncryptionRequest
    {
        BucketName = bucketName,
        ServerSideEncryptionConfiguration = new ServerSideEncryptionConfiguration
        {
            ServerSideEncryptionRules =
            [
                new ServerSideEncryptionRule
                {
                    ServerSideEncryptionByDefault = new ServerSideEncryptionByDefault
                    {
                        ServerSideEncryptionAlgorithm = ServerSideEncryptionMethod.AES256
                    },
                    BucketKeyEnabled = true
                }
            ]
        }
    }, ct);
}
```

### List Buckets

```csharp
public async Task<IReadOnlyList<S3Bucket>> ListBucketsAsync(CancellationToken ct = default)
{
    var response = await _s3.ListBucketsAsync(ct);
    return response.Buckets.AsReadOnly();
}
```

### Configure Lifecycle Rules

```csharp
public async Task ConfigureLifecycleAsync(
    string bucketName,
    CancellationToken ct = default)
{
    var config = new LifecycleConfiguration
    {
        Rules =
        [
            new LifecycleRule
            {
                Id = "transition-to-ia-after-30d",
                Status = LifecycleRuleStatus.Enabled,
                Filter = new LifecycleFilter
                {
                    LifecycleFilterPredicate = new LifecyclePrefixPredicate
                    {
                        Prefix = "archives/"
                    }
                },
                Transitions =
                [
                    new LifecycleTransition
                    {
                        Days = 30,
                        StorageClass = S3StorageClass.StandardInfrequentAccess
                    },
                    new LifecycleTransition
                    {
                        Days = 90,
                        StorageClass = S3StorageClass.Glacier
                    }
                ]
            },
            new LifecycleRule
            {
                Id = "delete-temp-after-7d",
                Status = LifecycleRuleStatus.Enabled,
                Filter = new LifecycleFilter
                {
                    LifecycleFilterPredicate = new LifecyclePrefixPredicate
                    {
                        Prefix = "tmp/"
                    }
                },
                Expiration = new LifecycleRuleExpiration { Days = 7 },
                AbortIncompleteMultipartUpload = new LifecycleRuleAbortIncompleteMultipartUpload
                {
                    DaysAfterInitiation = 3
                }
            }
        ]
    };

    await _s3.PutLifecycleConfigurationAsync(new PutLifecycleConfigurationRequest
    {
        BucketName = bucketName,
        Configuration = config
    }, ct);
}
```

---

## CORS Configuration

Required when browsers need to upload/download directly to S3 using presigned URLs.

```csharp
public async Task ConfigureCorsAsync(
    string bucketName,
    IEnumerable<string> allowedOrigins,
    CancellationToken ct = default)
{
    var corsConfig = new CORSConfiguration
    {
        Rules =
        [
            new CORSRule
            {
                Id = "allow-web-uploads",
                AllowedOrigins = allowedOrigins.ToList(),
                AllowedMethods = ["GET", "PUT", "POST", "DELETE", "HEAD"],
                AllowedHeaders = ["*"],
                ExposeHeaders = ["ETag", "x-amz-request-id", "x-amz-id-2"],
                MaxAgeSeconds = 3600
            }
        ]
    };

    await _s3.PutCORSConfigurationAsync(new PutCORSConfigurationRequest
    {
        BucketName = bucketName,
        Configuration = corsConfig
    }, ct);
}
```

---

## Credential Management

### Credential Resolution Order

The AWS SDK for .NET resolves credentials in this order:

1. **Explicit credentials** passed to `AmazonS3Client` constructor (avoid in production).
2. **AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN** environment variables.
3. **AWS shared credentials file** (`~/.aws/credentials`) using the `[default]` or named profile.
4. **AWS config file** (`~/.aws/config`) for SSO and role-based profiles.
5. **ECS container credentials** via the `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` endpoint.
6. **EC2 instance metadata (IMDS v2)** -- IAM role attached to the EC2 instance.

### Recommended Patterns by Environment

| Environment | Credential Source | Notes |
|---|---|---|
| Local development | Named profile in `~/.aws/credentials` | Set `AWS:Profile` in `appsettings.Development.json` |
| CI/CD | Environment variables or OIDC | GitHub Actions supports OIDC for AssumeRoleWithWebIdentity |
| ECS Fargate | Task IAM role | Automatic via container credentials endpoint |
| EC2 | Instance profile IAM role | Automatic via IMDS v2 |
| Lambda | Execution role | Automatic via environment variables set by Lambda runtime |
| EKS | IRSA (IAM Roles for Service Accounts) | Uses projected service account tokens |

### Profile Configuration in appsettings

```json
{
  "AWS": {
    "Profile": "dev-profile",
    "Region": "ap-southeast-1"
  }
}
```

### Assuming a Cross-Account Role

```csharp
using Amazon.SecurityToken;
using Amazon.SecurityToken.Model;

public static IAmazonS3 CreateCrossAccountS3Client(string roleArn, string sessionName)
{
    var stsClient = new AmazonSecurityTokenServiceClient();

    var assumeRoleResponse = stsClient.AssumeRoleAsync(new AssumeRoleRequest
    {
        RoleArn = roleArn,
        RoleSessionName = sessionName,
        DurationSeconds = 3600
    }).GetAwaiter().GetResult();

    var credentials = assumeRoleResponse.Credentials;

    return new AmazonS3Client(
        credentials.AccessKeyId,
        credentials.SecretAccessKey,
        credentials.SessionToken,
        Amazon.RegionEndpoint.APSoutheast1);
}
```

---

## Error Handling Patterns

### AmazonS3Exception Hierarchy

All S3 errors derive from `AmazonS3Exception`, which itself extends `AmazonServiceException`. The key properties are:

- **StatusCode** (`System.Net.HttpStatusCode`) -- The HTTP status code.
- **ErrorCode** (`string`) -- The S3-specific error code (e.g., `"NoSuchKey"`, `"NoSuchBucket"`, `"AccessDenied"`).
- **ErrorType** (`ErrorType`) -- Whether the error is `Sender` (client) or `Receiver` (server).
- **RequestId** -- Useful for AWS support cases.

### Comprehensive Error Handling

```csharp
using System.Net;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Logging;

public sealed class ResilientS3Client
{
    private readonly IAmazonS3 _s3;
    private readonly ILogger<ResilientS3Client> _logger;
    private readonly string _bucketName;

    public ResilientS3Client(
        IAmazonS3 s3,
        ILogger<ResilientS3Client> logger,
        IConfiguration config)
    {
        _s3 = s3;
        _logger = logger;
        _bucketName = config["S3:BucketName"]!;
    }

    public async Task<byte[]?> SafeDownloadAsync(string key, CancellationToken ct = default)
    {
        try
        {
            using var response = await _s3.GetObjectAsync(
                new GetObjectRequest { BucketName = _bucketName, Key = key }, ct);
            using var ms = new MemoryStream();
            await response.ResponseStream.CopyToAsync(ms, ct);
            return ms.ToArray();
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            _logger.LogWarning("Object not found: {Key}", key);
            return null;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.Forbidden)
        {
            _logger.LogError(ex,
                "Access denied to {Key}. Check IAM policy and bucket policy. " +
                "RequestId: {RequestId}", key, ex.RequestId);
            throw;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.ServiceUnavailable)
        {
            // S3 returns 503 when throttling -- the SDK retries automatically,
            // but if all retries are exhausted, this catch block runs.
            _logger.LogError(ex,
                "S3 throttling for {Key} after all retries. " +
                "RequestId: {RequestId}", key, ex.RequestId);
            throw;
        }
        catch (AmazonS3Exception ex) when (ex.ErrorCode == "InvalidRange")
        {
            _logger.LogError(ex,
                "Invalid byte range for {Key}. Object may have been modified.", key);
            throw;
        }
        catch (AmazonS3Exception ex)
        {
            _logger.LogError(ex,
                "Unexpected S3 error for {Key}. " +
                "StatusCode={StatusCode}, ErrorCode={ErrorCode}, RequestId={RequestId}",
                key, ex.StatusCode, ex.ErrorCode, ex.RequestId);
            throw;
        }
    }
}
```

### HttpStatusCode Pattern Summary

| Status Code | Meaning | Action |
|---|---|---|
| 200 | OK | Success |
| 204 | No Content | Successful delete |
| 301 | Moved Permanently | Wrong region for bucket |
| 304 | Not Modified | Conditional GET matched ETag |
| 403 | Forbidden | IAM or bucket policy deny |
| 404 | Not Found | Object or bucket does not exist |
| 409 | Conflict | Bucket already exists (owned by another account) |
| 412 | Precondition Failed | Conditional header not met |
| 503 | Service Unavailable | Throttling or internal error -- retry |

### Configuring Retry Behavior

```csharp
using Amazon.Runtime;

var s3Config = new AmazonS3Config
{
    RegionEndpoint = Amazon.RegionEndpoint.APSoutheast1,
    RetryMode = RequestRetryMode.Adaptive, // adaptive retry with token bucket
    MaxErrorRetry = 5,
    Timeout = TimeSpan.FromSeconds(30),
    ReadWriteTimeout = TimeSpan.FromMinutes(5)
};

var client = new AmazonS3Client(s3Config);
```

---

## S3 Event Notifications

S3 can send event notifications to SNS, SQS, or Lambda when objects are created, deleted, or modified.

### Configuring Event Notifications Programmatically

```csharp
public async Task ConfigureEventNotificationsAsync(
    string bucketName,
    string lambdaArn,
    string sqsArn,
    CancellationToken ct = default)
{
    var config = new PutBucketNotificationRequest
    {
        BucketName = bucketName,
        LambdaFunctionConfigurations =
        [
            new LambdaFunctionConfiguration
            {
                FunctionArn = lambdaArn,
                Events = [EventType.ObjectCreatedAll],
                Filter = new Filter
                {
                    S3KeyFilter = new S3KeyFilter
                    {
                        FilterRules =
                        [
                            new FilterRule
                            {
                                Name = "prefix",
                                Value = "uploads/"
                            },
                            new FilterRule
                            {
                                Name = "suffix",
                                Value = ".pdf"
                            }
                        ]
                    }
                }
            }
        ],
        QueueConfigurations =
        [
            new QueueConfiguration
            {
                Queue = sqsArn,
                Events = [EventType.ObjectRemovedAll]
            }
        ]
    };

    await _s3.PutBucketNotificationAsync(config, ct);
}
```

### Processing S3 Events in a Lambda Function

When receiving S3 events in a .NET Lambda, the event payload is deserialized as `S3Event`:

```csharp
using Amazon.Lambda.Core;
using Amazon.Lambda.S3Events;
using Amazon.S3;
using Amazon.S3.Util;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

public sealed class S3EventHandler
{
    private readonly IAmazonS3 _s3;

    public S3EventHandler()
    {
        _s3 = new AmazonS3Client();
    }

    public async Task HandleAsync(S3Event s3Event, ILambdaContext context)
    {
        foreach (var record in s3Event.Records)
        {
            var bucket = record.S3.Bucket.Name;
            var key = record.S3.Object.Key;
            var eventName = record.EventName;
            var size = record.S3.Object.Size;

            context.Logger.LogInformation(
                $"Event={eventName}, Bucket={bucket}, Key={key}, Size={size}");

            if (eventName.Value.StartsWith("ObjectCreated"))
            {
                // Process the newly created object
                using var response = await _s3.GetObjectAsync(bucket, key);
                // ... process response.ResponseStream
            }
        }
    }
}
```

---

## Testing with LocalStack and Mocks

### Unit Testing with Mocked IAmazonS3

Since `IAmazonS3` is an interface, it is straightforward to mock for unit tests. Use NSubstitute or Moq:

```csharp
using Amazon.S3;
using Amazon.S3.Model;
using NSubstitute;
using System.Net;

namespace MyApp.Tests;

public class S3StorageServiceTests
{
    private readonly IAmazonS3 _mockS3 = Substitute.For<IAmazonS3>();
    private readonly S3StorageService _sut;

    public S3StorageServiceTests()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["S3:BucketName"] = "test-bucket"
            })
            .Build();

        _sut = new S3StorageService(_mockS3, config);
    }

    [Fact]
    public async Task UploadAsync_ReturnsETag_OnSuccess()
    {
        // Arrange
        var expectedETag = "\"abc123\"";
        _mockS3.PutObjectAsync(Arg.Any<PutObjectRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutObjectResponse
            {
                HttpStatusCode = HttpStatusCode.OK,
                ETag = expectedETag
            });

        // Act
        var etag = await _sut.UploadAsync(
            "test-key",
            "hello"u8.ToArray(),
            "text/plain");

        // Assert
        Assert.Equal(expectedETag, etag);

        await _mockS3.Received(1).PutObjectAsync(
            Arg.Is<PutObjectRequest>(r =>
                r.BucketName == "test-bucket" &&
                r.Key == "test-key" &&
                r.ContentType == "text/plain"),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExistsAsync_ReturnsFalse_WhenNotFound()
    {
        // Arrange
        _mockS3.GetObjectMetadataAsync(
                Arg.Any<GetObjectMetadataRequest>(),
                Arg.Any<CancellationToken>())
            .ThrowsAsync(new AmazonS3Exception("Not Found")
            {
                StatusCode = HttpStatusCode.NotFound
            });

        // Act
        var exists = await _sut.ExistsAsync("missing-key");

        // Assert
        Assert.False(exists);
    }

    [Fact]
    public async Task DownloadAsync_ReturnsContent()
    {
        // Arrange
        var content = "file content"u8.ToArray();
        var response = new GetObjectResponse
        {
            ResponseStream = new MemoryStream(content),
            Headers = { ContentType = "application/pdf" }
        };

        _mockS3.GetObjectAsync(
                Arg.Any<GetObjectRequest>(),
                Arg.Any<CancellationToken>())
            .Returns(response);

        // Act
        var (data, contentType) = await _sut.DownloadAsync("test.pdf");

        // Assert
        Assert.Equal(content, data);
        Assert.Equal("application/pdf", contentType);
    }

    [Fact]
    public async Task DeleteAsync_CallsDeleteObject()
    {
        // Act
        await _sut.DeleteAsync("delete-me");

        // Assert
        await _mockS3.Received(1).DeleteObjectAsync(
            Arg.Is<DeleteObjectRequest>(r =>
                r.BucketName == "test-bucket" &&
                r.Key == "delete-me"),
            Arg.Any<CancellationToken>());
    }
}
```

### Integration Testing with LocalStack

LocalStack provides a local AWS-compatible environment that supports S3. Use it in integration tests with Testcontainers:

```csharp
using Amazon.S3;
using Amazon.S3.Model;
using Testcontainers.LocalStack;

namespace MyApp.IntegrationTests;

public class S3IntegrationTests : IAsyncLifetime
{
    private readonly LocalStackContainer _localStack = new LocalStackBuilder()
        .WithImage("localstack/localstack:3.0")
        .Build();

    private IAmazonS3 _s3 = null!;
    private const string TestBucket = "integration-test-bucket";

    public async Task InitializeAsync()
    {
        await _localStack.StartAsync();

        _s3 = new AmazonS3Client(
            "test",
            "test",
            new AmazonS3Config
            {
                ServiceURL = _localStack.GetConnectionString(),
                ForcePathStyle = true,
                UseHttp = true
            });

        await _s3.PutBucketAsync(TestBucket);
    }

    public async Task DisposeAsync()
    {
        _s3.Dispose();
        await _localStack.DisposeAsync();
    }

    [Fact]
    public async Task PutAndGetObject_RoundTrips()
    {
        // Arrange
        var content = "Hello, LocalStack!"u8.ToArray();

        // Act -- upload
        await _s3.PutObjectAsync(new PutObjectRequest
        {
            BucketName = TestBucket,
            Key = "test.txt",
            InputStream = new MemoryStream(content),
            ContentType = "text/plain"
        });

        // Act -- download
        using var response = await _s3.GetObjectAsync(TestBucket, "test.txt");
        using var ms = new MemoryStream();
        await response.ResponseStream.CopyToAsync(ms);

        // Assert
        Assert.Equal(content, ms.ToArray());
        Assert.Equal("text/plain", response.Headers.ContentType);
    }

    [Fact]
    public async Task ListObjects_ReturnsPaginatedResults()
    {
        // Arrange -- upload 5 objects
        for (int i = 0; i < 5; i++)
        {
            await _s3.PutObjectAsync(new PutObjectRequest
            {
                BucketName = TestBucket,
                Key = $"prefix/file-{i}.txt",
                InputStream = new MemoryStream("data"u8.ToArray())
            });
        }

        // Act
        var response = await _s3.ListObjectsV2Async(new ListObjectsV2Request
        {
            BucketName = TestBucket,
            Prefix = "prefix/",
            MaxKeys = 2
        });

        // Assert
        Assert.Equal(2, response.S3Objects.Count);
        Assert.True(response.IsTruncated);
    }
}
```

---

## Performance Optimization

### Connection Pooling

The `AmazonS3Client` manages an internal `HttpClient` with connection pooling. Key configuration points:

```csharp
var config = new AmazonS3Config
{
    RegionEndpoint = Amazon.RegionEndpoint.APSoutheast1,
    MaxConnectionsPerServer = 50, // default is typically low
    BufferSize = 8192,
    UseAccelerateEndpoint = false // set true for Transfer Acceleration
};
```

Because the client manages its own pool, register `IAmazonS3` as a singleton. Creating multiple client instances fragments the connection pool and causes excessive TCP handshakes.

### Transfer Acceleration

S3 Transfer Acceleration routes uploads through CloudFront edge locations, reducing latency for geographically distant uploads:

```csharp
// 1. Enable Transfer Acceleration on the bucket
await _s3.PutBucketAccelerateConfigurationAsync(
    new PutBucketAccelerateConfigurationRequest
    {
        BucketName = _bucketName,
        AccelerateConfiguration = new AccelerateConfiguration
        {
            Status = BucketAccelerateStatus.Enabled
        }
    });

// 2. Create a client that uses the accelerate endpoint
var acceleratedClient = new AmazonS3Client(new AmazonS3Config
{
    RegionEndpoint = Amazon.RegionEndpoint.APSoutheast1,
    UseAccelerateEndpoint = true
});
```

The accelerate endpoint uses `{bucket}.s3-accelerate.amazonaws.com` instead of the regional endpoint. This is only beneficial for cross-region or cross-continent transfers.

### Parallel Operations

For bulk operations, use `Parallel.ForEachAsync` with bounded concurrency:

```csharp
public async Task UploadManyAsync(
    IEnumerable<(string Key, byte[] Content, string ContentType)> items,
    int maxConcurrency = 10,
    CancellationToken ct = default)
{
    await Parallel.ForEachAsync(
        items,
        new ParallelOptions
        {
            MaxDegreeOfParallelism = maxConcurrency,
            CancellationToken = ct
        },
        async (item, token) =>
        {
            await _s3.PutObjectAsync(new PutObjectRequest
            {
                BucketName = _bucketName,
                Key = item.Key,
                InputStream = new MemoryStream(item.Content),
                ContentType = item.ContentType,
                AutoCloseStream = true
            }, token);
        });
}
```

### Optimizing Large Listings

When listing millions of objects, use `ListObjectsV2Async` with pagination and avoid loading all keys into memory at once. Process each page as it arrives:

```csharp
public async IAsyncEnumerable<S3Object> ListObjectsStreamAsync(
    string prefix,
    [EnumeratorCancellation] CancellationToken ct = default)
{
    string? continuationToken = null;

    do
    {
        var response = await _s3.ListObjectsV2Async(new ListObjectsV2Request
        {
            BucketName = _bucketName,
            Prefix = prefix,
            ContinuationToken = continuationToken,
            MaxKeys = 1000
        }, ct);

        foreach (var obj in response.S3Objects)
        {
            yield return obj;
        }

        continuationToken = response.IsTruncated ? response.NextContinuationToken : null;
    }
    while (continuationToken is not null);
}
```

### Content-Based Key Design

Avoid sequential key prefixes (e.g., `2024/01/01/file001.txt`, `2024/01/01/file002.txt`). S3 partitions objects by prefix, and sequential keys can cause hot partitions. Instead, use a hash prefix or UUID:

```csharp
public static string GenerateDistributedKey(string logicalPath)
{
    var hash = Convert.ToHexString(
        System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(logicalPath)))[..8];
    return $"{hash}/{logicalPath}";
}
```

Note: AWS has improved S3's internal partitioning significantly since 2018, so this is mainly relevant for extremely high-throughput workloads (thousands of PUT/GET per second on a single prefix).

---

## Best Practices

1. **Register IAmazonS3 as a singleton.** The client manages its own HTTP connection pool. Transient or scoped registration causes socket exhaustion and connection churn.

2. **Always use server-side encryption.** Set `ServerSideEncryptionMethod.AES256` (SSE-S3) or `AWSKMS` (SSE-KMS) on every `PutObjectRequest`. Alternatively, enforce encryption via bucket policy.

3. **Use CancellationToken everywhere.** Every async S3 method accepts a `CancellationToken`. Thread it from the HTTP request context through to the SDK call so that abandoned requests do not continue consuming resources.

4. **Prefer TransferUtility for files larger than 5 MB.** It handles multipart uploads, parallel part transfers, and automatic retries. For files under 5 MB, `PutObjectAsync` is simpler and sufficient.

5. **Set AutoCloseStream appropriately.** When passing your own stream, set `AutoCloseStream = false` so the SDK does not dispose the stream you still own. When creating a stream specifically for the upload, set `AutoCloseStream = true`.

6. **Block public access on all buckets.** Use `PutPublicAccessBlockAsync` to enforce the four public-access-block settings. Use presigned URLs for controlled external access instead of public ACLs.

7. **Configure lifecycle rules.** Abort incomplete multipart uploads after a few days to avoid storage charges for orphaned parts. Transition infrequently accessed data to cheaper storage classes.

8. **Use ListObjectsV2 (not ListObjects).** The V2 API returns a `ContinuationToken` instead of a `Marker`, provides consistent pagination semantics, and is the recommended API going forward.

9. **Log the RequestId on errors.** The `AmazonS3Exception.RequestId` is essential for AWS support cases. Always include it in error logs.

10. **Use path-style addressing only for LocalStack.** In production, virtual-hosted-style addressing (`{bucket}.s3.amazonaws.com`) is the default and required for new buckets. Set `ForcePathStyle = true` only in test configurations targeting LocalStack or MinIO.

11. **Validate presigned URL expiry.** Do not issue presigned URLs with durations longer than necessary. For upload URLs, keep the window under 15 minutes. For download URLs, keep it under 1 hour unless there is a specific requirement.

12. **Use S3 Intelligent-Tiering for unpredictable access patterns.** It automatically moves objects between frequent and infrequent access tiers with no retrieval fees.

---

## Anti-Patterns

### 1. Creating a new AmazonS3Client per request

```csharp
// BAD: Creates a new client (and TCP connection pool) for every call
public async Task UploadBad(byte[] data)
{
    using var client = new AmazonS3Client(); // DO NOT do this
    await client.PutObjectAsync(new PutObjectRequest { /* ... */ });
}

// GOOD: Inject IAmazonS3 as a singleton
public class MyService(IAmazonS3 s3) { /* use s3 */ }
```

### 2. Loading entire large files into memory

```csharp
// BAD: Reads entire file into a byte array
var allBytes = await File.ReadAllBytesAsync("large-file.zip"); // OOM risk
await s3.PutObjectAsync(new PutObjectRequest
{
    InputStream = new MemoryStream(allBytes), // double memory usage
    // ...
});

// GOOD: Stream from disk
await using var stream = File.OpenRead("large-file.zip");
await s3.PutObjectAsync(new PutObjectRequest
{
    InputStream = stream,
    AutoCloseStream = false,
    // ...
});
```

### 3. Ignoring pagination in list operations

```csharp
// BAD: Only gets the first 1000 objects and silently ignores the rest
var response = await s3.ListObjectsV2Async(new ListObjectsV2Request
{
    BucketName = bucket, Prefix = prefix
});
var allKeys = response.S3Objects.Select(o => o.Key).ToList();
// If there are more than 1000 objects, this list is incomplete!

// GOOD: Paginate with ContinuationToken (see ListKeysAsync example above)
```

### 4. Hardcoding credentials

```csharp
// BAD: Never hardcode credentials
var client = new AmazonS3Client("AKIA...", "secret...", RegionEndpoint.USEast1);

// GOOD: Let the SDK resolve credentials from the environment
var client = new AmazonS3Client();
// Or use DI: services.AddAWSService<IAmazonS3>();
```

### 5. Using synchronous (.Result / .GetAwaiter().GetResult()) calls

```csharp
// BAD: Blocks the thread and risks deadlocks in ASP.NET Core
var response = s3.GetObjectAsync(request).Result;

// GOOD: Use async/await throughout
var response = await s3.GetObjectAsync(request, ct);
```

### 6. Not disposing GetObjectResponse

```csharp
// BAD: Leaks the response stream and underlying HTTP connection
var response = await s3.GetObjectAsync(bucket, key);
// response is never disposed

// GOOD: Always dispose or use 'using'
using var response = await s3.GetObjectAsync(bucket, key);
```

### 7. Catching generic Exception instead of AmazonS3Exception

```csharp
// BAD: Catches everything, hiding the real error
try { await s3.GetObjectAsync(request); }
catch (Exception ex) { /* swallowed */ }

// GOOD: Catch specific S3 exceptions with status code patterns
try { await s3.GetObjectAsync(request, ct); }
catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound)
{
    // Handle specifically
}
```

### 8. Using public ACLs instead of presigned URLs

```csharp
// BAD: Making objects publicly readable via ACLs
var request = new PutObjectRequest
{
    CannedACL = S3CannedACL.PublicRead, // Security risk
    // ...
};

// GOOD: Use presigned URLs for time-limited, authenticated access
var url = s3.GetPreSignedURL(new GetPreSignedUrlRequest
{
    BucketName = bucket,
    Key = key,
    Expires = DateTime.UtcNow.AddMinutes(15),
    Verb = HttpVerb.GET
});
```

### 9. Not configuring abort rules for incomplete multipart uploads

Incomplete multipart uploads accumulate storage charges silently. Always configure a lifecycle rule to abort them:

```csharp
// Ensure you have a lifecycle rule with AbortIncompleteMultipartUpload
// set to a reasonable number of days (e.g., 3-7 days)
```

### 10. Using GetObjectAsync to check existence

```csharp
// BAD: Downloads the entire object just to check if it exists
try
{
    using var response = await s3.GetObjectAsync(bucket, key);
    return true;
}
catch (AmazonS3Exception) { return false; }

// GOOD: Use GetObjectMetadataAsync (HEAD request, no data transfer)
try
{
    await s3.GetObjectMetadataAsync(new GetObjectMetadataRequest
    {
        BucketName = bucket, Key = key
    });
    return true;
}
catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound)
{
    return false;
}
```

---

## Sources & References

1. [AWS SDK for .NET -- Amazon S3 Developer Guide](https://docs.aws.amazon.com/sdk-for-net/v3/developer-guide/s3-apis-intro.html)
2. [AWSSDK.S3 NuGet Package](https://www.nuget.org/packages/AWSSDK.S3)
3. [AWSSDK.Extensions.NETCore.Setup Documentation](https://docs.aws.amazon.com/sdk-for-net/v3/developer-guide/net-dg-config-netcore.html)
4. [Amazon S3 API Reference -- GetPreSignedURL](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html)
5. [AWS SDK for .NET -- TransferUtility Class Reference](https://docs.aws.amazon.com/sdkfornet/v3/apidocs/items/S3/TTransferUtility.html)
6. [Amazon S3 Best Practices Design Patterns](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html)
7. [LocalStack S3 Documentation](https://docs.localstack.cloud/user-guide/aws/s3/)
8. [Testcontainers for .NET -- LocalStack Module](https://dotnet.testcontainers.org/modules/localstack/)
