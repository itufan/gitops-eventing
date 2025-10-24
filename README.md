# Event-Driven Platform with Knative Eventing & Kafka

Production-ready event-driven architecture deployed via GitOps on Kubernetes, featuring Knative Eventing with Apache Kafka and CloudEvents v1.0 compliance.

## Features

- **CloudEvents v1.0**: Standards-based event format
- **Knative Eventing**: Powerful event routing and delivery
- **Apache Kafka**: Durable, scalable event streaming (KRaft mode)
- **100% GitOps**: Automated deployment via ArgoCD
- **High Availability**: 3-broker Kafka cluster with replication
- **Cluster-Internal**: No external ingress, secure by design
- **Production-Ready**: Network policies, monitoring, backups

## Quick Start

```bash
# 1. Deploy via ArgoCD
kubectl apply -f applications/appproject.yaml
kubectl apply -f applications/applicationset.yaml

# 2. Wait for components to sync (5-10 minutes)
kubectl get applications -n argocd -l app.kubernetes.io/part-of=event-driven-platform -w

# 3. Verify deployment
kubectl get broker -n knative-eventing default
kubectl get kafka -n eventing event-cluster

# 4. Send test event
chmod +x examples/cloudevents/send-event.sh
./examples/cloudevents/send-event.sh
```

## Architecture

```
Applications → Knative Broker → Kafka Cluster → Triggers → Subscribers
                     ↓
            CloudEvents v1.0 Compliant
```

### Components

| Component | Version | Purpose |
|-----------|---------|---------|
| **Strimzi Operator** | 0.48.0 | Manages Kafka lifecycle |
| **Apache Kafka** | 3.9.0 | Event streaming platform |
| **Knative Operator** | 1.19.4 | Manages Knative components |
| **Knative Eventing** | 1.15.0 | Event routing framework |
| **Kafka Broker** | 1.19.7 | Native Kafka integration |

### Kafka Configuration

- **Brokers**: 3 replicas (high availability)
- **Mode**: KRaft (no ZooKeeper)
- **Storage**: 10GB per broker (Longhorn)
- **Replication**: Factor 3, Min ISR 2
- **Retention**: 7 days
- **Network**: Cluster-internal, no TLS

### Node Placement

Deployed on Falkenstein workers:
- **Preferred**: Workers without `workload=gitops-observability`
  - `orderlust-workers-general-fsn1-jbz` (data-services)
  - `orderlust-workers-general-fsn1-wpy` (applications)
- **Fallback**: Any Falkenstein worker (HA)

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** - Design decisions and component overview
- **[Deployment Guide](docs/DEPLOYMENT.md)** - Installation and operations
- **[CloudEvents Guide](docs/CLOUDEVENTS_GUIDE.md)** - Event schema and usage

## Examples

### Send an Event

```bash
curl -X POST \
  http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default \
  -H "Ce-Specversion: 1.0" \
  -H "Ce-Type: com.example.order.created" \
  -H "Ce-Source: my-service" \
  -H "Ce-Id: $(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{"orderId": "12345", "amount": 99.99}'
```

### Create a Trigger

```yaml
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: order-processor
  namespace: default
spec:
  broker: default
  filter:
    attributes:
      type: com.example.order.created
  subscriber:
    ref:
      apiVersion: v1
      kind: Service
      name: order-processor
```

More examples in [`examples/`](examples/) directory.

## Repository Structure

```
gitops-eventing/
├── infrastructure/          # Operators and base resources
│   ├── strimzi-operator/   # Kafka operator
│   ├── knative-operator/   # Knative operator
│   ├── externalsecrets/    # Secret management
│   └── clustersecretstore.yaml
├── environments/
│   └── production/         # Production configuration
│       ├── kafka-cluster.yaml
│       ├── knative-eventing-cr.yaml
│       ├── kafka-broker-config.yaml
│       └── network-policies.yaml
├── applications/           # ArgoCD resources
│   ├── appproject.yaml
│   └── applicationset.yaml
├── examples/               # Usage examples
│   ├── brokers/
│   ├── triggers/
│   ├── cloudevents/
│   └── sources/
└── docs/                   # Documentation
    ├── ARCHITECTURE.md
    ├── DEPLOYMENT.md
    └── CLOUDEVENTS_GUIDE.md
```

