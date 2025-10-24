# Event-Driven Platform Deployment Guide

## Prerequisites

Before deploying the event-driven platform, ensure you have:

### Required Components

- ✅ **Kubernetes Cluster**: v1.28+ (your cluster: v1.31.13+k3s1)
- ✅ **ArgoCD**: Installed and accessible
- ✅ **External Secrets Operator**: Installed (for Vault integration)
- ✅ **Vault**: Running with Kubernetes auth configured
- ✅ **Longhorn**: Storage class available (or alternative CSI)
- ✅ **kubectl**: Configured with cluster admin access

### Node Requirements

**Minimum**: 3 worker nodes for high availability

**Your Configuration**:
- 5 Falkenstein workers (cax41: 16 CPUs, 32GB RAM each)
- Deployment targets 3 workers (2 without gitops-observability, 1 fallback)

### Resource Requirements

Per component:
- **Kafka Brokers**: 3 × (1 CPU, 4Gi RAM, 10Gi storage) = **3 CPUs, 12Gi RAM, 30Gi storage**
- **Knative Eventing**: ~0.5 CPU, 1Gi RAM
- **Knative Kafka Broker**: ~0.5 CPU, 1Gi RAM
- **Strimzi Operator**: 0.2 CPU, 256Mi RAM

**Total**: ~4 CPUs, 14Gi RAM, 30Gi storage

## Deployment Steps

### Step 1: Clone and Initialize Repository

```bash
# Clone the repository
cd /home/it
git clone https://github.com/yourusername/gitops-eventing.git
cd gitops-eventing

# Initialize Git (if creating from scratch)
git init
git add .
git commit -m "Initial commit: Event-driven platform with Knative and Kafka"
git branch -M main
git remote add origin https://github.com/yourusername/gitops-eventing.git
git push -u origin main
```

### Step 2: Configure Vault Secrets (Optional)

If you need to store Kafka credentials or other secrets:

```bash
# Store Kafka admin credentials in Vault
kubectl exec -n vault platform-vault-0 -- vault kv put secret/eventing/kafka \
  admin-username=admin \
  admin-password=$(openssl rand -base64 32)

# Create External Secret to sync from Vault
kubectl apply -f infrastructure/externalsecrets/
```

### Step 3: Create ArgoCD AppProject

```bash
# Create the eventing AppProject
kubectl apply -f applications/appproject.yaml

# Verify project creation
kubectl get appproject -n argocd eventing
```

### Step 4: Deploy ApplicationSet

```bash
# Deploy the ApplicationSet (this triggers all deployments)
kubectl apply -f applications/applicationset.yaml

# Verify ApplicationSet creation
kubectl get applicationset -n argocd eventing-platform
```

### Step 5: Monitor Deployment

ArgoCD will deploy components in waves. Monitor progress:

```bash
# Watch applications sync
kubectl get applications -n argocd -l app.kubernetes.io/part-of=event-driven-platform -w

# Expected applications (in order):
# 1. eventing-namespaces (wave 0)
# 2. eventing-strimzi-operator (wave 1)
# 3. eventing-knative-operator (wave 1)
# 4. eventing-kafka-cluster (wave 2)
# 5. eventing-knative-eventing (wave 3)
# 6. eventing-kafka-broker-config (wave 3)
# 7. eventing-kafka-broker-controller (wave 4)
# 8. eventing-kafka-broker-dataplane (wave 4)
# 9. eventing-default-kafka-broker (wave 5)
# 10. eventing-network-policies (wave 6)
```

### Step 6: Verify Component Health

#### Verify Namespaces

```bash
kubectl get namespaces | grep -E "eventing|knative"
# Expected:
# eventing             Active   Xm
# knative-eventing     Active   Xm
# knative-operator     Active   Xm
# strimzi-system       Active   Xm
```

#### Verify Operators

```bash
# Strimzi Operator
kubectl get pods -n strimzi-system
# Expected: 1 pod running

# Knative Operator
kubectl get pods -n knative-operator
# Expected: 1 pod running
```

#### Verify Kafka Cluster

```bash
# Check Kafka custom resource
kubectl get kafka -n eventing event-cluster

# Check Kafka pods
kubectl get pods -n eventing -l strimzi.io/cluster=event-cluster
# Expected: 3 broker pods + 1 entity operator pod

# Check Kafka cluster status
kubectl describe kafka -n eventing event-cluster | grep -A 5 "Status:"
# Should show: Ready
```

#### Verify Knative Eventing

