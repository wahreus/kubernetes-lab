# Build and modify container images

Build a small OCI-compatible container image, inspect it, update it, import it into the Kubernetes nodes, and run it in Kubernetes without using an external container registry.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.
* Docker is available on the machine where the image is built.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the image builder

Check that the image builder is available:

```bash
docker version
```

Add the current user to the `docker` group so Docker can be used without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Verify that you can run a container:

```bash
docker run --rm busybox:1.37 echo "container runtime works"
```

Expected output:

```text
container runtime works
```

## 2. Create a simple application

Create a working directory:

    mkdir -p ckad-image-demo
    cd ckad-image-demo

Create a file named `index.html`:

    cat > index.html <<'EOF'
    <!doctype html>
    <html>
      <body>
        <h1>CKAD image demo v1</h1>
      </body>
    </html>
    EOF

Create a file named `Dockerfile`:

    cat > Dockerfile <<'EOF'
    FROM nginx:1.28-alpine

    COPY index.html /usr/share/nginx/html/index.html

    EXPOSE 80
    EOF

The Dockerfile starts from a small NGINX base image and copies the application file into the image. `EXPOSE 80` documents that the container is expected to serve traffic on port 80.

## 3. Build the image

Build the image:

    docker build -t ckad-image-demo:v1 .

Docker reads the `Dockerfile` in the current directory, creates the image layers, and stores the finished image in Docker's local image store under the tag `ckad-image-demo:v1`.

List local images:

    docker images ckad-image-demo

Inspect the image metadata:

    docker image inspect ckad-image-demo:v1

## 4. Run and test the image locally

Start a container:

    docker run --rm -d \
      --name ckad-image-demo \
      -p 8080:80 \
      ckad-image-demo:v1

This starts the image as a background container. Port `8080` on the host is mapped to port `80` inside the container, allowing the NGINX page to be tested with `curl`.

Test the application:

    curl http://localhost:8080

The response should contain:

    CKAD image demo v1

Stop the container:

    docker stop ckad-image-demo

## 5. Modify the image

Update `index.html`:

    cat > index.html <<'EOF'
    <!doctype html>
    <html>
      <body>
        <h1>CKAD image demo v2</h1>
      </body>
    </html>
    EOF

Build a second image:

    docker build -t ckad-image-demo:v2 .

The new tag creates a second version of the image while keeping `v1` available. This lets Kubernetes switch between versions later in the exercise.

Compare the images:

    docker images ckad-image-demo

## 6. Make the images available to Kubernetes

Kubernetes uses containerd rather than Docker as its container runtime. Docker and containerd keep separate local image stores, so an image built successfully with Docker is not automatically visible to Kubernetes. The image therefore needs to be imported into containerd on every worker that may run the Pod.

Export both image versions to a tar archive. `docker save` packages the image layers and metadata so they can be transferred into another container runtime without using a registry:

    docker save \
      -o ckad-image-demo.tar \
      ckad-image-demo:v1 \
      ckad-image-demo:v2

Create the namespace used by the exercise:

    kubectl create namespace image-demo

Create a temporary DaemonSet. A DaemonSet is useful here because it places one loader Pod on each worker node. Each loader Pod mounts the host's containerd socket and `ctr` binary, giving it temporary access to that worker's image store. This lets the image be imported through Kubernetes itself, without SSH or an external registry:

    cat > image-loader.yaml <<'EOF'
    apiVersion: apps/v1
    kind: DaemonSet
    metadata:
      name: image-loader
      namespace: image-demo
    spec:
      selector:
        matchLabels:
          app: image-loader
      template:
        metadata:
          labels:
            app: image-loader
        spec:
          containers:
          - name: loader
            image: busybox:1.37
            command: ["sh", "-c", "sleep 3600"]
            securityContext:
              privileged: true
            volumeMounts:
            - name: containerd-socket
              mountPath: /run/containerd/containerd.sock
            - name: ctr
              mountPath: /usr/local/bin/ctr
              readOnly: true
          volumes:
          - name: containerd-socket
            hostPath:
              path: /run/containerd/containerd.sock
              type: Socket
          - name: ctr
            hostPath:
              path: /usr/bin/ctr
              type: File
    EOF

Apply it:

    kubectl apply -f image-loader.yaml

Wait for the loader Pods to become ready:

    kubectl wait \
      --for=condition=Ready pod \
      -l app=image-loader \
      -n image-demo \
      --timeout=120s

Check that one loader Pod is running on each worker:

    kubectl get pods -n image-demo -l app=image-loader -o wide

