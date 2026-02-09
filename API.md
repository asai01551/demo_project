# 📡 API Documentation

Complete API reference for Webhook Relay & Logger system.

## Base URLs

- **Receiver Service**: `http://localhost:3001` (or your deployed URL)
- **Logger Service**: `http://localhost:3002`
- **Dashboard Service**: `http://localhost:3004`

## Authentication

All API requests require an API key passed in the `X-API-Key` header.

```bash
curl -H "X-API-Key: your_api_key_here" http://localhost:3001/webhook/{endpoint_id}
```

## Receiver Service API

### Send Webhook

Receive and queue a webhook for processing.

**Endpoint**: `POST /webhook/:endpointId`

**Headers**:
- `X-API-Key`: Your API key (required)
- `Content-Type`: application/json

**Parameters**:
- `endpointId` (path): The endpoint ID to send the webhook to

**Request Body**: Any valid JSON

**Example**:
```bash
curl -X POST http://localhost:3001/webhook/abc123 \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "user.created",
    "data": {
      "id": 123,
      "email": "user@example.com"
    }
  }'
```

**Response** (202 Accepted):
```json
{
  "success": true,
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "message": "Webhook accepted for processing"
}
```

**Error Responses**:
- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Endpoint not found or inactive
- `500 Internal Server Error`: Server error

---

### Get Webhook Event Status

Retrieve the status of a specific webhook event.

**Endpoint**: `GET /webhook/:endpointId/events/:eventId`

**Headers**:
- `X-API-Key`: Your API key (required)

**Parameters**:
- `endpointId` (path): The endpoint ID
- `eventId` (path): The event ID returned when webhook was sent

**Example**:
```bash
curl http://localhost:3001/webhook/abc123/events/550e8400-e29b-41d4-a716-446655440000 \
  -H "X-API-Key: your_api_key"
```

