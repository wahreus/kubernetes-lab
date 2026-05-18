from textwrap import fill
import random
import signal
import time


INTRO_WIDTH = 68
TIME_LIMIT_SECONDS = 180


COMMANDS = [
    {
        "prompt": "List all pods in the production namespace with extra node/IP details.",
        "answer": "kubectl get pods -n production -o wide",
    },
    {
        "prompt": "Show detailed troubleshooting information for pod api-7d9f8c9b6f-2kq4m in namespace backend.",
        "answer": "kubectl describe pod api-7d9f8c9b6f-2kq4m -n backend",
    },
    {
        "prompt": "Create or update resources from the manifest file manifests/nginx-deployment.yaml.",
        "answer": "kubectl apply -f manifests/nginx-deployment.yaml",
    },
    {
        "prompt": "Create a deployment named web using the nginx:1.27 image.",
        "answer": "kubectl create deployment web --image=nginx:1.27",
    },
    {
        "prompt": "Open deployment frontend in namespace production for direct editing.",
        "answer": "kubectl edit deployment frontend -n production",
    },
    {
        "prompt": "Show logs from pod web-6c8f7d9f5b-mq2xz in namespace frontend.",
        "answer": "kubectl logs web-6c8f7d9f5b-mq2xz -n frontend",
    },
    {
        "prompt": "Start an interactive shell inside pod debug-shell in namespace tools.",
        "answer": "kubectl exec -it debug-shell -n tools -- sh",
    },
    {
        "prompt": "Switch your current kubeconfig context to dev-cluster.",
        "answer": "kubectl config use-context dev-cluster",
    },
    {
        "prompt": "Show documentation for container resource requests and limits.",
        "answer": "kubectl explain pod.spec.containers.resources",
    },
    {
        "prompt": "Delete pod crashloop-demo in namespace troubleshooting.",
        "answer": "kubectl delete pod crashloop-demo -n troubleshooting",
    },
    {
        "prompt": "Prepare node worker-2 for maintenance by safely evicting workloads.",
        "answer": "kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data",
    },
    {
        "prompt": "Mark node worker-3 so no new pods are scheduled there.",
        "answer": "kubectl cordon worker-3",
    },
    {
        "prompt": "Mark node worker-3 as schedulable again.",
        "answer": "kubectl uncordon worker-3",
    },
    {
        "prompt": "Prevent regular pods from scheduling on worker-1 unless they tolerate the dedicated=infra restriction.",
        "answer": "kubectl taint nodes worker-1 dedicated=infra:NoSchedule",
    },
    {
        "prompt": "Check whether you are allowed to create deployments in the production namespace.",
        "answer": "kubectl auth can-i create deployments -n production",
    },
    {
        "prompt": "Initialize a control-plane node using 10.244.0.0/16 as the pod network range.",
        "answer": "sudo kubeadm init --pod-network-cidr=10.244.0.0/16",
    },
    {
        "prompt": "Reset kubeadm state on a node.",
        "answer": "sudo kubeadm reset",
    },
    {
        "prompt": "Generate a fresh full worker-node join command.",
        "answer": "kubeadm token create --print-join-command",
    },
    {
        "prompt": "Show the available upgrade versions for a kubeadm-managed cluster.",
        "answer": "sudo kubeadm upgrade plan",
    },
    {
        "prompt": "Upgrade the control plane to version v1.34.1.",
        "answer": "sudo kubeadm upgrade apply v1.34.1",
    },
]


class TimeExpired(Exception):
    pass


def handle_timeout(signum, frame):
    raise TimeExpired


def normalize(command: str) -> str:
    return " ".join(command.strip().split())


def print_results(correct: int, attempted: int) -> None:
    precision = correct / attempted * 100 if attempted > 0 else 0

    print("\nTime is up!")
    print()
    print(f"Correct:   {correct}")
    print(f"Attempted: {attempted}")
    print(f"Precision: {precision:.1f}%")


def get_next_prompt(deck: list[dict[str, str]]) -> dict[str, str]:
    if not deck:
        deck.extend(COMMANDS)
        random.shuffle(deck)

    return deck.pop()


def wrap(text: str) -> str:
    return fill(" ".join(text.split()), width=INTRO_WIDTH)



def main() -> None:
    correct = 0
    attempted = 0

    deck = COMMANDS.copy()
    random.shuffle(deck)

    input(
            "\n\n"
            "Welcome to KubeRun!\n\n"
            + wrap(
                "This is a short command-speed game for Kubernetes and CKA practice. "
                "It does not cover every possible command. Instead, it focuses on 20 "
                "common commands that are useful for Kubernetes administration and "
                "exam practice."
            )
            + "\n\n"
            + wrap(
                f"For {TIME_LIMIT_SECONDS // 60} minutes, you will be shown task descriptions. "
                "Your job is to type the correct command that matches each task. "
                "The goal of the game is to type as many correct commands as possible. "
                "The commands are not executed, this is only typing practice."
            )
            + "\n\n"
            + "Press ENTER when you are ready to begin."
        )

    print("\n\n")
    for i in range(3, 0, -1):
        print(f"{i}...")
        time.sleep(1)
    print("\n\n")

    signal.signal(signal.SIGALRM, handle_timeout)
    signal.alarm(TIME_LIMIT_SECONDS)

    start_time = time.monotonic()

    try:
        while True:
            remaining = max(0, TIME_LIMIT_SECONDS - int(time.monotonic() - start_time))
            item = get_next_prompt(deck)

            print(f"Time left: {remaining}s")
            print(f"Prompt: {item['prompt']}")

            user_answer = input("> ")
            attempted += 1

            if normalize(user_answer) == normalize(item["answer"]):
                correct += 1
                print("Correct!\n\n")
            else:
                print(f"Incorrect. Answer: {item['answer']}\n\n")

    except TimeExpired:
        print_results(correct, attempted)

    except KeyboardInterrupt:
        print("\nStopped early.")
        print_results(correct, attempted)

    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main()