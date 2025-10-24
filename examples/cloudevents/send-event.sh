#!/bin/bash
# Example: Send CloudEvents to Knative Kafka Broker
# This script demonstrates how to send events to the broker from within the cluster

set -e

# Configuration
BROKER_NAME="${BROKER_NAME:-default}"
BROKER_NAMESPACE="${BROKER_NAMESPACE:-knative-eventing}"
EVENT_TYPE="${EVENT_TYPE:-com.example.test.event}"
EVENT_SOURCE="${EVENT_SOURCE:-test-script}"

# Get broker URL
BROKER_URL=$(kubectl get broker ${BROKER_NAME} -n ${BROKER_NAMESPACE} -o jsonpath='{.status.address.url}')

if [ -z "$BROKER_URL" ]; then
  echo "Error: Could not retrieve broker URL"
  echo "Make sure broker '${BROKER_NAME}' exists in namespace '${BROKER_NAMESPACE}'"
  exit 1
fi

echo "Broker URL: $BROKER_URL"

# Generate CloudEvent
EVENT_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create CloudEvent JSON
EVENT_DATA=$(cat <<EOF
{
  "specversion": "1.0",
  "type": "${EVENT_TYPE}",
  "source": "${EVENT_SOURCE}",
  "id": "${EVENT_ID}",
  "time": "${TIMESTAMP}",
  "datacontenttype": "application/json",
  "data": {
    "message": "Hello from test script",
    "timestamp": "${TIMESTAMP}",
    "environment": "production"
  }
}
EOF
)

echo "Sending CloudEvent..."
echo "$EVENT_DATA" | jq .

# Send event using curl (from a pod in the cluster)
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -v -X POST \
  -H "Content-Type: application/cloudevents+json" \
  -d "$EVENT_DATA" \
  "${BROKER_URL}"

echo "Event sent successfully!"
echo ""
echo "To view events, check the logs of your subscriber service or the dead-letter-sink:"
echo "  kubectl logs -n knative-eventing -l app=event-dead-letter-sink"