```bash
# Check KnativeEventing CR
kubectl get knativeeventing -n knative-eventing

# Check Knative pods
kubectl get pods -n knative-eventing
# Expected:
# - eventing-controller (2 replicas)
# - eventing-webhook (2 replicas)
# - imc-controller (1 replica)
# - kafka-controller (1 replica)
# - kafka-broker-receiver (1+ replicas)
# - kafka-broker-dispatcher (1+ replicas)
```

#### Verify Default Broker

```bash
# Check broker status
kubectl get broker -n knative-eventing default

# Get broker URL
kubectl get broker -n knative-eventing default -o jsonpath='{.status.address.url}'
# Expected: http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-eventing/default
```

### Step 7: Deploy Example Event Consumer (Optional)

Test the platform with a simple event display service:

```bash
# Deploy example consumer
kubectl apply -f examples/sources/event-consumer-service.yaml

# Verify deployment
kubectl get pods -n default -l app=event-display
kubectl get trigger -n default display-all-events
```

### Step 8: Send Test Events

```bash
# Make the send-event.sh script executable
chmod +x examples/cloudevents/send-event.sh

# Send a test event
cd examples/cloudevents
./send-event.sh

# View received events
kubectl logs -n default -l app=event-display -f
```

## Post-Deployment Configuration

### Create Namespace-Specific Brokers

For applications that need isolated brokers:

```bash
# Create namespace
kubectl create namespace my-app

# Deploy namespace broker
kubectl apply -f examples/brokers/namespace-broker.yaml -n my-app

# Verify broker
kubectl get broker -n my-app
```

### Configure Event Triggers

Create triggers to route events to your services:

```bash
# Edit examples/triggers/event-filter-trigger.yaml for your use case
# Update: type, source, subscriber service

kubectl apply -f examples/triggers/event-filter-trigger.yaml
kubectl get trigger -n <namespace>
```

### Set Up Event Sources

#### Kafka Source (for external Kafka)

```bash
# Edit examples/sources/kafka-source-example.yaml
# Update: bootstrap servers, topics, consumer group

kubectl apply -f examples/sources/kafka-source-example.yaml
kubectl get kafkasource -n <namespace>
```

#### Ping Source (scheduled events)

```bash
# Edit examples/sources/ping-source-example.yaml
# Update: schedule, data, sink

kubectl apply -f examples/sources/ping-source-example.yaml
kubectl get pingsource -n <namespace>
```

## Operations

### Scaling

#### Scale Kafka Brokers

```bash
# Edit kafka-cluster.yaml
# Change spec.kafka.replicas: 3 → 5

# Commit and push (GitOps)
git add environments/production/kafka-cluster.yaml
git commit -m "Scale Kafka to 5 brokers"
git push

# Or apply directly (not recommended)
kubectl patch kafka event-cluster -n eventing --type merge -p '{"spec":{"kafka":{"replicas":5}}}'
```

#### Scale Knative Controllers

```bash
# Edit knative-eventing-cr.yaml
# Change replicas in workloads section

# Commit and push
git add environments/production/knative-eventing-cr.yaml
git commit -m "Scale eventing-controller to 3 replicas"
git push
```

### Monitoring

#### View Metrics

```bash
# Kafka metrics endpoint
kubectl port-forward -n eventing svc/event-cluster-kafka-bootstrap 9090:9090

# Access Prometheus metrics
curl http://localhost:9090/metrics
```

#### Check Event Flow

```bash
# Broker metrics
kubectl get broker -n knative-eventing default -o yaml | grep -A 20 status

# Trigger metrics
kubectl get trigger -n <namespace> <trigger-name> -o yaml | grep -A 10 status

# Dead letter sink logs (failed events)
kubectl logs -n knative-eventing -l app=event-dead-letter-sink
```

### Troubleshooting

#### Kafka Not Ready

```bash
# Check Kafka cluster status
kubectl describe kafka -n eventing event-cluster

# Check broker logs
kubectl logs -n eventing event-cluster-kafka-0

# Common issues:
# - Insufficient storage (increase PVC size)
# - Node affinity constraints (check node labels)
# - Resource limits (increase CPU/memory)
```

#### Events Not Delivered

```bash
# Check broker status
kubectl get broker -n knative-eventing default -o yaml

# Check trigger status
kubectl get trigger -n <namespace> <trigger-name> -o yaml

# Check dispatcher logs
kubectl logs -n knative-eventing -l app=kafka-broker-dispatcher

# Common issues:
# - Incorrect filter attributes
# - Subscriber service not available
# - Network policy blocking traffic
```

#### High Event Latency

```bash
# Check Kafka lag
kubectl exec -n eventing event-cluster-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups

# Check receiver/dispatcher resources
kubectl top pods -n knative-eventing

# Solutions:
# - Increase receiver/dispatcher replicas
# - Increase Kafka broker resources
# - Increase topic partitions
```

