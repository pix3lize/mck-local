#!/bin/bash

# Get all running images
IMAGES=$(kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s '[[:space:]]' '\n' | sort | uniq)

NODE="k3d-mongocluster-agent-2"
OUTPUT_DIR="./exported-images"

mkdir -p "$OUTPUT_DIR"

echo "Exporting images from k3d cluster..."

for IMAGE in $IMAGES; do
  # Create safe filename (replace / and : with -)
  FILENAME=$(echo "$IMAGE" | sed 's/[\/:]/-/g')
  echo "Exporting $IMAGE to $FILENAME.tar"
  
  # Export image from k3d node
  docker exec $NODE ctr -n k8s.io images export "/tmp/$FILENAME.tar" "$IMAGE"
  
  # Copy to host
  docker cp "$NODE:/tmp/$FILENAME.tar" "$OUTPUT_DIR/$FILENAME.tar"
  
  # Clean up temp file in node
  docker exec $NODE rm "/tmp/$FILENAME.tar"
done

echo "All images exported to $OUTPUT_DIR/"