## Deployment Waves

ArgoCD deploys components in order:

1. **Wave 0**: Namespaces
2. **Wave 1**: Operators (Strimzi, Knative)
3. **Wave 2**: Kafka Cluster
4. **Wave 3**: Knative Eventing + Config
5. **Wave 4**: Kafka Broker Integration
6. **Wave 5**: Default Broker
7. **Wave 6**: Network Policies

## Monitoring

### View Broker Status

```bash
kubectl get broker -n knative-eventing default -o yaml
```

### Check Kafka Cluster

```bash
kubectl get kafka -n eventing event-cluster
kubectl get pods -n eventing -l strimzi.io/cluster=event-cluster
```

### View Event Logs

```bash
# Dead letter sink (failed events)
kubectl logs -n knative-eventing -l app=event-dead-letter-sink

# Kafka broker logs
kubectl logs -n eventing event-cluster-kafka-0
```

### Metrics

Kafka and Knative metrics exposed in Prometheus format:

```bash
# Forward Kafka metrics
kubectl port-forward -n eventing svc/event-cluster-kafka-bootstrap 9090:9090

# Access metrics
curl http://localhost:9090/metrics
```

## Operations

### Scale Kafka Brokers

```bash
# Edit kafka-cluster.yaml
spec.kafka.replicas: 3 → 5

# Commit and push
git add environments/production/kafka-cluster.yaml
git commit -m "Scale Kafka to 5 brokers"
git push
```

### Create Namespace Broker

```bash
kubectl apply -f examples/brokers/namespace-broker.yaml -n my-namespace
```

### Debug Event Flow

```bash
# Deploy event display service
kubectl apply -f examples/sources/event-consumer-service.yaml

# View received events
kubectl logs -n default -l app=event-display -f
```

## Security

- **Network Policies**: Cluster-internal only, no external access
- **No TLS**: Plaintext communication within trusted cluster
- **Vault Integration**: Secrets managed via External Secrets Operator
- **RBAC**: Kubernetes role-based access control

## Performance

### Throughput

- **Kafka**: ~100K events/sec (depends on message size)
- **Knative**: ~10K events/sec per receiver pod
- **End-to-end latency**: <100ms (p95)

### Resource Usage

- **Kafka Brokers**: 3 CPUs, 12Gi RAM, 30Gi storage
- **Knative Eventing**: ~1 CPU, 2Gi RAM
- **Total**: ~4 CPUs, 14Gi RAM, 30Gi storage

## Troubleshooting

### Kafka Not Ready

```bash
kubectl describe kafka -n eventing event-cluster
kubectl logs -n eventing event-cluster-kafka-0
```

### Events Not Delivered

```bash
kubectl get trigger -n <namespace> <name> -o yaml
kubectl logs -n knative-eventing -l app=kafka-broker-dispatcher
```

### High Latency

```bash
kubectl top pods -n eventing
kubectl top pods -n knative-eventing
```

See [Deployment Guide](docs/DEPLOYMENT.md#troubleshooting) for more.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit pull request

## License

MIT License - see [LICENSE](LICENSE) for details

## Support

- **Documentation**: [docs/](docs/)
- **Examples**: [examples/](examples/)
- **Issues**: [GitHub Issues](https://github.com/itufan/gitops-eventing/issues)

## Acknowledgments

- [Knative Project](https://knative.dev/)
- [Strimzi](https://strimzi.io/)
- [CloudEvents](https://cloudevents.io/)
- [ArgoCD](https://argo-cd.readthedocs.io/)

## Related Projects

- [gitops-observability](https://github.com/itufan/gitops-observability) - Monitoring stack
- [orderkust/infra](https://github.com/itufan/infra) - Platform infrastructure
