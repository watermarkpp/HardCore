"""Add the revised A/B/C set while preserving earlier user work."""

from tools.half_moon_generator import hmg


def main():
    project = hmg.load_project()
    if any(g.get("kind") == "curated_a_b_c" for g in project["generations"]):
        raise ValueError("Curated first batch already exists")
    children = hmg.add_curated_batch(project)
    hmg.save_project(project)
    print(f"HMG_CURATED_BATCH_PASS generation={project['active_generation']} candidates={len(children)}")


if __name__ == "__main__":
    main()