### Backup and Recovery

#### Backup Kafka Data

```bash
# Kafka data is stored in Longhorn PVCs
# Use Longhorn backup features or Velero

# List PVCs
kubectl get pvc -n eventing

# Backup with Velero
velero backup create kafka-backup --include-namespaces eventing
```

#### Restore Kafka Cluster

```bash
# Restore with Velero
velero restore create --from-backup kafka-backup

# Or redeploy from GitOps (loses data)
kubectl delete kafka -n eventing event-cluster
# ArgoCD will recreate
```

### Upgrades

#### Upgrade Strimzi Operator

```bash
# Update version in applicationset.yaml
# Change: version: "0.48.0" → "0.49.0"

git add applications/applicationset.yaml
git commit -m "Upgrade Strimzi to 0.49.0"
git push

# Manual CRD upgrade required
kubectl apply -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.49.0/strimzi-cluster-operator-0.49.0.yaml
```

#### Upgrade Knative Eventing

```bash
# Update version in knative-eventing-cr.yaml
# Change: version: "1.15.0" → "1.16.0"

git add environments/production/knative-eventing-cr.yaml
git commit -m "Upgrade Knative Eventing to 1.16.0"
git push

# Operator handles rolling update
```

#### Upgrade Kafka Version

```bash
# Update version in kafka-cluster.yaml
# Change: version: 3.9.0 → 3.10.0

# IMPORTANT: Follow Kafka upgrade procedure
# 1. Upgrade brokers
# 2. Update inter.broker.protocol.version
# 3. Update log.message.format.version

git add environments/production/kafka-cluster.yaml
git commit -m "Upgrade Kafka to 3.10.0"
git push

# Monitor rolling update
kubectl get pods -n eventing -l strimzi.io/cluster=event-cluster -w
```

## Security Hardening

### Enable Network Policies

Network policies are deployed by default. To verify:

```bash
kubectl get networkpolicies -n eventing
kubectl get networkpolicies -n knative-eventing
```

### Restrict Broker Access

To limit which namespaces can send events:

```bash
# Edit network-policies.yaml
# Modify ingress rules to whitelist specific namespaces

# Apply changes
git add environments/production/network-policies.yaml
git commit -m "Restrict broker access to specific namespaces"
git push
```

### Enable Vault Secret Encryption

All application secrets should be stored in Vault:

```bash
# Store application credentials
kubectl exec -n vault platform-vault-0 -- vault kv put secret/eventing/myapp \
  api-key=secret-key-here \
  database-password=secure-password

# Create ExternalSecret
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend-eventing
    kind: ClusterSecretStore
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: secret/eventing/myapp
      property: api-key
EOF
```

## Performance Tuning

### Kafka Performance

```yaml
# In kafka-cluster.yaml
spec:
  kafka:
    config:
      # Increase batch size for throughput
      batch.size: 16384
      linger.ms: 10

      # Increase buffer sizes
      socket.send.buffer.bytes: 131072
      socket.receive.buffer.bytes: 131072

      # Increase max message size
      message.max.bytes: 10485760

      # Tune replication
      replica.fetch.max.bytes: 10485760
      num.replica.fetchers: 2
```

### Knative Performance

```yaml
# In knative-eventing-cr.yaml
spec:
  workloads:
  - name: kafka-broker-receiver
    replicas: 3  # Increase for higher throughput
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 2000m
        memory: 2Gi
```

## Monitoring Integration

### Prometheus ServiceMonitors

```bash
# Create ServiceMonitor for Kafka metrics
kubectl apply -f examples/servicemonitors/kafka.yaml

# Verify metrics collection
kubectl get servicemonitor -n observability
```

### Grafana Dashboards

Import pre-built dashboards:
- **Kafka**: Dashboard ID 11962
- **Strimzi**: Dashboard ID 14012
- **Knative Eventing**: Custom dashboard (to be created)

## Next Steps

1. Read [CloudEvents Guide](CLOUDEVENTS_GUIDE.md) for event schema design
2. Explore [Examples](../examples/) for common patterns
3. Review [Architecture](ARCHITECTURE.md) for design decisions

## Support

For issues and questions:
- Check ArgoCD application status
- Review pod logs
- Consult upstream documentation
- Open GitHub issue

## References

- [Knative Eventing Docs](https://knative.dev/docs/eventing/)
- [Strimzi Docs](https://strimzi.io/documentation/)
- [Kafka Operations](https://kafka.apache.org/documentation/#operations)
