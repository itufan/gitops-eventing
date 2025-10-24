# Manual Deployment Guide

This guide provides step-by-step instructions for deploying the event-driven platform when the automated ApplicationSet approach needs manual intervention.

## Prerequisites

- Kubernetes cluster v1.28+ (tested on v1.31.13+k3s1)
- kubectl configured with cluster admin access
- ArgoCD installed
- Longhorn storage class available

## Deployment Options

### Option 1: Automated (ApplicationSet)

Deploy everything via ArgoCD ApplicationSet:

```bash
# 1. Apply AppProject
kubectl apply -f applications/appproject.yaml

# 2. Apply Simplified ApplicationSet
kubectl apply -f applications/applicationset-simple.yaml

# 3. Monitor deployment
watch kubectl get applications -n argocd -l app.kubernetes.io/part-of=event-driven-platform
```

### Option 2: Manual Step-by-Step

If the ApplicationSet encounters issues, deploy manually:

#### Step 1: Install Operators

```bash
# Install Strimzi Operator (latest stable)
kubectl create -f 'https://strimzi.io/install/latest?namespace=strimzi-system' -n strimzi-system

# Configure to watch all namespaces
kubectl set env deployment/strimzi-cluster-operator -n strimzi-system STRIMZI_NAMESPACE='*'

# Install Knative Operator (v1.15.2 - compatible with K8s 1.31)
kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.15.2/operator.yaml

# Wait for operators to be ready
kubectl rollout status deployment/strimzi-cluster-operator -n strimzi-system --timeout=120s
kubectl rollout status deployment/knative-operator -n knative-operator --timeout=120s
```

#### Step 2: Create Namespaces

```bash
kubectl apply -f infrastructure/strimzi-operator/namespace.yaml
kubectl apply -f infrastructure/knative-operator/namespace.yaml
kubectl apply -f infrastructure/externalsecrets/namespace.yaml
```

#### Step 3: Deploy Kafka Cluster

```bash
# Apply Kafka cluster (3 brokers, 10GB each)
kubectl apply -f environments/production/kafka-cluster.yaml

# Wait for Kafka to be ready (this takes 5-10 minutes)
kubectl wait kafka/event-cluster -n eventing --for=condition=Ready --timeout=600s

# Verify Kafka pods
kubectl get pods -n eventing -l strimzi.io/cluster=event-cluster
# Expected: 3 broker pods + 1 entity-operator pod
```

#### Step 4: Deploy Knative Eventing

```bash
# Apply Knative Eventing CR
kubectl apply -f environments/production/knative-eventing-cr.yaml

# Wait for Knative Eventing to be ready (this takes 3-5 minutes)
kubectl wait knativeeventing/knative-eventing -n knative-eventing --for=condition=Ready --timeout=300s

# Verify Knative pods
kubectl get pods -n knative-eventing
# Expected: eventing-controller, eventing-webhook, imc-controller, etc.
```

#### Step 5: Install Kafka Broker Integration

```bash
# Install Kafka broker controller (compatible with Knative 1.15.x)
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.15.0/eventing-kafka-controller.yaml

# Install Kafka broker data plane
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.15.0/eventing-kafka-broker.yaml

# Apply broker configuration
kubectl apply -f environments/production/kafka-broker-config.yaml
```

#### Step 6: Deploy Default Broker

```bash
# Deploy default Kafka broker and dead-letter-sink
kubectl apply -f environments/production/kafka-broker-integration.yaml

# Wait for broker to be ready
kubectl wait broker/default -n knative-eventing --for=condition=Ready --timeout=120s

# Get broker URL
kubectl get broker default -n knative-eventing -o jsonpath='{.status.address.url}'
```

#### Step 7: Apply Network Policies

```bash
kubectl apply -f environments/production/network-policies.yaml
```

## Verification

### Check All Components