**Response** (200 OK):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "delivered",
  "receivedAt": "2024-01-15T10:30:00.000Z",
  "forwardedAt": "2024-01-15T10:30:02.500Z",
  "attempts": 1,
  "lastAttempt": {
    "id": "attempt-id",
    "attemptNumber": 1,
    "status": "success",
    "responseCode": 200,
    "attemptedAt": "2024-01-15T10:30:02.000Z"
  }
}
```

**Status Values**:
- `pending`: Webhook received, waiting to be processed
- `forwarding`: Currently being forwarded
- `delivered`: Successfully delivered to destination
- `failed`: Failed after all retry attempts

---

### Health Check

Check service health status.

**Endpoint**: `GET /health`

**Example**:
```bash
curl http://localhost:3001/health
```

**Response** (200 OK):
```json
{
  "status": "healthy",
  "service": "receiver",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "checks": {
    "database": "ok",
    "redis": "ok"
  }
}
```

---

### Liveness Probe

Kubernetes liveness probe endpoint.

**Endpoint**: `GET /health/live`

**Response**: `200 OK` with `{"alive": true}`

---

### Readiness Probe

Kubernetes readiness probe endpoint.

**Endpoint**: `GET /health/ready`

**Response**: `200 OK` with `{"ready": true}` if database is accessible

---

## Logger Service API

### Get Event Logs

Retrieve complete logs for a webhook event.

**Endpoint**: `GET /logs/events/:eventId`

**Parameters**:
- `eventId` (path): The event ID

**Example**:
```bash
curl http://localhost:3002/logs/events/550e8400-e29b-41d4-a716-446655440000
```

**Response** (200 OK):
```json
{
  "event": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "delivered",
    "receivedAt": "2024-01-15T10:30:00.000Z",
    "forwardedAt": "2024-01-15T10:30:02.500Z",
    "method": "POST",
    "headers": {
      "content-type": "application/json",
      "user-agent": "curl/7.68.0"
    }
  },
  "endpoint": {
    "id": "abc123",
    "name": "Production Webhook",
    "destinationUrl": "https://example.com/webhook"
  },
  "payload": {
    "body": {
      "event": "user.created",
      "data": {
        "id": 123
      }
    },
    "headers": {},
    "method": "POST",
    "query": {}
  },
  "attempts": [
    {
      "id": "attempt-id",
      "attemptNumber": 1,
      "status": "success",
      "responseCode": 200,
      "attemptedAt": "2024-01-15T10:30:02.000Z"
    }
  ],
  "logs": []
}
```

---

### Get Payload from S3

Retrieve a specific payload from S3.

**Endpoint**: `GET /logs/payload/:s3Key`

**Parameters**:
- `s3Key` (path): The S3 key for the payload

**Example**:
```bash
curl http://localhost:3002/logs/payload/payloads/2024-01-15/event-id.json
```

**Response** (200 OK): The payload JSON

---

### Get Response from S3

Retrieve a specific response from S3.

**Endpoint**: `GET /logs/response/:s3Key`

**Parameters**:
- `s3Key` (path): The S3 key for the response

**Example**:
```bash
curl http://localhost:3002/logs/response/responses/2024-01-15/event-id.json
```

**Response** (200 OK): The response JSON

---

### Search Logs

Search webhook events with filters.

**Endpoint**: `GET /logs/search`

**Query Parameters**:
- `endpointId` (optional): Filter by endpoint ID
- `status` (optional): Filter by status (pending, forwarding, delivered, failed)
- `startDate` (optional): Filter events after this date (ISO 8601)
- `endDate` (optional): Filter events before this date (ISO 8601)
- `limit` (optional): Number of results (default: 50, max: 100)
- `offset` (optional): Pagination offset (default: 0)

**Example**:
```bash
curl "http://localhost:3002/logs/search?endpointId=abc123&status=delivered&limit=20"
```

**Response** (200 OK):
```json
{
  "events": [
    {
      "id": "event-id",
      "status": "delivered",
      "receivedAt": "2024-01-15T10:30:00.000Z",
      "endpoint": {
        "id": "abc123",
        "name": "Production Webhook",
        "destinationUrl": "https://example.com/webhook"
      },
      "deliveryAttempts": [
        {
          "attemptNumber": 1,
          "status": "success",
          "responseCode": 200
        }
      ]
    }
  ],
  "pagination": {
    "total": 150,
    "limit": 20,
    "offset": 0
  }
}
```

---

### Get Endpoint Statistics

Retrieve statistics for an endpoint.

**Endpoint**: `GET /logs/stats/:endpointId`

**Query Parameters**:
- `days` (optional): Number of days to retrieve (default: 7)

**Example**:
```bash
curl "http://localhost:3002/logs/stats/abc123?days=30"
```

**Response** (200 OK):
```json
{
  "stats": [
    {
      "date": "2024-01-15",
      "totalReceived": 150,
      "totalDelivered": 145,
      "totalFailed": 5,
      "avgResponseTime": 250
    },
    {
      "date": "2024-01-14",
      "totalReceived": 200,
      "totalDelivered": 198,
      "totalFailed": 2,
      "avgResponseTime": 230
    }
  ]
}
```

---

## Dashboard Service API

### Get All Endpoints

Retrieve all endpoints for the authenticated user.

**Endpoint**: `GET /api/endpoints`

**Headers**:
- `X-API-Key`: Your API key (required)

**Example**:
```bash
curl http://localhost:3004/api/endpoints \
  -H "X-API-Key: your_api_key"
```

**Response** (200 OK):
```json
{
  "endpoints": [
    {
      "id": "abc123",
      "name": "Production Webhook",
      "destinationUrl": "https://example.com/webhook",
      "isActive": true,
      "createdAt": "2024-01-01T00:00:00.000Z",
      "stats": [
        {
          "date": "2024-01-15",
          "totalReceived": 150,
          "totalDelivered": 145,
          "totalFailed": 5
        }
      ]
    }
  ]
}
```

---

### Create Endpoint

Create a new webhook endpoint.

**Endpoint**: `POST /api/endpoints`

**Headers**:
- `X-API-Key`: Your API key (required)
- `Content-Type`: application/json

**Request Body**:
```json
{
  "name": "My Webhook",
  "destinationUrl": "https://example.com/webhook",
  "secret": "optional-webhook-secret"
}
```

**Example**:
```bash
curl -X POST http://localhost:3004/api/endpoints \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Webhook",
    "destinationUrl": "https://example.com/webhook"
  }'