Copy the image archive through the Kubernetes API and import it into containerd on every worker. The loop finds each loader Pod, copies the tar archive into it, and then runs `ctr images import` against that node's containerd socket. The `k8s.io` namespace is used because that is where Kubernetes expects its container images:

    for pod in $(kubectl get pods -n image-demo -l app=image-loader -o name); do
      name=${pod#pod/}
      kubectl cp \
        ckad-image-demo.tar \
        "image-demo/$name:/tmp/ckad-image-demo.tar"
      kubectl exec -n image-demo "$name" -- \
        /usr/local/bin/ctr \
        -a /run/containerd/containerd.sock \
        -n k8s.io \
        images import /tmp/ckad-image-demo.tar
    done

Verify the imported images on every worker:

    for pod in $(kubectl get pods -n image-demo -l app=image-loader -o name); do
      name=${pod#pod/}
      echo "=== $name ==="
      kubectl exec -n image-demo "$name" -- \
        /usr/local/bin/ctr \
        -a /run/containerd/containerd.sock \
        -n k8s.io \
        images list | grep ckad-image-demo
    done

The images are now available to Kubernetes on each worker without signing up for a registry and without SSH access between nodes.

## 7. Deploy the image to Kubernetes

Create a Deployment using version 2. At this point the Deployment only records which image Kubernetes should run; the image itself is already present locally on each worker:

    kubectl create deployment image-demo \
      --image=ckad-image-demo:v2 \
      -n image-demo

Set the pull policy to `Never` so Kubernetes uses the image already imported into containerd instead of trying to contact an external registry. The patch includes both the image name and the pull policy because the container entry is being updated as one unit:

    kubectl patch deployment image-demo \
      -n image-demo \
      --type=strategic \
      -p '{"spec":{"template":{"spec":{"containers":[{"name":"image-demo","image":"ckad-image-demo:v2","imagePullPolicy":"Never"}]}}}}'

Expose the Deployment. This creates a ClusterIP Service that sends traffic on port 80 to the Pods managed by the Deployment:

    kubectl expose deployment image-demo \
      --port=80 \
      --target-port=80 \
      -n image-demo

Wait for the rollout:

    kubectl rollout status deployment/image-demo -n image-demo

Inspect the image used by the Deployment:

    kubectl get deployment image-demo \
      -n image-demo \
      -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

## 8. Change the image used by the Deployment

Update the Deployment to version 1. Changing the image in the Pod template causes Kubernetes to create a new ReplicaSet and roll out replacement Pods using `v1`:

    kubectl set image deployment/image-demo \
      image-demo=ckad-image-demo:v1 \
      -n image-demo

Watch the rollout:

    kubectl rollout status deployment/image-demo -n image-demo

Inspect the rollout history:

    kubectl rollout history deployment/image-demo -n image-demo

Change back to version 2:

    kubectl set image deployment/image-demo \
      image-demo=ckad-image-demo:v2 \
      -n image-demo

## 9. Inspect image pull behavior

Check the Pod image and pull policy. This confirms both which image Kubernetes intends to run and whether it is allowed to pull from a registry:

    kubectl get deployment image-demo \
      -n image-demo \
      -o yaml | grep -A3 'image:'

Describe a Pod:

    kubectl describe pod \
      -n image-demo \
      "$(kubectl get pods -n image-demo -l app=image-demo -o jsonpath='{.items[0].metadata.name}')"

Look for:

* The exact image reference.
* The image ID.
* The `Never` pull policy.
* `ErrImageNeverPull`, `ErrImagePull`, or `ImagePullBackOff` errors.

## 10. Practice a multi-stage build

Replace the Dockerfile with:

    cat > Dockerfile <<'EOF'
    FROM busybox:1.37 AS builder
    RUN echo '<h1>Built in a separate stage</h1>' > /index.html

    FROM nginx:1.28-alpine
    COPY --from=builder /index.html /usr/share/nginx/html/index.html
    EXPOSE 80
    EOF

Build the image:

    docker build -t ckad-image-demo:multistage .

A multi-stage build allows files to be produced in one stage and copied into a later stage. The final image contains only what is copied forward, which can reduce image size and avoid shipping build tools that are not needed at runtime.

## Troubleshooting

If the image build fails:

    docker build --no-cache -t ckad-image-demo:v1 .

Check that the Dockerfile and copied files exist:

    ls -la

If the loader Pods do not start:

    kubectl get pods -n image-demo -l app=image-loader -o wide
    kubectl describe pod -n image-demo -l app=image-loader

Check that containerd and `ctr` exist on the worker nodes. The loader expects:

    /run/containerd/containerd.sock
    /usr/bin/ctr

If the import loop fails, inspect one loader Pod:

    kubectl exec -n image-demo <loader-pod> -- ls -l \
      /run/containerd/containerd.sock \
      /usr/local/bin/ctr \
      /tmp/ckad-image-demo.tar

If Kubernetes reports `ErrImageNeverPull`, `ErrImagePull`, or `ImagePullBackOff`:

    kubectl get pods -n image-demo -o wide
    kubectl describe pod -n image-demo <pod-name>

Find the loader Pod running on the same worker and verify that the image exists in containerd:

    kubectl get pods -n image-demo -l app=image-loader -o wide

Then run:

    kubectl exec -n image-demo <loader-pod> -- \
      /usr/local/bin/ctr \
      -a /run/containerd/containerd.sock \
      -n k8s.io \
      images list | grep ckad-image-demo

Also verify:

* The image name and tag are correct.
* Both image versions were imported on every worker.
* The Deployment uses `imagePullPolicy: Never`.

If a Deployment uses the wrong image:

    kubectl get deployment image-demo \
      -n image-demo \
      -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'

Update it with:

    kubectl set image deployment/image-demo \
      image-demo=<image>:<tag> \
      -n image-demo