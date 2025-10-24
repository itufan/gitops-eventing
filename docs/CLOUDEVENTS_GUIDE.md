# CloudEvents Guide

## Overview

CloudEvents is a specification for describing event data in a common way. This guide explains how to use CloudEvents with the event-driven platform.

## CloudEvents v1.0 Specification

### Required Attributes

Every CloudEvent **MUST** include these attributes:

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `id` | String | Unique identifier for the event | `"A234-1234-1234"` |
| `source` | URI | Context in which event occurred | `"https://orders-service.example.com"` |
| `specversion` | String | CloudEvents spec version | `"1.0"` |
| `type` | String | Event type identifier | `"com.example.order.created"` |

### Optional Attributes

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `datacontenttype` | String | Content type of data | `"application/json"` |
| `dataschema` | URI | Schema of the data | `"https://example.com/schema/v1"` |
| `subject` | String | Subject of the event | `"/orders/12345"` |
| `time` | Timestamp | When event occurred (RFC3339) | `"2025-10-24T12:00:00Z"` |

### Extension Attributes

You can add custom attributes for your domain:

```json
{
  "specversion": "1.0",
  "type": "com.example.order.created",
  "source": "orders-service",
  "id": "123",
  "customerid": "cust-456",
  "priority": "high",
  "region": "eu-west"
}
```

## Event Type Naming Convention

Use **reverse domain name notation** for event types:

```
com.{company}.{context}.{action}
```

### Examples

```
✅ Good:
com.example.order.created
com.example.payment.processed
com.example.inventory.depleted
com.example.user.registered

❌ Bad:
order-created
OrderCreated
order_created_event
```

### Type Hierarchy

Organize types hierarchically:

```
com.example.order.*             # All order events
com.example.order.created        # New order
com.example.order.updated        # Order modified
com.example.order.cancelled      # Order cancelled
com.example.order.item.added     # Item added to order
com.example.order.item.removed   # Item removed from order
```

## Source URI Conventions

The `source` identifies the context where the event originated.

### Service-Based Sources

```
Format: {service-name}
Examples:
  "orders-service"
  "payment-service"
  "inventory-service"
```

### URL-Based Sources

```
Format: https://{domain}/{path}
Examples:
  "https://api.example.com/orders"
  "https://api.example.com/v1/payments"
```

### Instance-Based Sources

```
Format: {service-name}/{instance-id}
Examples:
  "orders-service/pod-abc123"
  "worker/job-456"
```

## Event Structure Examples

### Minimal Event

```json
{
  "specversion": "1.0",
  "type": "com.example.test.ping",
  "source": "test-service",
  "id": "1"
}
```

### Standard Event

```json
{
  "specversion": "1.0",
  "type": "com.example.order.created",
  "source": "orders-service",
  "id": "A234-1234-1234",
  "time": "2025-10-24T12:00:00Z",
  "datacontenttype": "application/json",
  "subject": "/orders/12345",
  "data": {
    "orderId": "12345",
    "customerId": "customer-abc",
    "totalAmount": 59.98,
    "currency": "USD",
    "status": "pending"
  }
}
```

### Event with Extensions

```json
{
  "specversion": "1.0",
  "type": "com.example.payment.processed",
  "source": "payment-service",
  "id": "PAY-789",
  "time": "2025-10-24T12:05:30Z",
  "datacontenttype": "application/json",
  "subject": "/payments/789",
  "priority": "high",
  "correlationid": "ORDER-12345",
  "region": "eu-west",
  "data": {
    "paymentId": "789",
    "orderId": "12345",
    "amount": 59.98,
    "currency": "USD",
    "method": "credit_card",
    "status": "completed"
  }
}
```

## Content Modes

CloudEvents can be transmitted in different modes:

### Binary Content Mode (Recommended)

CloudEvents attributes in HTTP headers, data in body:

```http
POST /default HTTP/1.1
Host: kafka-broker-ingress.knative-eventing.svc.cluster.local
Content-Type: application/json
Ce-Specversion: 1.0
Ce-Type: com.example.order.created
Ce-Source: orders-service
Ce-Id: A234-1234-1234
Ce-Time: 2025-10-24T12:00:00Z

{
  "orderId": "12345",
  "customerId": "customer-abc",
  "totalAmount": 59.98
}
```

**Benefits**:
- Efficient routing (no body parsing)
- Smaller payload
- Faster filtering

### Structured Content Mode

Everything in JSON body:

```http
POST /default HTTP/1.1
Host: kafka-broker-ingress.knative-eventing.svc.cluster.local
Content-Type: application/cloudevents+json

{
  "specversion": "1.0",
  "type": "com.example.order.created",
  "source": "orders-service",
  "id": "A234-1234-1234",
  "time": "2025-10-24T12:00:00Z",
  "datacontenttype": "application/json",
  "data": {
    "orderId": "12345",
    "customerId": "customer-abc",
    "totalAmount": 59.98
  }
}
```

