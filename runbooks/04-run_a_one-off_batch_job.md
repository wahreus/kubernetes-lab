# Run a one-off batch Job

Create a Kubernetes Job, wait for it to complete, inspect its Pod and logs, and run the task again.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

```
kubectl get nodes
```

Confirm that the system Pods are running:

```
kubectl get pods -A
```

## 2. Create a namespace

Create a namespace for the batch workload:

```
kubectl create namespace batch
```

Verify the namespace:

```
kubectl get namespace batch
```

## 3. Create the Job manifest

Create a file named `job.yaml`:

```
apiVersion: batch/v1
kind: Job
metadata:
  name: sum
  namespace: batch
spec:
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: sum
    spec:
      restartPolicy: Never
      containers:
        - name: sum
          image: busybox:1.37
          command:
            - sh
            - -c
          args:
            - |
              total=0
              for number in $(seq 1 100); do
                total=$((total + number))
              done
              echo "sum(1..100)=$total"
```

The Job creates a Pod that calculates the sum of the integers from 1 through 100 and prints the result. The Pod exits after the calculation finishes.

Apply the manifest:

```
kubectl apply -f job.yaml
```

## 4. Monitor the Job

Check the Job:

```
kubectl get job sum -n batch
```

Watch the Job and its Pod:

```
watch kubectl get jobs,pods -n batch
```

Press `Ctrl+C` after the Job reports one successful completion.

Alternatively, wait for the completion condition:

```
kubectl wait \
  --for=condition=complete \
  job/sum \
  -n batch \
  --timeout=120s
```

Verify the completed Job and Pod:

```
kubectl get jobs,pods -n batch -o wide
```

The Job should report `1/1` completions, and its Pod should report `Completed`.

## 5. Inspect the Job output

Read the Job's logs:

```
kubectl logs job/sum -n batch
```

The output should be:

```
sum(1..100)=5050
```

Inspect the Pod:

```
kubectl describe pod \
  -n batch \
  -l batch.kubernetes.io/job-name=sum
```

Confirm that:

* The Pod's status is `Succeeded`.
* The container terminated with exit code `0`.
* The manifest uses `restartPolicy: Never`.

## 6. Verify Job ownership

Inspect the Pod's controlling resource:

```
kubectl describe pod \
  -n batch \
  -l batch.kubernetes.io/job-name=sum
```

Find the `Controlled By` entry. It should identify the Job:

```
Job/sum
```

The Job controller creates and tracks the Pod until the required completion succeeds.

## 7. Run the Job again

A completed Job does not start another Pod automatically. Delete and recreate the Job to run the task again:

```
kubectl delete job sum -n batch
kubectl apply -f job.yaml
```

Wait for the new execution to complete:

```
kubectl wait \
  --for=condition=complete \
  job/sum \
  -n batch \
  --timeout=120s
```

Read the new execution's output:

```
kubectl logs job/sum -n batch
```

## Troubleshooting

Inspect the Job:

```
kubectl describe job sum -n batch
```

Inspect the Job's Pod:

```
kubectl get pods \
  -n batch \
  -l batch.kubernetes.io/job-name=sum

kubectl describe pod -n batch <pod-name>
```

Read the Pod logs directly:

```
kubectl logs -n batch <pod-name>
```

Inspect recent events:

```
kubectl get events \
  -n batch \
  --sort-by=.metadata.creationTimestamp
```

If the Job reaches its backoff limit, inspect the failed Pod's termination reason and logs before recreating the Job.