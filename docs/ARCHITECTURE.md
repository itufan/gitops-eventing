# Event-Driven Platform Architecture

## Overview

This document describes the architecture and design decisions for the event-driven platform built on Knative Eventing and Apache Kafka.

## Components

### 1. Apache Kafka (via Strimzi)

**Purpose**: Event streaming platform for durable, scalable event storage

**Configuration**:
- **Mode**: KRaft (no ZooKeeper) - Kafka's new consensus protocol
- **Brokers**: 3 replicas for high availability
- **Storage**: 10GB per broker (Longhorn persistent volumes)
- **Replication Factor**: 3 (all data replicated to all brokers)
- **Min In-Sync Replicas**: 2 (ensures data durability)
- **Retention**: 7 days (168 hours)
- **Network**: Cluster-internal only, plaintext listeners (no TLS)

**Why Kafka?**
- **Durability**: Events are persisted to disk and replicated
- **Scalability**: Can handle high-throughput event streams
- **Replay**: Events can be re-consumed from any point in time
- **Integration**: Native integration with Knative Eventing

### 2. Knative Eventing

**Purpose**: CloudEvents-based event routing and delivery platform

**Configuration**:
- **Version**: 1.15.0
- **Components**: Eventing only (no Serving component)
- **High Availability**: 2 replicas for controllers
- **Source Support**: Kafka source enabled

**Key Features**:
- **CloudEvents Native**: All events conform to CloudEvents v1.0 spec
- **Broker/Trigger Model**: Decouples event producers from consumers
- **Delivery Guarantees**: Configurable retry and dead-letter-queue
- **Event Filtering**: Route events based on CloudEvents attributes

### 3. Knative Kafka Broker

**Purpose**: Native Kafka integration for Knative Eventing

**Configuration**:
- **Controller**: eventing-kafka-controller (v1.19.7)
- **Data Plane**: eventing-kafka-broker (v1.19.7)
- **Storage Mode**: Binary content mode (optimal for routing)

**Benefits**:
- **Zero Copies**: Events stored directly in Kafka
- **Native Performance**: No translation overhead
- **Kafka Features**: Leverage Kafka's durability and scalability

### 4. Strimzi Operator

**Purpose**: Manages Kafka cluster lifecycle on Kubernetes

**Configuration**:
- **Version**: 0.48.0
- **Watched Namespaces**: `eventing` only
- **Network Policies**: Enabled

**Responsibilities**:
- Kafka cluster deployment and upgrades
- Topic and user management (Entity Operator)
- Configuration validation
- Metrics exposure

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Service A  │  │   Service B  │  │   Service C  │      │
│  │  (Producer)  │  │  (Consumer)  │  │   (Both)     │      │
│  └──────┬───────┘  └───────▲──────┘  └──────┬───▲───┘      │
│         │                   │                 │   │          │
│         │ POST              │ HTTP            │   │          │
│         │ CloudEvents       │ CloudEvents     │   │          │
└─────────┼───────────────────┼─────────────────┼───┼──────────┘
          │                   │                 │   │
┌─────────▼───────────────────┴─────────────────▼───┴──────────┐
│              Knative Eventing (knative-eventing)              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │               Kafka Broker (default)                   │  │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐        │  │
│  │  │ Ingress  │───▶│ Triggers │───▶│ Delivery │        │  │
│  │  └────┬─────┘    └─────┬────┘    └────┬─────┘        │  │
│  └───────┼────────────────┼──────────────┼──────────────┘  │
│          │                │              │                  │
│          │ Produce        │ Filter       │ Consume          │
└──────────┼────────────────┼──────────────┼──────────────────┘
           │                │              │
┌──────────▼────────────────▼──────────────▼──────────────────┐
│              Apache Kafka (eventing namespace)                │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Broker 1  │  │  Broker 2  │  │  Broker 3  │            │
│  │ (Primary)  │  │  (Replica) │  │  (Replica) │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│                                                               │
│  Topics: knative-broker-default, __consumer_offsets, etc.    │
└───────────────────────────────────────────────────────────────┘
```

## Event Flow

1. **Event Production**:
   - Application sends CloudEvent to Broker URL via HTTP POST
   - Broker ingress validates CloudEvent format
   - Event stored in Kafka topic (binary content mode)

2. **Event Routing**:
   - Triggers query Kafka for events matching their filters
   - Filters based on CloudEvents attributes (type, source, etc.)
   - Matched events routed to subscriber services

3. **Event Delivery**:
   - HTTP POST to subscriber service with CloudEvent
   - Retry on failure (configurable backoff)
   - Dead-letter-sink for permanently failed events

## Design Decisions

### Why No TLS?

**Decision**: Disable TLS for Kafka inter-broker and client communication

**Rationale**:
- Cluster-internal only deployment (no external access)
- Reduces latency and CPU overhead
- Simplifies certificate management
- Network policies provide namespace-level isolation
- Focus on application-level security (authentication, authorization)

**Trade-offs**:
- Events transmitted in plaintext within cluster
- Acceptable for trusted cluster environment
- Can be enabled later if compliance requires it

### Why KRaft Mode?

**Decision**: Use KRaft instead of ZooKeeper for Kafka metadata

**Rationale**:
- Simpler architecture (fewer components)
- Better scalability (metadata stored in Kafka itself)
- Faster controller failover
- Future-proof (ZooKeeper deprecated in Kafka 4.0)

### Why Knative Eventing Without Serving?

**Decision**: Deploy only Eventing component, not Serving

**Rationale**:
- Event-driven architecture focus (not serverless functions)
- Existing application deployment with standard Kubernetes resources
- Serving adds unnecessary complexity for this use case
- Can be added later if serverless workloads needed

### Node Placement Strategy

**Configuration**:
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100  # Primary
      preference:
        matchExpressions:
        - key: location
          operator: In
          values: [falkenstein]
        - key: workload
          operator: NotIn
          values: [gitops-observability]
    - weight: 50   # Fallback
      preference:
        matchExpressions:
        - key: location
          operator: In
          values: [falkenstein]
```