**Benefits**:
- Human-readable
- Easy to log/debug
- Portable (no special headers)

## Sending Events

### From curl (Binary Mode)

```bash
curl -v -X POST \
  http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default \
  -H "Content-Type: application/json" \
  -H "Ce-Specversion: 1.0" \
  -H "Ce-Type: com.example.test.event" \
  -H "Ce-Source: curl-test" \
  -H "Ce-Id: $(uuidgen)" \
  -H "Ce-Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -d '{"message": "Hello from curl"}'
```

### From curl (Structured Mode)

```bash
curl -v -X POST \
  http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default \
  -H "Content-Type: application/cloudevents+json" \
  -d '{
    "specversion": "1.0",
    "type": "com.example.test.event",
    "source": "curl-test",
    "id": "'$(uuidgen)'",
    "time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "datacontenttype": "application/json",
    "data": {
      "message": "Hello from curl"
    }
  }'
```

### From Python

```python
import requests
import uuid
from datetime import datetime, timezone

def send_cloudevent(broker_url, event_type, source, data):
    """Send CloudEvent in binary content mode"""
    headers = {
        'Content-Type': 'application/json',
        'Ce-Specversion': '1.0',
        'Ce-Type': event_type,
        'Ce-Source': source,
        'Ce-Id': str(uuid.uuid4()),
        'Ce-Time': datetime.now(timezone.utc).isoformat()
    }

    response = requests.post(broker_url, json=data, headers=headers)
    response.raise_for_status()
    return response

# Usage
broker_url = "http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default"
send_cloudevent(
    broker_url=broker_url,
    event_type="com.example.order.created",
    source="python-service",
    data={"orderId": "12345", "amount": 99.99}
)
```

### From Go

```go
package main

import (
    "context"
    "log"

    cloudevents "github.com/cloudevents/sdk-go/v2"
)

type OrderCreated struct {
    OrderID string  `json:"orderId"`
    Amount  float64 `json:"amount"`
}

func main() {
    // Create CloudEvents client
    c, err := cloudevents.NewClientHTTP(
        cloudevents.WithTarget("http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default"),
    )
    if err != nil {
        log.Fatal(err)
    }

    // Create event
    event := cloudevents.NewEvent()
    event.SetType("com.example.order.created")
    event.SetSource("go-service")
    event.SetData(cloudevents.ApplicationJSON, OrderCreated{
        OrderID: "12345",
        Amount:  99.99,
    })

    // Send event
    ctx := context.Background()
    if result := c.Send(ctx, event); cloudevents.IsUndelivered(result) {
        log.Fatalf("failed to send: %v", result)
    }
}
```

### From Node.js

```javascript
const { CloudEvent, HTTP } = require('cloudevents');
const axios = require('axios');

async function sendCloudEvent(brokerUrl, eventType, source, data) {
  // Create CloudEvent
  const event = new CloudEvent({
    type: eventType,
    source: source,
    data: data,
  });

  // Convert to HTTP message (binary mode)
  const message = HTTP.binary(event);

  // Send via axios
  const response = await axios.post(brokerUrl, message.body, {
    headers: message.headers,
  });

  return response.data;
}

// Usage
const brokerUrl = 'http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default';
sendCloudEvent(
  brokerUrl,
  'com.example.order.created',
  'nodejs-service',
  { orderId: '12345', amount: 99.99 }
);
```

## Receiving Events

### Event Handler Signature

Your service receives events as HTTP POST requests:

```
POST /your-endpoint HTTP/1.1
Content-Type: application/json
Ce-Specversion: 1.0
Ce-Type: com.example.order.created
Ce-Source: orders-service
Ce-Id: A234-1234-1234
Ce-Time: 2025-10-24T12:00:00Z

{
  "orderId": "12345",
  "amount": 99.99
}
```

### Python Flask Example

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/events', methods=['POST'])
def handle_event():
    # Extract CloudEvents headers
    event_type = request.headers.get('Ce-Type')
    event_source = request.headers.get('Ce-Source')
    event_id = request.headers.get('Ce-Id')

    # Get event data
    data = request.json

    print(f"Received event: type={event_type}, source={event_source}, id={event_id}")
    print(f"Data: {data}")

    # Process event based on type
    if event_type == 'com.example.order.created':
        handle_order_created(data)
    elif event_type == 'com.example.payment.processed':
        handle_payment_processed(data)
    else:
        print(f"Unknown event type: {event_type}")

    # Return 200 OK (required for Knative)
    return jsonify({"status": "processed"}), 200

def handle_order_created(data):
    order_id = data.get('orderId')
    print(f"Processing order {order_id}")
    # Your business logic here

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### Go HTTP Handler Example

