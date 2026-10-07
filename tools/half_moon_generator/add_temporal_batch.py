"""Add the corrected 120-degree six-frame batch to a saved local project."""

from tools.half_moon_generator import hmg


def main():
    project = hmg.load_project()
    children = hmg.add_temporal_batch(project)
    hmg.save_project(project)
    print(f"HMG_TEMPORAL_BATCH_PASS generation={project['active_generation']} candidates={len(children)}")


if __name__ == "__main__":
    main()
