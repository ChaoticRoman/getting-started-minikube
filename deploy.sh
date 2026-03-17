#!/usr/bin/env bash
set -euo pipefail

# Point docker CLI at minikube's daemon so images are available to k8s
eval $(minikube docker-env)

# Build images
docker build -t backend:latest  backend/
docker build --build-arg COMMIT_SHA=$(git rev-parse HEAD) -t frontend:latest frontend/

# Apply manifests
kubectl apply -f k8s/

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s

echo ""
echo "Open the app:"
minikube service frontend --url