```go
package main

import (
    "encoding/json"
    "log"
    "net/http"

    cloudevents "github.com/cloudevents/sdk-go/v2"
)

type OrderCreated struct {
    OrderID string  `json:"orderId"`
    Amount  float64 `json:"amount"`
}

func handleCloudEvent(w http.ResponseWriter, r *http.Request) {
    // Parse CloudEvent
    event, err := cloudevents.NewEventFromHTTPRequest(r)
    if err != nil {
        log.Printf("Failed to parse CloudEvent: %v", err)
        http.Error(w, "Bad Request", http.StatusBadRequest)
        return
    }

    log.Printf("Received event: type=%s, source=%s, id=%s",
        event.Type(), event.Source(), event.ID())

    // Handle event based on type
    switch event.Type() {
    case "com.example.order.created":
        var order OrderCreated
        if err := event.DataAs(&order); err != nil {
            log.Printf("Failed to unmarshal data: %v", err)
            http.Error(w, "Bad Request", http.StatusBadRequest)
            return
        }
        handleOrderCreated(order)
    default:
        log.Printf("Unknown event type: %s", event.Type())
    }

    // Return 200 OK
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "processed"})
}

func handleOrderCreated(order OrderCreated) {
    log.Printf("Processing order %s", order.OrderID)
    // Your business logic here
}

func main() {
    http.HandleFunc("/events", handleCloudEvent)
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

## Event Filtering

Triggers use CloudEvents attributes to filter events:

### Filter by Type

```yaml
filter:
  attributes:
    type: com.example.order.created
```

### Filter by Source

```yaml
filter:
  attributes:
    source: orders-service
```

### Filter by Multiple Attributes

```yaml
filter:
  attributes:
    type: com.example.order.created
    source: orders-service
    priority: high
```

### Filter by Subject Pattern

```yaml
filter:
  attributes:
    type: com.example.order.updated
    subject: "/orders/vip/*"  # Note: Exact match, not glob
```

## Best Practices

### Event Design

1. **Use meaningful types**: `com.example.order.created` not `order-event`
2. **Keep data minimal**: Include only essential information
3. **Use subject for hierarchy**: `/orders/12345/items/67`
4. **Add correlation IDs**: Link related events
5. **Include timestamps**: Always set `time` attribute

### Error Handling

1. **Return 2xx for success**: `200`, `201`, `202` accepted
2. **Return 4xx for permanent failures**: Event will go to DLQ
3. **Return 5xx for retries**: Knative will retry with backoff
4. **Log errors**: Include event ID for tracing

### Performance

1. **Batch events**: Send multiple events in quick succession
2. **Use binary mode**: Faster routing and filtering
3. **Keep payloads small**: < 1MB recommended
4. **Async processing**: Return HTTP 200 immediately, process async

### Security

1. **Validate event structure**: Check required fields
2. **Verify event source**: Trust but verify
3. **Sanitize data**: Prevent injection attacks
4. **Rate limit**: Protect against event floods

## Event Patterns

### Command Pattern

```json
{
  "type": "com.example.order.create.requested",
  "source": "api-gateway",
  "data": {
    "customerId": "123",
    "items": [...]
  }
}
```

Response:
```json
{
  "type": "com.example.order.created",
  "source": "orders-service",
  "correlationid": "original-event-id",
  "data": {
    "orderId": "456"
  }
}
```

### Change Data Capture

```json
{
  "type": "com.example.database.row.updated",
  "source": "postgres-cdc",
  "subject": "/tables/orders/rows/12345",
  "data": {
    "before": {...},
    "after": {...},
    "operation": "UPDATE"
  }
}
```

### Notification Pattern

```json
{
  "type": "com.example.notification.email.required",
  "source": "notification-service",
  "priority": "high",
  "data": {
    "to": "user@example.com",
    "template": "order-confirmation",
    "variables": {...}
  }
}
```

## Debugging Events

### View All Events (Dead Letter Sink)

```bash
kubectl logs -n knative-eventing -l app=event-dead-letter-sink -f
```

### View Specific Trigger Events

```bash
# Deploy event-display for specific trigger
kubectl apply -f examples/sources/event-consumer-service.yaml

# View logs
kubectl logs -n default -l app=event-display -f
```

### Check Broker Status

```bash
kubectl describe broker -n knative-eventing default
```

### Trace Event Flow

Add tracing headers:
```http
Ce-Traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

## References

- [CloudEvents Spec v1.0](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md)
- [CloudEvents SDK Go](https://github.com/cloudevents/sdk-go)
- [CloudEvents SDK Python](https://github.com/cloudevents/sdk-python)
- [CloudEvents SDK Node.js](https://github.com/cloudevents/sdk-javascript)
- [Knative Eventing Documentation](https://knative.dev/docs/eventing/)

## Next Steps

- Review [Architecture](ARCHITECTURE.md) for platform design
- Follow [Deployment Guide](DEPLOYMENT.md) for setup
- Explore [Examples](../examples/) for patterns
