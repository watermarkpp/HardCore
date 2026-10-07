"""Add the six user-supplied SW frames as an eight-direction review batch."""

from tools.half_moon_generator import hmg


def main():
    project = hmg.load_project()
    children = hmg.add_sw_reference_batch(project)
    hmg.save_project(project)
    print(f"HMG_SW_REFERENCE_PASS generation={project['active_generation']} candidates={len(children)}")


if __name__ == "__main__":
    main()