```bash
# Operators
kubectl get pods -n strimzi-system
kubectl get pods -n knative-operator

# Kafka
kubectl get kafka -n eventing
kubectl get pods -n eventing

# Knative Eventing
kubectl get knativeeventing -n knative-eventing
kubectl get pods -n knative-eventing

# Default Broker
kubectl get broker -n knative-eventing
```

### Test Event Flow

```bash
# Deploy example event display service
kubectl apply -f examples/sources/event-consumer-service.yaml

# Send test event
chmod +x examples/cloudevents/send-event.sh
./examples/cloudevents/send-event.sh

# View received events
kubectl logs -n default -l app=event-display -f
```

## Troubleshooting

### Operators Not Starting

```bash
# Check operator logs
kubectl logs -n strimzi-system -l name=strimzi-cluster-operator
kubectl logs -n knative-operator -l app=knative-operator

# Common issues:
# - Kubernetes version incompatibility
# - RBAC permissions missing
# - CRD conflicts from previous installations
```

### Kafka Cluster Not Creating Pods

```bash
# Check Kafka resource status
kubectl describe kafka event-cluster -n eventing

# Check operator logs for errors
kubectl logs -n strimzi-system -l name=strimzi-cluster-operator --tail=100

# Common issues:
# - Unsupported Kafka version
# - Insufficient storage
# - Node affinity constraints
# - Operator not watching namespace
```

### Knative Eventing Not Ready

```bash
# Check KnativeEventing status
kubectl describe knativeeventing knative-eventing -n knative-eventing

# Check operator logs
kubectl logs -n knative-operator -l app=knative-operator

# Common issues:
# - Version incompatibility with K8s
# - Webhook certificate issues
# - Missing CRDs
```

### Events Not Delivered

```bash
# Check broker status
kubectl describe broker default -n knative-eventing

# Check trigger status
kubectl get trigger -n <namespace> <trigger-name> -o yaml

# Check dispatcher logs
kubectl logs -n knative-eventing -l app=kafka-broker-dispatcher

# Common issues:
# - Kafka not accessible
# - Network policies blocking traffic
# - Incorrect filter attributes
```

## Version Compatibility Matrix

| Component | Version | K8s Requirement |
|-----------|---------|----------------|
| Kubernetes | 1.31.13+k3s1 | - |
| Strimzi Operator | 0.44.0+ (latest) | 1.19+ |
| Kafka | 3.8.0 | - |
| Knative Operator | 1.15.2 | 1.28-1.31 |
| Knative Eventing | 1.15.0 | 1.28-1.31 |
| Kafka Broker | 1.15.0 | Matches Knative |

## Clean Up

To remove the entire platform:

```bash
# Delete all applications (if using ArgoCD)
kubectl delete applicationset eventing-platform-simple -n argocd
kubectl delete application -n argocd -l app.kubernetes.io/part-of=event-driven-platform

# Delete resources manually
kubectl delete -f environments/production/kafka-broker-integration.yaml
kubectl delete -f environments/production/kafka-broker-config.yaml
kubectl delete -f environments/production/knative-eventing-cr.yaml
kubectl delete -f environments/production/kafka-cluster.yaml

# Delete operators
kubectl delete -f https://github.com/knative/operator/releases/download/knative-v1.15.2/operator.yaml
kubectl delete -f https://strimzi.io/install/latest?namespace=strimzi-system -n strimzi-system

# Delete namespaces
kubectl delete namespace eventing knative-eventing knative-operator strimzi-system
```

## Next Steps

1. Review [ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions
2. Read [CLOUDEVENTS_GUIDE.md](docs/CLOUDEVENTS_GUIDE.md) for event schema
3. Explore [examples/](examples/) for common patterns
4. Set up monitoring (Prometheus ServiceMonitors)
5. Configure External Secrets for Vault integration

## Support

For issues:
- Check [DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed troubleshooting
- Review operator logs
- Consult upstream documentation:
  - [Strimzi](https://strimzi.io/documentation/)
  - [Knative Eventing](https://knative.dev/docs/eventing/)
  - [CloudEvents](https://cloudevents.io/)