**Rationale**:
- **Primary**: Falkenstein workers without `workload=gitops-observability`
  - `orderlust-workers-general-fsn1-jbz` (workload=data-services)
  - `orderlust-workers-general-fsn1-wpy` (workload=applications)
- **Fallback**: Any Falkenstein worker (ensures 3+ nodes for HA)
- **Anti-affinity**: Spreads replicas across nodes for fault tolerance

**Benefits**:
- Dedicated nodes for eventing platform (preferred)
- Falls back to shared nodes if needed (flexibility)
- Minimum 3 nodes available (high availability)
- Co-location with data services (data-services node)

## Scalability

### Horizontal Scaling

**Kafka Brokers**:
- Can scale to 5+ brokers (increase replicas in Kafka CR)
- Rebalancing handled automatically by Kafka
- Consider storage requirements (10GB × brokers)

**Knative Eventing**:
- Controllers scaled to 2 replicas (active-passive)
- Data plane (receivers/dispatchers) auto-scales based on load
- Can configure HPA for auto-scaling

**Triggers**:
- Each trigger is an independent consumer
- Scales with number of subscriber services
- Consumer group per trigger (parallel consumption)

### Vertical Scaling

**Kafka Brokers**:
- Increase CPU: 500m → 2000m
- Increase Memory: 2Gi → 8Gi
- Increase Storage: 10Gi → 100Gi+

**Knative Components**:
- Usually CPU-bound (routing logic)
- Memory scales with event throughput
- Monitor metrics for bottlenecks

## High Availability

### Kafka HA

- **3 Brokers**: Survives 1 broker failure
- **Replication Factor 3**: All data on all brokers
- **Min ISR 2**: Requires 2 replicas to acknowledge writes
- **Pod Anti-Affinity**: Each broker on different node

### Knative HA

- **2 Controllers**: Active-passive failover
- **Pod Anti-Affinity**: Controllers on different nodes
- **Webhook Redundancy**: 2 replicas for admission control

### Network HA

- **Network Policies**: Prevent unauthorized access
- **Service Mesh**: Can add Istio/Linkerd for mTLS (future)
- **DNS**: Kubernetes DNS provides service discovery

## Monitoring & Observability

### Metrics

**Kafka Metrics** (via JMX Exporter):
- Broker metrics: CPU, memory, disk, network
- Topic metrics: message rate, byte rate, lag
- Consumer group metrics: lag, rate

**Knative Metrics**:
- Broker metrics: event rate, latency
- Trigger metrics: delivery rate, error rate
- Controller metrics: reconciliation rate

**Integration**:
- All metrics exposed in Prometheus format
- ServiceMonitors for automatic scraping
- Pre-built dashboards in Grafana

### Logging

**Kafka Logs**:
- Structured JSON logs
- Collected by Promtail → Loki
- Retention: 7 days (matches event retention)

**Knative Logs**:
- CloudEvents delivery logs
- Error logs for failed deliveries
- Audit logs for broker access

### Tracing

**CloudEvents Context Propagation**:
- `traceparent` header support
- Integration with Tempo (optional)
- Distributed tracing across services

## Security

### Network Security

- **Network Policies**: Restrict traffic to necessary paths
- **Cluster-Internal Only**: No public ingress
- **Namespace Isolation**: Policies between namespaces

### Secret Management

- **Vault Integration**: Via External Secrets Operator
- **Service Accounts**: Kubernetes RBAC for pod identity
- **No Hardcoded Secrets**: All secrets from Vault

### Event Security

- **Schema Validation**: CloudEvents spec enforcement
- **Authentication**: Can add API keys/tokens per producer
- **Authorization**: Can add RBAC for broker access (future)

## Future Enhancements

### Short Term

1. **Event Schema Registry**: Define and validate event schemas
2. **Additional Sources**: HTTP, GCP Pub/Sub, AWS SQS
3. **Event Replay**: Tools for replaying historical events
4. **Monitoring Dashboard**: Grafana dashboard for eventing

### Long Term

1. **Multi-Region**: Kafka MirrorMaker for cross-region replication
2. **Event Mesh**: Knative EventMesh for multi-cluster routing
3. **Serverless Functions**: Add Knative Serving for FaaS
4. **Stream Processing**: Kafka Streams or Flink integration

## Related Documentation

- [Deployment Guide](DEPLOYMENT.md)
- [CloudEvents Guide](CLOUDEVENTS_GUIDE.md)
- [Examples](../examples/)

## References

- [Knative Eventing Documentation](https://knative.dev/docs/eventing/)
- [Strimzi Documentation](https://strimzi.io/documentation/)
- [CloudEvents Specification](https://github.com/cloudevents/spec)
- [Kafka Documentation](https://kafka.apache.org/documentation/)