```

**Response** (201 Created):
```json
{
  "endpoint": {
    "id": "new-endpoint-id",
    "name": "My Webhook",
    "destinationUrl": "https://example.com/webhook",
    "isActive": true,
    "createdAt": "2024-01-15T10:30:00.000Z"
  }
}
```

---

### Update Endpoint

Update an existing endpoint.

**Endpoint**: `PATCH /api/endpoints/:endpointId`

**Headers**:
- `X-API-Key`: Your API key (required)
- `Content-Type`: application/json

**Request Body** (all fields optional):
```json
{
  "name": "Updated Name",
  "destinationUrl": "https://new-url.com/webhook",
  "secret": "new-secret",
  "isActive": false
}
```

**Example**:
```bash
curl -X PATCH http://localhost:3004/api/endpoints/abc123 \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"isActive": false}'
```

**Response** (200 OK):
```json
{
  "endpoint": {
    "id": "abc123",
    "name": "Updated Name",
    "destinationUrl": "https://new-url.com/webhook",
    "isActive": false,
    "updatedAt": "2024-01-15T10:30:00.000Z"
  }
}
```

---

### Delete Endpoint

Delete an endpoint and all associated data.

**Endpoint**: `DELETE /api/endpoints/:endpointId`

**Headers**:
- `X-API-Key`: Your API key (required)

**Example**:
```bash
curl -X DELETE http://localhost:3004/api/endpoints/abc123 \
  -H "X-API-Key: your_api_key"
```

**Response** (200 OK):
```json
{
  "success": true
}
```

---

### Get Endpoint Events

Retrieve events for a specific endpoint.

**Endpoint**: `GET /api/endpoints/:endpointId/events`

**Query Parameters**:
- `limit` (optional): Number of results (default: 50)
- `offset` (optional): Pagination offset (default: 0)
- `status` (optional): Filter by status

**Example**:
```bash
curl "http://localhost:3004/api/endpoints/abc123/events?limit=20&status=delivered" \
  -H "X-API-Key: your_api_key"
```

**Response**: Same as Logger Service search endpoint

---

### Get Event Details

Retrieve detailed information about a specific event.

**Endpoint**: `GET /api/events/:eventId`

**Example**:
```bash
curl http://localhost:3004/api/events/550e8400-e29b-41d4-a716-446655440000 \
  -H "X-API-Key: your_api_key"
```

**Response**: Same as Logger Service event logs endpoint

---

### Get Endpoint Statistics

Retrieve statistics for an endpoint.

**Endpoint**: `GET /api/endpoints/:endpointId/stats`

**Query Parameters**:
- `days` (optional): Number of days (default: 7)

**Example**:
```bash
curl "http://localhost:3004/api/endpoints/abc123/stats?days=30" \
  -H "X-API-Key: your_api_key"
```

**Response**: Same as Logger Service stats endpoint

---

## Rate Limiting

All endpoints are rate-limited to **1000 requests per 15 minutes** per IP address.

**Rate Limit Headers**:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1642248000
```

**Rate Limit Exceeded** (429 Too Many Requests):
```json
{
  "error": "Too many requests from this IP, please try again later."
}
```

---

## Error Responses

All error responses follow this format:

```json
{
  "error": "Error message description"
}
```

**Common HTTP Status Codes**:
- `400 Bad Request`: Invalid request parameters
- `401 Unauthorized`: Missing or invalid API key
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error
- `503 Service Unavailable`: Service temporarily unavailable

---

## Webhooks

When forwarding webhooks to your destination URL, the system adds these headers:

```
User-Agent: WebhookRelay/1.0
X-Webhook-Event-Id: 550e8400-e29b-41d4-a716-446655440000
X-Webhook-Attempt: 1
```

Your endpoint should respond with:
- `2xx` status code for success
- Any other status code will trigger a retry

---

## SDK Examples

### Node.js

```javascript
const axios = require('axios');

const apiKey = 'your_api_key';
const baseUrl = 'http://localhost:3001';

async function sendWebhook(endpointId, payload) {
  try {
    const response = await axios.post(
      `${baseUrl}/webhook/${endpointId}`,
      payload,
      {
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json'
        }
      }
    );
    console.log('Webhook sent:', response.data);
    return response.data.eventId;
  } catch (error) {
    console.error('Error:', error.response?.data || error.message);
  }
}

// Usage
sendWebhook('abc123', {
  event: 'user.created',
  data: { id: 123 }
});
```

### Python

```python
import requests

api_key = 'your_api_key'
base_url = 'http://localhost:3001'

def send_webhook(endpoint_id, payload):
    response = requests.post(
        f'{base_url}/webhook/{endpoint_id}',
        json=payload,
        headers={
            'X-API-Key': api_key,
            'Content-Type': 'application/json'
        }
    )
    response.raise_for_status()
    return response.json()

# Usage
result = send_webhook('abc123', {
    'event': 'user.created',
    'data': {'id': 123}
})
print(f"Event ID: {result['eventId']}")
```

---

For more examples and integration guides, see the main README.md.