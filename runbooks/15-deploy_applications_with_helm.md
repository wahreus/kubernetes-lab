# Deploy applications with Helm

Add a Helm repository, inspect a chart, install a release, override values, upgrade it, inspect release state, roll it back, and uninstall it.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.
* Helm 3 is installed on the control-plane node.

Run all commands on the control-plane node unless otherwise specified.

## 1. Verify Helm and the cluster

Check Helm:

    helm version

Check Kubernetes:

    kubectl get nodes

## 2. Create a namespace

Create a namespace:

    kubectl create namespace helm-demo

## 3. Add a chart repository

Add the Bitnami repository:

    helm repo add bitnami https://charts.bitnami.com/bitnami

Update repository metadata:

    helm repo update

List configured repositories:

    helm repo list

Search for the NGINX chart:

    helm search repo bitnami/nginx

Inspect chart metadata:

    helm show chart bitnami/nginx

Inspect default values:

    helm show values bitnami/nginx | less

Exit `less` with `q`.

## 4. Render a chart without installing it

Render the chart locally:

    helm template web bitnami/nginx \
      --namespace helm-demo \
      > rendered.yaml

Inspect the generated Kubernetes resources:

    grep '^kind:' rendered.yaml

A dry render is useful for understanding what Helm will submit to Kubernetes.

## 5. Install a release

Install the chart:

    helm install web bitnami/nginx \
      --namespace helm-demo \
      --set service.type=ClusterIP

List releases:

    helm list -n helm-demo

Check the Kubernetes resources:

    kubectl get all -n helm-demo

Wait until the Deployment is available:

    kubectl rollout status deployment/web-nginx -n helm-demo

## 6. Inspect the release

Show release status:

    helm status web -n helm-demo

Show the values explicitly supplied for the release:

    helm get values web -n helm-demo

Show all computed values:

    helm get values web -n helm-demo --all

Show the rendered manifest stored in the release:

    helm get manifest web -n helm-demo | less

## 7. Upgrade with command-line values

Check the current replica count:

    kubectl get deployment web-nginx -n helm-demo

Upgrade the release to two replicas:

    helm upgrade web bitnami/nginx \
      --namespace helm-demo \
      --set replicaCount=2 \
      --set service.type=ClusterIP

Wait for the rollout:

    kubectl rollout status deployment/web-nginx -n helm-demo

Verify:

    kubectl get deployment,pods -n helm-demo

## 8. Upgrade with a values file

Create `values.yaml`:

    replicaCount: 3

    service:
      type: ClusterIP

    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi

Apply the values file:

    helm upgrade web bitnami/nginx \
      --namespace helm-demo \
      -f values.yaml

Verify the replica count:

    kubectl get deployment web-nginx -n helm-demo

Inspect the configured resources:

    kubectl get deployment web-nginx \
      -n helm-demo \
      -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'

## 9. Inspect release history

Show revision history:

    helm history web -n helm-demo

Each successful install or upgrade creates a Helm release revision.

## 10. Roll back the release

Identify an earlier revision:

    helm history web -n helm-demo

Roll back to revision 1:

    helm rollback web 1 -n helm-demo

Verify the release:

    helm status web -n helm-demo

Check the workload:

    kubectl get deployment,pods -n helm-demo

## 11. Practice a dry-run upgrade

Render an upgrade without applying it:

    helm upgrade web bitnami/nginx \
      --namespace helm-demo \
      --set replicaCount=2 \
      --dry-run=client

For additional rendered output useful during troubleshooting:

    helm upgrade web bitnami/nginx \
      --namespace helm-demo \
      --set replicaCount=2 \
      --dry-run=client \
      --debug

## 12. Download and inspect a chart

Download the chart locally:

    helm pull bitnami/nginx --untar

Inspect the chart structure:

    find nginx -maxdepth 2 -type f | sort | head -30

Important files include:

    Chart.yaml
    values.yaml
    templates/

Render the local chart:

    helm template local-web ./nginx \
      --namespace helm-demo \
      --set replicaCount=1 \
      > local-rendered.yaml

## 13. Uninstall the release

Uninstall it:

    helm uninstall web -n helm-demo

Verify that the release is gone:

    helm list -n helm-demo

Check remaining resources:

    kubectl get all -n helm-demo

## Troubleshooting

If a release fails:

    helm status web -n helm-demo
    helm history web -n helm-demo

Inspect Kubernetes resources:

    kubectl get all -n helm-demo
    kubectl get events \
      -n helm-demo \
      --sort-by=.metadata.creationTimestamp

Render the chart before applying changes:

    helm template web bitnami/nginx \
      --namespace helm-demo \
      -f values.yaml

If an upgrade produced a bad revision:

    helm history web -n helm-demo
    helm rollback web <revision> -n helm-demo

Useful commands to remember:

    helm search repo
    helm show values
    helm install
    helm list
    helm status
    helm get values
    helm upgrade
    helm history
    helm rollback
    helm uninstall
    helm template