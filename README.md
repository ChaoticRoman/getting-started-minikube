# Getting Started with Minikube

A simple Kubernetes application running on Minikube: Nginx serving a static page that proxies API requests to a FastAPI backend.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)

## Project Structure

```
backend/     — FastAPI app (GET /api/hello returns {"message": "Hello, World!"})
frontend/    — Nginx serving static HTML and proxying /api/* to the backend
k8s/         — Kubernetes manifests (Deployments + Services)
deploy.sh    — Build & deploy script
```

## Start

1. Start minikube:

   ```bash
   minikube start
   ```

2. Deploy the application:

   ```bash
   ./deploy.sh
   ```

   This builds Docker images inside minikube, applies the Kubernetes manifests, and waits for pods to be ready.

## Open in Browser

```bash
minikube service frontend --url
```

Open the printed URL in your browser. Click the button to call the FastAPI backend.

## Dashboard

Minikube includes a built-in Kubernetes dashboard:

```bash
minikube dashboard
```

This opens the dashboard in your default browser, where you can view deployments, pods, services, and logs.

## Useful Commands

```bash
# Check pod status
kubectl get pods

# View backend logs
kubectl logs -l app=backend

# View frontend logs
kubectl logs -l app=frontend
```

## Cleanup

```bash
# Remove the application
kubectl delete -f k8s/

# Stop minikube
minikube stop

# Or delete the cluster entirely
minikube delete
```
