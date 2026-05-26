import json
from pathlib import Path
from textwrap import fill
import random
import signal
import time


INTRO_WIDTH = 68
TASKS_PATH = Path(__file__).with_name("tasks.json")
with TASKS_PATH.open(encoding="utf-8") as file:
    COMMANDS = json.load(file)
TIME_LIMIT_SECONDS = len(COMMANDS)*10


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
                f"It does not cover every possible command. Instead, it focuses on {len(COMMANDS)} "
                "common commands that are useful for Kubernetes administration and "
                "exam practice."
            )
            + "\n\n"
            + wrap(
                f"For {TIME_LIMIT_SECONDS//60} minutes, you will be shown task descriptions. "
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