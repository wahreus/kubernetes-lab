# Implement blue-green and canary deployments

Deploy two application versions, switch traffic with Service selectors, and implement a simple canary release with two Deployments behind one Service.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that the nodes are ready:

    kubectl get nodes

## 2. Create a namespace

Create a namespace:

    kubectl create namespace deployment-strategies

## 3. Create the blue version

Create `blue.yaml`:

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: app-blue
      namespace: deployment-strategies
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: demo
          version: blue
      template:
        metadata:
          labels:
            app: demo
            version: blue
        spec:
          containers:
            - name: app
              image: hashicorp/http-echo:1.0
              args:
                - -text=blue
                - -listen=:8080
              ports:
                - containerPort: 8080

Apply it:

    kubectl apply -f blue.yaml

Wait for the Deployment:

    kubectl rollout status deployment/app-blue -n deployment-strategies

## 4. Create a Service for blue

Create `service.yaml`:

    apiVersion: v1
    kind: Service
    metadata:
      name: app
      namespace: deployment-strategies
    spec:
      selector:
        app: demo
        version: blue
      ports:
        - port: 80
          targetPort: 8080

Apply it:

    kubectl apply -f service.yaml

Verify the selected endpoints:

    kubectl get pods \
      -n deployment-strategies \
      -l app=demo,version=blue \
      --show-labels

    kubectl get endpointslices \
      -n deployment-strategies \
      -l kubernetes.io/service-name=app

## 5. Test the blue version

Run repeated requests:

    kubectl run curl \
      --image=curlimages/curl:8.12.1 \
      --restart=Never \
      --rm -it \
      -n deployment-strategies \
      -- sh -c 'for i in $(seq 1 5); do curl -s http://app; done'

Every response should be:

    blue

## 6. Deploy the green version

Create `green.yaml`:

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: app-green
      namespace: deployment-strategies
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: demo
          version: green
      template:
        metadata:
          labels:
            app: demo
            version: green
        spec:
          containers:
            - name: app
              image: hashicorp/http-echo:1.0
              args:
                - -text=green
                - -listen=:8080
              ports:
                - containerPort: 8080

Apply it:

    kubectl apply -f green.yaml

Wait for it:

    kubectl rollout status deployment/app-green -n deployment-strategies

The blue and green versions now run at the same time, but the Service still sends traffic only to blue.

## 7. Switch traffic from blue to green

Patch the Service selector:

    kubectl patch service app \
      -n deployment-strategies \
      -p '{"spec":{"selector":{"app":"demo","version":"green"}}}'

Verify the selector:

    kubectl get service app \
      -n deployment-strategies \
      -o jsonpath='{.spec.selector}{"\n"}'

Test it:

    kubectl run curl \
      --image=curlimages/curl:8.12.1 \
      --restart=Never \
      --rm -it \
      -n deployment-strategies \
      -- sh -c 'for i in $(seq 1 5); do curl -s http://app; done'

Every response should now be:

    green

This is a blue-green cutover. The inactive version remains available for a quick rollback.

## 8. Roll back the blue-green cutover

Switch the Service back to blue:

    kubectl patch service app \
      -n deployment-strategies \
      -p '{"spec":{"selector":{"app":"demo","version":"blue"}}}'

Verify the responses:

    kubectl run curl \
      --image=curlimages/curl:8.12.1 \
      --restart=Never \
      --rm -it \
      -n deployment-strategies \
      -- curl -s http://app

The response should be:

    blue

## 9. Prepare a simple canary deployment

A basic canary can be created by letting a Service select Pods from two versions and controlling the approximate traffic ratio through replica counts.

Remove the version selector from the Service:

    kubectl patch service app \
      -n deployment-strategies \
      --type=json \
      -p='[{"op":"remove","path":"/spec/selector/version"}]'

Scale blue to 4 replicas:

    kubectl scale deployment/app-blue \
      --replicas=4 \
      -n deployment-strategies

Scale green to 1 replica:

    kubectl scale deployment/app-green \
      --replicas=1 \
      -n deployment-strategies

Wait for both Deployments:

    kubectl rollout status deployment/app-blue -n deployment-strategies
    kubectl rollout status deployment/app-green -n deployment-strategies

Verify that the Service selects both versions:

    kubectl get pods \
      -n deployment-strategies \
      -l app=demo \
      --show-labels

    kubectl get endpointslices \
      -n deployment-strategies \
      -l kubernetes.io/service-name=app \
      -o wide

## 10. Test the canary

Run many requests:

    kubectl run curl \
      --image=curlimages/curl:8.12.1 \
      --restart=Never \
      --rm -it \
      -n deployment-strategies \
      -- sh -c 'for i in $(seq 1 30); do curl -s http://app; done'

You should see both:

    blue
    green

The ratio is approximate. Kubernetes Services do not provide a guaranteed percentage-based traffic split. The replica ratio only creates a simple exam-practice canary.

## 11. Promote the canary

Scale green up:

    kubectl scale deployment/app-green \
      --replicas=4 \
      -n deployment-strategies

Scale blue down:

    kubectl scale deployment/app-blue \
      --replicas=0 \
      -n deployment-strategies

Verify:

    kubectl get deployments,pods -n deployment-strategies

All application traffic should now reach green.

## Troubleshooting

Inspect Service selectors:

    kubectl get service app \
      -n deployment-strategies \
      -o jsonpath='{.spec.selector}{"\n"}'

Inspect Pod labels:

    kubectl get pods \
      -n deployment-strategies \
      --show-labels

Inspect Service endpoints:

    kubectl get endpointslices \
      -n deployment-strategies \
      -l kubernetes.io/service-name=app

If the Service has no endpoints, its selector does not match any Ready Pods.

Inspect rollout status:

    kubectl rollout status deployment/app-blue -n deployment-strategies
    kubectl rollout status deployment/app-green -n deployment-strategies