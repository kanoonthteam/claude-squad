---
name: project-tool-apis
description: Export/Integration Engineer skill covering Jira REST API v3, Linear GraphQL API, Notion API, Confluence REST API, and issue sync strategies — all with production-quality Dart 3.x examples for authentication, CRUD operations, webhooks, pagination, batch operations, rate limiting, and conflict resolution
---

# Project Tool APIs — Jira, Linear, Notion, Confluence & Issue Sync

Comprehensive reference for integrating with project management and documentation tools from Dart. Covers Jira REST API v3 for issue tracking, Linear's GraphQL API for modern project management, Notion API for knowledge-base pages and databases, Confluence REST API for wiki documentation, and cross-tool issue synchronization patterns including webhook processing, idempotency, pagination, batch operations, rate limiting, and error handling.

## Table of Contents

1. [Jira REST API v3](#jira-rest-api-v3)
   1. [Authentication](#jira-authentication)
   2. [Issues — Create, Read, Update](#jira-issues--create-read-update)
   3. [Projects and Fields](#jira-projects-and-fields)
   4. [Attachments](#jira-attachments)
   5. [Transitions](#jira-transitions)
   6. [JQL Query Syntax](#jql-query-syntax)
2. [Linear GraphQL API](#linear-graphql-api)
   1. [Authentication and Client Setup](#linear-authentication-and-client-setup)
   2. [Issues, Projects, Teams, Labels](#linear-issues-projects-teams-labels)
   3. [Webhook Integration](#linear-webhook-integration)
3. [Notion API](#notion-api)
   1. [Authentication and Client Setup](#notion-authentication-and-client-setup)
   2. [Pages and Databases](#notion-pages-and-databases)
   3. [Blocks and Properties](#notion-blocks-and-properties)
   4. [Creating Pages with Embedded Images](#creating-notion-pages-with-embedded-wireframe-images)
4. [Confluence REST API](#confluence-rest-api)
   1. [Pages and Spaces](#confluence-pages-and-spaces)
   2. [Attachments](#confluence-attachments)
5. [Issue Sync Strategies](#issue-sync-strategies)
   1. [One-Way Push](#one-way-push)
   2. [Two-Way Sync](#two-way-sync)
   3. [Conflict Resolution](#conflict-resolution)
6. [Webhook Event Processing and Idempotency](#webhook-event-processing-and-idempotency)
7. [API Pagination Patterns](#api-pagination-patterns)
   1. [Cursor-Based Pagination](#cursor-based-pagination)
   2. [Offset-Based Pagination](#offset-based-pagination)
8. [Batch Operations and Rate Limiting](#batch-operations-and-rate-limiting)
9. [Error Handling and Retry Strategies](#error-handling-and-retry-strategies)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)
12. [Sources & References](#sources--references)

---

## Jira REST API v3

Jira Cloud exposes a comprehensive REST API (v3) under the base URL `https://<your-domain>.atlassian.net/rest/api/3/`. All request and response bodies use JSON. The API covers issues, projects, custom fields, attachments, transitions, search via JQL, and more.

### Jira Authentication

Jira Cloud supports two primary authentication methods:

**API Token (Basic Auth)**

Generate a token at `https://id.atlassian.com/manage-profile/security/api-tokens`. Send it as HTTP Basic Auth where the username is your Atlassian account email and the password is the API token.

**OAuth 2.0 (3LO)**

For apps distributed to multiple Jira tenants, use OAuth 2.0 three-legged authorization. The flow is:

1. Register your app at `https://developer.atlassian.com/console/myapps/`.
2. Redirect the user to `https://auth.atlassian.com/authorize` with the required scopes (e.g., `read:jira-work`, `write:jira-work`).
3. Exchange the authorization code for an access token at `https://auth.atlassian.com/oauth/token`.
4. Use the access token in an `Authorization: Bearer <token>` header.
5. Refresh the token before expiry using the refresh token grant.

Scopes to request for typical issue management: `read:jira-work`, `write:jira-work`, `read:jira-user`, `manage:jira-project`.

```dart
// lib/services/jira/jira_client.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Jira Cloud REST API v3 client with API-token and OAuth 2.0 support.
class JiraClient {
  final String baseUrl; // e.g. https://myorg.atlassian.net
  final http.Client _http;
  String _authHeader;

  /// Create a client using API-token basic auth.
  JiraClient.basicAuth({
    required this.baseUrl,
    required String email,
    required String apiToken,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _authHeader =
            'Basic ${base64Encode(utf8.encode('$email:$apiToken'))}';

  /// Create a client using an OAuth 2.0 Bearer token.
  JiraClient.oauth({
    required this.baseUrl,
    required String accessToken,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _authHeader = 'Bearer $accessToken';

  /// Update the Bearer token (e.g. after a refresh).
  void updateAccessToken(String accessToken) {
    _authHeader = 'Bearer $accessToken';
  }

  /// Generic GET with pagination support.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/api/3/$path')
        .replace(queryParameters: queryParams);
    final response = await _http.get(uri, headers: _headers);
    return _handleResponse(response);
  }

  /// Generic POST.
  Future<Map<String, dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/api/3/$path');
    final response = await _http.post(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  /// Generic PUT.
  Future<Map<String, dynamic>> put(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/api/3/$path');
    final response = await _http.put(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  /// Upload an attachment to an issue.
  Future<List<dynamic>> addAttachment(
    String issueIdOrKey,
    String filename,
    Uint8List bytes,
  ) async {
    final uri =
        Uri.parse('$baseUrl/rest/api/3/issue/$issueIdOrKey/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = _authHeader
      ..headers['X-Atlassian-Token'] = 'no-check'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ));
    final streamed = await _http.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw JiraApiException(streamed.statusCode, body);
    }
    return jsonDecode(body) as List<dynamic>;
  }

  /// Transition an issue to a new status.
  Future<void> transitionIssue(
    String issueIdOrKey,
    String transitionId, {
    Map<String, dynamic>? fields,
  }) async {
    final uri =
        Uri.parse('$baseUrl/rest/api/3/issue/$issueIdOrKey/transitions');
    final body = <String, dynamic>{
      'transition': {'id': transitionId},
      if (fields != null) 'fields': fields,
    };
    final response = await _http.post(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 204) {
      throw JiraApiException(response.statusCode, response.body);
    }
  }

  /// Search issues with JQL.
  Future<JiraSearchResult> searchJql(
    String jql, {
    int startAt = 0,
    int maxResults = 50,
    List<String> fields = const ['summary', 'status', 'assignee'],
  }) async {
    final result = await get('search', queryParams: {
      'jql': jql,
      'startAt': '$startAt',
      'maxResults': '$maxResults',
      'fields': fields.join(','),
    });
    return JiraSearchResult.fromJson(result);
  }

  Map<String, String> get _headers => {
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw JiraApiException(response.statusCode, response.body);
  }

  void dispose() => _http.close();
}

class JiraApiException implements Exception {
  final int statusCode;
  final String body;
  JiraApiException(this.statusCode, this.body);

  @override
  String toString() => 'JiraApiException($statusCode): $body';
}

class JiraSearchResult {
  final int startAt;
  final int maxResults;
  final int total;
  final List<Map<String, dynamic>> issues;

  JiraSearchResult({
    required this.startAt,
    required this.maxResults,
    required this.total,
    required this.issues,
  });

  bool get hasMore => startAt + issues.length < total;

  factory JiraSearchResult.fromJson(Map<String, dynamic> json) {
    return JiraSearchResult(
      startAt: json['startAt'] as int,
      maxResults: json['maxResults'] as int,
      total: json['total'] as int,
      issues: (json['issues'] as List).cast<Map<String, dynamic>>(),
    );
  }
}
```

### Jira Issues -- Create, Read, Update

**Creating an issue** requires at minimum a project key, issue type, and summary. The body uses Atlassian Document Format (ADF) for the description field.

Endpoint: `POST /rest/api/3/issue`

Request body example:

```json
{
  "fields": {
    "project": { "key": "PROJ" },
    "issuetype": { "name": "Task" },
    "summary": "Implement login screen",
    "description": {
      "version": 1,
      "type": "doc",
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Implement the login screen per wireframe v2." }
          ]
        }
      ]
    },
    "assignee": { "accountId": "5b10ac8d82e05b22cc7d4ef5" },
    "labels": ["mobile", "sprint-12"],
    "priority": { "name": "High" }
  }
}
```

**Reading an issue**: `GET /rest/api/3/issue/{issueIdOrKey}?fields=summary,status,description`

**Updating an issue**: `PUT /rest/api/3/issue/{issueIdOrKey}` with only the fields to change in the request body. You do not need to send all fields, only the changed ones.

**Important notes on ADF (Atlassian Document Format):**
- The `description` field in API v3 must be ADF, not plain text.
- Inline images are referenced using the `mediaInline` node type with an `id` that corresponds to an attachment.
- ADF supports paragraphs, headings, bullet lists, ordered lists, code blocks, tables, media, and more.

### Jira Projects and Fields

**List projects**: `GET /rest/api/3/project/search` returns paginated results. Filter with `query` parameter for name matching.

**Get project details**: `GET /rest/api/3/project/{projectIdOrKey}` includes issue types, lead, category, and components.

**Custom fields**: `GET /rest/api/3/field` returns all fields (system and custom). Custom fields have IDs like `customfield_10001`. Use `GET /rest/api/3/field/{fieldId}/context` to get context-specific configuration.

Setting custom field values when creating/updating an issue:

```json
{
  "fields": {
    "customfield_10001": "string value",
    "customfield_10002": { "value": "Option A" },
    "customfield_10003": [{ "value": "Tag1" }, { "value": "Tag2" }],
    "customfield_10004": { "accountId": "user-account-id" }
  }
}
```

### Jira Attachments

Upload attachments with a multipart form POST to `POST /rest/api/3/issue/{issueIdOrKey}/attachments`. The `X-Atlassian-Token: no-check` header is required to bypass XSRF protection.

The response returns an array of attachment objects with `id`, `filename`, `mimeType`, `size`, and `content` (download URL).

To embed an uploaded wireframe image in the issue description (ADF), reference the attachment by its ID in a `mediaInline` or `mediaSingle` node:

```json
{
  "type": "mediaSingle",
  "attrs": { "layout": "center" },
  "content": [
    {
      "type": "media",
      "attrs": {
        "type": "file",
        "id": "<attachment-id>",
        "collection": ""
      }
    }
  ]
}
```

### Jira Transitions

List available transitions: `GET /rest/api/3/issue/{issueIdOrKey}/transitions`

Execute a transition: `POST /rest/api/3/issue/{issueIdOrKey}/transitions` with `{ "transition": { "id": "31" } }`. You can optionally include `fields` to set required fields during the transition (e.g., resolution).

Common workflow: Query available transitions first, find the target transition by name, then execute it. Transitions are workflow-specific, so the available IDs vary by project and issue type.

### JQL Query Syntax

JQL (Jira Query Language) is used to search and filter issues.

**Basic syntax**: `field operator value [AND|OR] field operator value [ORDER BY field [ASC|DESC]]`

**Common operators**: `=`, `!=`, `~` (contains), `!~` (not contains), `IN`, `NOT IN`, `IS`, `IS NOT`, `>`, `>=`, `<`, `<=`, `WAS`, `CHANGED`

**Useful JQL examples**:

| Purpose | JQL |
|---------|-----|
| Issues in a project | `project = PROJ` |
| Open bugs assigned to me | `project = PROJ AND issuetype = Bug AND assignee = currentUser() AND status != Done` |
| Updated in last 24 hours | `project = PROJ AND updated >= -24h` |
| Text search in summary | `project = PROJ AND summary ~ "login screen"` |
| Sprint-scoped | `project = PROJ AND sprint = "Sprint 12"` |
| Created this week | `project = PROJ AND created >= startOfWeek()` |
| Specific labels | `project = PROJ AND labels IN ("mobile", "frontend")` |
| Unassigned high priority | `project = PROJ AND assignee IS EMPTY AND priority = High` |
| Status changed after date | `project = PROJ AND status CHANGED AFTER "2025-01-01"` |
| Multiple issue types | `project = PROJ AND issuetype IN (Story, Task, Bug)` |

**JQL functions**: `currentUser()`, `startOfDay()`, `endOfDay()`, `startOfWeek()`, `endOfWeek()`, `startOfMonth()`, `endOfMonth()`, `now()`, `membersOf("group")`, `issueHistory()`.

**Escaping**: Use `\\` to escape reserved characters. Wrap values with spaces in quotes.

---

## Linear GraphQL API

Linear exposes a GraphQL API at `https://api.linear.app/graphql`. It supports queries, mutations, and subscriptions for issues, projects, teams, labels, cycles, and more.

### Linear Authentication and Client Setup

Linear supports two authentication methods:

1. **Personal API keys** — generated at Settings > API > Personal API keys. Sent as `Authorization: <api-key>`.
2. **OAuth 2.0** — for integrations used by multiple workspaces. Redirect-based flow via `https://linear.app/oauth/authorize`.

All requests are `POST` to `https://api.linear.app/graphql` with a JSON body containing `query` and optional `variables`.

Rate limits: Linear uses a complexity-based rate limit. Each request has a computed cost. The response includes `X-RateLimit-Requests-Remaining` and `X-RateLimit-Requests-Reset` headers.

### Linear Issues, Projects, Teams, Labels

**Query issues with filtering**:

```graphql
query FilteredIssues($teamId: String!, $after: String) {
  issues(
    filter: { team: { id: { eq: $teamId } }, state: { name: { neq: "Done" } } }
    first: 50
    after: $after
    orderBy: updatedAt
  ) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      id
      identifier
      title
      description
      priority
      state { name }
      assignee { name email }
      labels { nodes { name color } }
      project { id name }
      createdAt
      updatedAt
    }
  }
}
```

**Create an issue**:

```graphql
mutation CreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    success
    issue {
      id
      identifier
      url
    }
  }
}
```

Variables:

```json
{
  "input": {
    "teamId": "team-uuid",
    "title": "Implement login screen",
    "description": "Per wireframe v2, implement the login screen.",
    "priority": 2,
    "labelIds": ["label-uuid-1"],
    "projectId": "project-uuid",
    "assigneeId": "user-uuid"
  }
}
```

**Update an issue**:

```graphql
mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) {
    success
    issue { id identifier title state { name } }
  }
}
```

**Query teams**: `query { teams { nodes { id name key } } }`

**Query labels**: `query { issueLabels { nodes { id name color } } }`

**Query projects**: `query { projects(first: 50) { nodes { id name state startDate targetDate } } }`

### Linear Webhook Integration

Linear webhooks notify your server of events in real time. Configure them at Settings > API > Webhooks, or programmatically via the `webhookCreate` mutation.

**Supported event types**: `Issue`, `Comment`, `Project`, `Cycle`, `IssueLabel`, `Reaction`, plus sub-actions `create`, `update`, `remove`.

**Webhook payload structure**:

```json
{
  "action": "create",
  "type": "Issue",
  "createdAt": "2025-06-15T10:30:00.000Z",
  "data": {
    "id": "issue-uuid",
    "identifier": "PROJ-42",
    "title": "New issue title",
    "teamId": "team-uuid",
    "stateId": "state-uuid",
    "priority": 2
  },
  "url": "https://linear.app/org/issue/PROJ-42",
  "organizationId": "org-uuid"
}
```

**Webhook signature verification**: Linear signs payloads with HMAC-SHA256 using the webhook signing secret. The signature is in the `Linear-Signature` header. Always verify this server-side before processing the event.

---

## Notion API

The Notion API (currently at version `2022-06-28`) is a REST API at `https://api.notion.com/v1/`. It manages pages, databases, blocks, and users within a Notion workspace.

### Notion Authentication and Client Setup

Notion uses Internal Integrations (bearer token) or Public Integrations (OAuth 2.0).

For internal integrations:
1. Create an integration at `https://www.notion.so/my-integrations`.
2. Copy the Internal Integration Secret (starts with `ntn_` or `secret_`).
3. Share target pages/databases with the integration via the "Connections" menu in Notion.
4. Send requests with `Authorization: Bearer <token>` and `Notion-Version: 2022-06-28`.

### Notion Pages and Databases

**Create a page** inside a database:

`POST /v1/pages`

```json
{
  "parent": { "database_id": "db-uuid" },
  "properties": {
    "Name": { "title": [{ "text": { "content": "Login Screen Wireframe" } }] },
    "Status": { "select": { "name": "In Review" } },
    "Priority": { "number": 1 },
    "Tags": { "multi_select": [{ "name": "mobile" }, { "name": "wireframe" }] },
    "Assignee": { "people": [{ "object": "user", "id": "user-uuid" }] }
  },
  "children": []
}
```

**Query a database**: `POST /v1/databases/{database_id}/query` with a filter object:

```json
{
  "filter": {
    "and": [
      { "property": "Status", "select": { "equals": "In Review" } },
      { "property": "Priority", "number": { "less_than_or_equal_to": 2 } }
    ]
  },
  "sorts": [
    { "property": "Priority", "direction": "ascending" }
  ],
  "page_size": 100,
  "start_cursor": "cursor-string"
}
```

**Update a page**: `PATCH /v1/pages/{page_id}` with only the properties to change.

**Retrieve a page**: `GET /v1/pages/{page_id}`

### Notion Blocks and Properties

Notion pages are composed of blocks. Common block types:

| Block Type | Description |
|-----------|-------------|
| `paragraph` | Text paragraph |
| `heading_1`, `heading_2`, `heading_3` | Headings |
| `bulleted_list_item` | Bullet point |
| `numbered_list_item` | Numbered list |
| `to_do` | Checkbox item |
| `code` | Code block with language |
| `image` | External or uploaded image |
| `embed` | Embedded URL |
| `table` | Table with rows |
| `divider` | Horizontal rule |
| `callout` | Callout box with icon |

**Append blocks to a page**: `PATCH /v1/blocks/{block_id}/children`

**Retrieve block children**: `GET /v1/blocks/{block_id}/children?page_size=100`

**Property types in databases**: `title`, `rich_text`, `number`, `select`, `multi_select`, `date`, `people`, `files`, `checkbox`, `url`, `email`, `phone_number`, `formula`, `relation`, `rollup`, `status`.

### Creating Notion Pages with Embedded Wireframe Images

To create a Notion page with an embedded wireframe image, include an `image` block in the `children` array. Notion supports external URLs for images (the image must be publicly accessible or use a signed URL with sufficient TTL).

```dart
// lib/services/notion/notion_client.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Notion API client for pages, databases, and blocks.
class NotionClient {
  static const _baseUrl = 'https://api.notion.com/v1';
  static const _apiVersion = '2022-06-28';

  final String _token;
  final http.Client _http;

  NotionClient({
    required String token,
    http.Client? httpClient,
  })  : _token = token,
        _http = httpClient ?? http.Client();

  /// Create a page in a database with wireframe image blocks.
  Future<Map<String, dynamic>> createPageWithWireframes({
    required String databaseId,
    required String title,
    required String status,
    required List<String> wireframeImageUrls,
    String? description,
  }) async {
    final children = <Map<String, dynamic>>[];

    // Add description paragraph if provided.
    if (description != null && description.isNotEmpty) {
      children.add({
        'object': 'block',
        'type': 'paragraph',
        'paragraph': {
          'rich_text': [
            {'type': 'text', 'text': {'content': description}},
          ],
        },
      });
    }

    // Add a heading before wireframes.
    children.add({
      'object': 'block',
      'type': 'heading_2',
      'heading_2': {
        'rich_text': [
          {'type': 'text', 'text': {'content': 'Wireframes'}},
        ],
      },
    });

    // Add each wireframe as an image block.
    for (final (index, url) in wireframeImageUrls.indexed) {
      children.add({
        'object': 'block',
        'type': 'image',
        'image': {
          'type': 'external',
          'external': {'url': url},
          'caption': [
            {
              'type': 'text',
              'text': {'content': 'Wireframe ${index + 1}'},
            },
          ],
        },
      });
    }

    final body = {
      'parent': {'database_id': databaseId},
      'properties': {
        'Name': {
          'title': [
            {'text': {'content': title}},
          ],
        },
        'Status': {
          'select': {'name': status},
        },
      },
      'children': children,
    };

    return _post('pages', body);
  }

  /// Query a database with optional filter and pagination.
  Future<NotionQueryResult> queryDatabase(
    String databaseId, {
    Map<String, dynamic>? filter,
    List<Map<String, dynamic>>? sorts,
    int pageSize = 100,
    String? startCursor,
  }) async {
    final body = <String, dynamic>{
      'page_size': pageSize,
      if (filter != null) 'filter': filter,
      if (sorts != null) 'sorts': sorts,
      if (startCursor != null) 'start_cursor': startCursor,
    };
    final json = await _post('databases/$databaseId/query', body);
    return NotionQueryResult.fromJson(json);
  }

  /// Append child blocks to a page or block.
  Future<Map<String, dynamic>> appendBlocks(
    String blockId,
    List<Map<String, dynamic>> children,
  ) async {
    return _patch('blocks/$blockId/children', {'children': children});
  }

  /// Retrieve a page by ID.
  Future<Map<String, dynamic>> getPage(String pageId) => _get('pages/$pageId');

  /// Update page properties.
  Future<Map<String, dynamic>> updatePage(
    String pageId,
    Map<String, dynamic> properties,
  ) async {
    return _patch('pages/$pageId', {'properties': properties});
  }

  // -- HTTP helpers --

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _http.get(
      Uri.parse('$_baseUrl/$path'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _patch(
      String path, Map<String, dynamic> body) async {
    final response = await _http.patch(
      Uri.parse('$_baseUrl/$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Notion-Version': _apiVersion,
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _handleResponse(http.Response response) {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    throw NotionApiException(
      statusCode: response.statusCode,
      code: json['code'] as String? ?? 'unknown',
      message: json['message'] as String? ?? response.body,
    );
  }

  void dispose() => _http.close();
}

class NotionApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  NotionApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'NotionApiException($statusCode, $code): $message';
}

class NotionQueryResult {
  final List<Map<String, dynamic>> results;
  final bool hasMore;
  final String? nextCursor;

  NotionQueryResult({
    required this.results,
    required this.hasMore,
    this.nextCursor,
  });

  factory NotionQueryResult.fromJson(Map<String, dynamic> json) {
    return NotionQueryResult(
      results: (json['results'] as List).cast<Map<String, dynamic>>(),
      hasMore: json['has_more'] as bool,
      nextCursor: json['next_cursor'] as String?,
    );
  }
}
```

---

## Confluence REST API

Confluence Cloud exposes REST APIs under `https://<your-domain>.atlassian.net/wiki/rest/api/`. Authentication is the same as Jira (API token basic auth or OAuth 2.0, both via Atlassian identity).

### Confluence Pages and Spaces

**List spaces**: `GET /wiki/rest/api/space?limit=25&start=0`

**Get a space**: `GET /wiki/rest/api/space/{spaceKey}?expand=description.view,homepage`

**Create a page**:

`POST /wiki/rest/api/content`

```json
{
  "type": "page",
  "title": "Login Screen Design Spec",
  "space": { "key": "DESIGN" },
  "ancestors": [{ "id": "parent-page-id" }],
  "body": {
    "storage": {
      "value": "<h2>Overview</h2><p>Login screen wireframe and specification.</p><ac:image ac:width=\"800\"><ri:attachment ri:filename=\"wireframe-login.png\" /></ac:image>",
      "representation": "storage"
    }
  }
}
```

**Update a page**: `PUT /wiki/rest/api/content/{contentId}` — requires the current `version.number` incremented by 1.

```json
{
  "type": "page",
  "title": "Login Screen Design Spec (Updated)",
  "version": { "number": 2 },
  "body": {
    "storage": {
      "value": "<h2>Overview</h2><p>Updated login screen wireframe v2.</p>",
      "representation": "storage"
    }
  }
}
```

**Get a page**: `GET /wiki/rest/api/content/{contentId}?expand=body.storage,version,ancestors`

**Search**: `GET /wiki/rest/api/content/search?cql=space=DESIGN AND type=page AND title~"login"&limit=25`

### Confluence Attachments

**Upload attachment**: `POST /wiki/rest/api/content/{contentId}/child/attachment`

Uses multipart form upload. Set `X-Atlassian-Token: no-check` header. The `minorEdit` parameter controls whether the upload generates a notification.

**List attachments**: `GET /wiki/rest/api/content/{contentId}/child/attachment`

**Reference in page body** (storage format): Use `<ac:image><ri:attachment ri:filename="wireframe.png" /></ac:image>` to embed an uploaded attachment.

**Download an attachment**: `GET /wiki/rest/api/content/{contentId}/child/attachment/{attachmentId}/download`

---

## Issue Sync Strategies

Synchronizing issues between tools (e.g., Jira to Linear, or Jira to Notion) requires careful design around data flow direction, conflict handling, and deduplication.

### One-Way Push

The simplest strategy: changes in the source system are pushed to the destination. The destination is treated as read-only (from the sync perspective).

**Implementation pattern**:
1. Listen for webhook events from the source (or poll on a schedule).
2. Map the source issue fields to the destination's schema.
3. Create or update the corresponding entity in the destination.
4. Store a mapping record (source ID to destination ID) in a persistent store.

**When to use**: Status dashboards, archival, or when one tool is the single source of truth.

### Two-Way Sync

Both systems can originate changes, which must propagate to the other.

**Implementation pattern**:
1. Listen for webhooks from both systems.
2. On each event, determine if the change originated from the sync itself (to prevent echo loops).
3. Apply field mapping and push the change to the other system.
4. Use `lastSyncedAt` timestamps and field-level version tracking.

**Echo loop prevention**: Tag synced updates with a marker (e.g., a custom field or comment prefix like `[sync]`). When processing an incoming webhook, check for this marker and skip if present.

### Conflict Resolution

When the same field is changed in both systems between sync cycles:

| Strategy | Description | Best For |
|----------|-------------|----------|
| Last-write-wins | Most recent timestamp wins | Low-contention fields |
| Source-of-truth | One system always wins | Clear ownership |
| Field-level ownership | Different fields owned by different systems | Mixed workflows |
| Manual resolution | Flag conflicts for human review | Critical data |
| Merge | Combine changes (e.g., append comments) | Additive fields |

```dart
// lib/services/sync/issue_sync_service.dart

import 'dart:async';

/// Bidirectional issue sync between Jira and Linear.
class IssueSyncService {
  final JiraClient _jira;
  final LinearClient _linear;
  final SyncMappingStore _mappings;
  final IdempotencyStore _idempotency;

  IssueSyncService({
    required JiraClient jira,
    required LinearClient linear,
    required SyncMappingStore mappings,
    required IdempotencyStore idempotency,
  })  : _jira = jira,
        _linear = linear,
        _mappings = mappings,
        _idempotency = idempotency;

  /// Handle a Jira webhook event and push changes to Linear.
  Future<void> handleJiraWebhook(Map<String, dynamic> event) async {
    final eventId = event['webhookEvent'] as String;
    final issueKey = event['issue']?['key'] as String?;
    if (issueKey == null) return;

    // Idempotency: skip if we already processed this event.
    final idempotencyKey = 'jira:$eventId:$issueKey:${event['timestamp']}';
    if (await _idempotency.hasProcessed(idempotencyKey)) return;

    // Check if this change was caused by us (echo loop prevention).
    final changelogItems =
        (event['changelog']?['items'] as List?) ?? [];
    final isSyncOrigin = changelogItems.any(
      (item) => item['field'] == 'labels' &&
          (item['toString'] as String?)?.contains('[linear-sync]') == true,
    );
    if (isSyncOrigin) {
      await _idempotency.markProcessed(idempotencyKey);
      return;
    }

    // Look up existing mapping.
    final mapping = await _mappings.findByJiraKey(issueKey);

    if (mapping != null) {
      // Update existing Linear issue.
      await _updateLinearFromJira(mapping, event);
    } else if (eventId.contains('created')) {
      // Create a new Linear issue.
      await _createLinearFromJira(issueKey, event);
    }

    await _idempotency.markProcessed(idempotencyKey);
  }

  /// Handle a Linear webhook event and push changes to Jira.
  Future<void> handleLinearWebhook(Map<String, dynamic> event) async {
    final action = event['action'] as String;
    final issueId = event['data']?['id'] as String?;
    if (issueId == null) return;

    final idempotencyKey = 'linear:$action:$issueId:${event['createdAt']}';
    if (await _idempotency.hasProcessed(idempotencyKey)) return;

    // Echo loop prevention: check for sync marker in description.
    final description = event['data']?['description'] as String? ?? '';
    if (description.contains('[jira-sync]')) {
      await _idempotency.markProcessed(idempotencyKey);
      return;
    }

    final mapping = await _mappings.findByLinearId(issueId);

    if (mapping != null) {
      await _updateJiraFromLinear(mapping, event);
    } else if (action == 'create') {
      await _createJiraFromLinear(issueId, event);
    }

    await _idempotency.markProcessed(idempotencyKey);
  }

  /// Resolve conflicts using field-level ownership.
  Future<ResolvedFields> resolveConflict({
    required Map<String, dynamic> jiraFields,
    required Map<String, dynamic> linearFields,
    required SyncMapping mapping,
  }) async {
    final resolved = <String, dynamic>{};
    final conflicts = <String>[];

    // Field ownership map: which system owns which field.
    const fieldOwnership = {
      'summary': SyncSource.jira,
      'title': SyncSource.jira,
      'description': SyncSource.jira,
      'status': SyncSource.linear,
      'state': SyncSource.linear,
      'priority': SyncSource.linear,
      'assignee': SyncSource.jira,
      'labels': SyncSource.shared, // merges from both
    };

    for (final entry in fieldOwnership.entries) {
      switch (entry.value) {
        case SyncSource.jira:
          resolved[entry.key] = jiraFields[entry.key];
        case SyncSource.linear:
          resolved[entry.key] = linearFields[entry.key];
        case SyncSource.shared:
          // Merge: union of labels from both.
          final jiraLabels =
              (jiraFields[entry.key] as List?)?.cast<String>() ?? [];
          final linearLabels =
              (linearFields[entry.key] as List?)?.cast<String>() ?? [];
          resolved[entry.key] = {...jiraLabels, ...linearLabels}.toList();
      }
    }

    return ResolvedFields(fields: resolved, conflicts: conflicts);
  }

  // Private helper stubs (implementation depends on field mapping logic).
  Future<void> _updateLinearFromJira(
      SyncMapping mapping, Map<String, dynamic> event) async {
    // Map Jira fields -> Linear input, then call Linear mutation.
  }

  Future<void> _createLinearFromJira(
      String issueKey, Map<String, dynamic> event) async {
    // Create Linear issue, store mapping.
  }

  Future<void> _updateJiraFromLinear(
      SyncMapping mapping, Map<String, dynamic> event) async {
    // Map Linear fields -> Jira fields, then call Jira PUT.
  }

  Future<void> _createJiraFromLinear(
      String linearId, Map<String, dynamic> event) async {
    // Create Jira issue, store mapping.
  }
}

enum SyncSource { jira, linear, shared }

class SyncMapping {
  final String jiraKey;
  final String linearId;
  final DateTime lastSyncedAt;

  SyncMapping({
    required this.jiraKey,
    required this.linearId,
    required this.lastSyncedAt,
  });
}

class ResolvedFields {
  final Map<String, dynamic> fields;
  final List<String> conflicts;

  ResolvedFields({required this.fields, required this.conflicts});
}

// Abstract interfaces for persistence.
abstract class SyncMappingStore {
  Future<SyncMapping?> findByJiraKey(String key);
  Future<SyncMapping?> findByLinearId(String id);
  Future<void> save(SyncMapping mapping);
}

abstract class IdempotencyStore {
  Future<bool> hasProcessed(String key);
  Future<void> markProcessed(String key);
}
```

---

## Webhook Event Processing and Idempotency

Webhooks can be delivered more than once (at-least-once delivery). Every webhook handler must be idempotent.

**Idempotency implementation**:
1. Derive a unique key from the event (e.g., combination of event type, entity ID, and timestamp or event ID).
2. Before processing, check if this key exists in your idempotency store (database table, Redis, etc.).
3. If it exists, skip processing and return success.
4. If not, process the event, then persist the key.
5. Use a TTL on stored keys (e.g., 7 days) to prevent unbounded growth.

**Webhook verification**:
- Jira: Verify the webhook source IP or use a shared secret.
- Linear: HMAC-SHA256 signature in the `Linear-Signature` header.
- Notion: Currently does not support outbound webhooks natively; use polling or Notion's "automations" feature.
- Confluence: Similar to Jira, webhooks can be configured per space.

**Ordering considerations**: Webhooks may arrive out of order. Use the entity's `updatedAt` timestamp to detect stale events. If the incoming event's timestamp is older than the last synced timestamp, skip the update.

---

## API Pagination Patterns

### Cursor-Based Pagination

Used by Linear, Notion, and newer Atlassian APIs.

**How it works**: The response includes a `cursor` or `endCursor` pointing to the last item. Pass this as the `after` or `start_cursor` parameter in the next request.

**Advantages**: Stable under concurrent inserts/deletes. No duplicate or skipped items.

**Linear pagination** (GraphQL):
- Response includes `pageInfo { hasNextPage, endCursor }`.
- Pass `after: endCursor` and `first: 50` in the next query.

**Notion pagination**:
- Response includes `has_more` (boolean) and `next_cursor` (string or null).
- Pass `start_cursor: next_cursor` in the next request.

**Generic Dart paginator**:

```dart
// lib/utils/paginator.dart

/// Generic cursor-based paginator that works with any API.
class CursorPaginator<T> {
  final Future<CursorPage<T>> Function(String? cursor) _fetchPage;

  CursorPaginator(this._fetchPage);

  /// Fetch all items across all pages.
  Future<List<T>> fetchAll({int? maxPages}) async {
    final allItems = <T>[];
    String? cursor;
    var pageCount = 0;

    do {
      final page = await _fetchPage(cursor);
      allItems.addAll(page.items);
      cursor = page.hasMore ? page.nextCursor : null;
      pageCount++;
      if (maxPages != null && pageCount >= maxPages) break;
    } while (cursor != null);

    return allItems;
  }

  /// Stream items page by page (lazy loading).
  Stream<List<T>> streamPages() async* {
    String? cursor;

    do {
      final page = await _fetchPage(cursor);
      yield page.items;
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);
  }
}

class CursorPage<T> {
  final List<T> items;
  final bool hasMore;
  final String? nextCursor;

  CursorPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
}

// Usage example: paginate through all Notion database results.
//
// final paginator = CursorPaginator<Map<String, dynamic>>((cursor) async {
//   final result = await notionClient.queryDatabase(
//     databaseId,
//     startCursor: cursor,
//     pageSize: 100,
//   );
//   return CursorPage(
//     items: result.results,
//     hasMore: result.hasMore,
//     nextCursor: result.nextCursor,
//   );
// });
//
// final allPages = await paginator.fetchAll();
```

### Offset-Based Pagination

Used by Jira's v3 search endpoint and Confluence's content API.

**How it works**: The response includes `startAt`, `maxResults`, and `total`. Increment `startAt` by `maxResults` to get the next page. Continue while `startAt + results.length < total`.

**Disadvantages**: If items are inserted or deleted during pagination, you may get duplicates or miss items. Suitable for read-heavy, low-churn data.

**Jira search pagination**: The `searchJql` method in the `JiraClient` above demonstrates this pattern. Loop by incrementing `startAt` while `hasMore` is true.

---

## Batch Operations and Rate Limiting

### Batch Operations

**Jira bulk operations**:
- `POST /rest/api/3/issue/bulk` — create up to 50 issues at once.
- Bulk transitions are not natively supported; iterate and throttle.
- For updates, use individual `PUT` calls with concurrency control.

**Linear batch mutations**: GraphQL supports combining multiple mutations in a single request, but Linear's API discourages overly large payloads. Batch up to 10 mutations per request.

**Notion batch**: No native batch API. Use concurrent requests with rate limiting. Notion allows 3 requests per second for internal integrations.

### Rate Limiting

All four APIs enforce rate limits:

| API | Rate Limit | Strategy |
|-----|-----------|----------|
| Jira Cloud | ~10 req/s per user (varies) | `Retry-After` header on 429 |
| Linear | Complexity-based, ~1500/hour | `X-RateLimit-*` headers |
| Notion | 3 req/s (internal), 1 req/s (public) | `Retry-After` header on 429 |
| Confluence | Same as Jira (~10 req/s) | `Retry-After` header on 429 |

**Rate limiter implementation**: Use a token bucket or sliding window. On 429 responses, respect the `Retry-After` header.

---

## Error Handling and Retry Strategies

### HTTP Error Classification

| Status Code | Meaning | Retryable? |
|------------|---------|------------|
| 400 | Bad request — malformed body or invalid fields | No |
| 401 | Unauthorized — invalid or expired token | No (refresh token first) |
| 403 | Forbidden — insufficient permissions | No |
| 404 | Not found — entity deleted or wrong ID | No |
| 409 | Conflict — concurrent modification | Yes (re-fetch, re-apply) |
| 429 | Rate limited | Yes (after `Retry-After`) |
| 500 | Server error | Yes (with backoff) |
| 502/503/504 | Gateway/service errors | Yes (with backoff) |

### Retry Strategy

Use exponential backoff with jitter for retryable errors:

```dart
// lib/utils/retry.dart

import 'dart:math';

/// Retry a function with exponential backoff and jitter.
Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 500),
  double backoffMultiplier = 2.0,
  Duration maxDelay = const Duration(seconds: 30),
  bool Function(Exception)? shouldRetry,
}) async {
  final random = Random();
  var delay = initialDelay;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } on Exception catch (e) {
      if (attempt == maxAttempts) rethrow;

      // Check if the error is retryable.
      final retryable = shouldRetry?.call(e) ?? _isRetryableDefault(e);
      if (!retryable) rethrow;

      // Handle explicit Retry-After header.
      final retryAfter = _extractRetryAfter(e);
      final waitDuration = retryAfter ?? delay;

      // Add jitter: 50%-150% of the computed delay.
      final jitteredMs =
          (waitDuration.inMilliseconds * (0.5 + random.nextDouble())).round();
      await Future<void>.delayed(Duration(milliseconds: jitteredMs));

      // Increase delay for next attempt.
      delay = Duration(
        milliseconds:
            min((delay.inMilliseconds * backoffMultiplier).round(),
                maxDelay.inMilliseconds),
      );
    }
  }

  // Unreachable, but Dart requires it.
  throw StateError('Retry loop exited unexpectedly');
}

bool _isRetryableDefault(Exception e) {
  if (e is JiraApiException) {
    return [429, 500, 502, 503, 504].contains(e.statusCode);
  }
  if (e is NotionApiException) {
    return [429, 500, 502, 503, 504].contains(e.statusCode);
  }
  // Network errors are generally retryable.
  return e.toString().contains('SocketException') ||
      e.toString().contains('TimeoutException');
}

Duration? _extractRetryAfter(Exception e) {
  // In practice, parse the Retry-After header from the HTTP response.
  // This is a simplified placeholder — real implementations should
  // capture the header value in the exception or response object.
  if (e is JiraApiException && e.statusCode == 429) {
    return const Duration(seconds: 5); // Fallback
  }
  if (e is NotionApiException && e.statusCode == 429) {
    return const Duration(seconds: 1); // Notion is 3 req/s
  }
  return null;
}

// Forward declarations (these are defined in their respective files).
class JiraApiException implements Exception {
  final int statusCode;
  final String body;
  JiraApiException(this.statusCode, this.body);
}

class NotionApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  NotionApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });
}
```

### Circuit Breaker Pattern

For high-throughput sync jobs, implement a circuit breaker that stops requests to a failing API after a threshold of consecutive failures. Re-enable after a cooldown period. This prevents cascading failures and wasted API calls during outages.

**States**: Closed (normal) -> Open (failing, requests rejected) -> Half-Open (allow one test request).

---

## Best Practices

1. **Always verify webhook signatures.** Never trust unverified webhook payloads. Validate HMAC signatures for Linear, and source verification for Jira/Confluence.

2. **Use idempotency keys for all writes.** Store a hash of (event type + entity ID + timestamp) and check before processing. This protects against duplicate webhook deliveries.

3. **Implement field-level mapping, not whole-object sync.** Map specific fields between systems rather than attempting to mirror entire objects. Different tools have different data models and capabilities.

4. **Respect rate limits proactively.** Track your request rate client-side and throttle before hitting 429 responses. Parse `Retry-After` and `X-RateLimit-*` headers.

5. **Use cursor-based pagination when available.** Cursor-based pagination is more reliable than offset-based, especially for datasets that change during iteration.

6. **Store sync mappings durably.** Use a database table to map entity IDs across systems (e.g., Jira issue key to Linear issue ID). Include `lastSyncedAt` timestamps for conflict detection.

7. **Log all sync operations.** Maintain a structured audit log of every sync action (source event, mapped fields, destination response). This is critical for debugging sync issues.

8. **Handle ADF correctly in Jira v3.** The description field uses Atlassian Document Format. Never send plain strings where ADF is expected — the API will reject them.

9. **Set reasonable timeouts.** External API calls should have explicit connect and read timeouts (15-30 seconds). Use the retry utility for transient failures.

10. **Keep OAuth tokens refreshed.** For OAuth 2.0 integrations, refresh tokens before expiry. Jira tokens expire after 1 hour; Linear tokens also have limited lifespans.

11. **Use the `expand` parameter in Atlassian APIs.** Jira and Confluence responses are minimal by default. Request only the fields you need with `fields` (Jira) or `expand` (Confluence) to reduce payload size and latency.

12. **Test with sandbox environments.** Jira offers free developer instances at `https://developer.atlassian.com/`. Linear and Notion have free tiers suitable for development and testing.

13. **Handle partial failures in batch operations.** When creating multiple issues, some may succeed and others fail. Process results individually and retry only the failures.

14. **Use streaming/pagination for large datasets.** Never attempt to fetch thousands of issues in a single request. Always paginate and consider using Dart `Stream` for memory efficiency.

---

## Anti-Patterns

1. **Polling without backoff.** Repeatedly polling APIs at a fixed short interval (e.g., every second) instead of using webhooks. This wastes rate limit budget and creates unnecessary load. Use webhooks for real-time events and poll only as a fallback with exponential backoff.

2. **Ignoring webhook delivery guarantees.** Assuming webhooks are delivered exactly once. All major APIs provide at-least-once delivery, meaning you will receive duplicates. Without idempotency handling, this causes duplicate issues, double transitions, or corrupted sync state.

3. **Sync loops (echo effect).** System A pushes a change to System B via sync. System B fires a webhook for that change. The sync handler picks it up and pushes it back to System A. This creates an infinite loop. Always tag sync-originated changes with a marker and filter them out.

4. **Storing API tokens in code.** Hardcoding API tokens, secrets, or credentials in source code or version-controlled config files. Use environment variables, secret managers (Vault, AWS Secrets Manager), or encrypted configuration.

5. **Mapping entire objects blindly.** Attempting to copy all fields from one system to another without understanding the schema differences. This leads to data corruption, invalid field values, and lost information. Map fields explicitly and validate before writing.

6. **Ignoring pagination.** Fetching only the first page of results and assuming that is the complete dataset. APIs return at most 50-100 items per page. Always check `hasMore`, `has_more`, or compare `startAt + length < total`.

7. **Retrying non-retryable errors.** Retrying 400 (bad request) or 403 (forbidden) errors wastes time and rate limit. Only retry 429 (rate limited) and 5xx (server errors). For 401, refresh the token and retry once.

8. **Not handling version conflicts in Confluence.** Confluence requires the exact current `version.number + 1` when updating a page. If two clients update concurrently, one will fail with a 409 conflict. Always fetch the current version before updating.

9. **Using offset pagination for real-time data.** Offset-based pagination can miss items or return duplicates if the underlying dataset changes during iteration. Use cursor-based pagination for actively-changing data, or snapshot the query with an `updatedBefore` filter.

10. **Fire-and-forget webhook processing.** Processing webhook events inline in the HTTP handler without a queue. If processing takes too long, the webhook delivery times out and is retried, potentially causing duplicate processing. Acknowledge the webhook immediately (return 200), enqueue the event, and process asynchronously.

11. **Unbounded concurrency on batch operations.** Sending hundreds of concurrent API requests without a concurrency limit. This overwhelms rate limits and causes cascading 429 errors. Use a semaphore or pool to limit concurrent requests (e.g., 5-10 in parallel).

12. **Not cleaning up idempotency keys.** Storing idempotency keys forever without a TTL. Over time this table grows unbounded. Set a TTL (e.g., 7 days) and periodically purge expired keys.

---

## Sources & References

- Jira Cloud REST API v3 documentation: https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/
- Atlassian OAuth 2.0 (3LO) authorization: https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/
- Linear API reference (GraphQL): https://developers.linear.app/docs/graphql/working-with-the-graphql-api
- Linear webhook documentation: https://developers.linear.app/docs/graphql/webhooks
- Notion API reference: https://developers.notion.com/reference/intro
- Notion authentication guide: https://developers.notion.com/docs/authorization
- Confluence Cloud REST API documentation: https://developer.atlassian.com/cloud/confluence/rest/v1/intro/
- Atlassian Document Format (ADF) specification: https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/
- JQL syntax reference: https://support.atlassian.com/jira-software-cloud/docs/use-advanced-search-with-jira-query-language-jql/
