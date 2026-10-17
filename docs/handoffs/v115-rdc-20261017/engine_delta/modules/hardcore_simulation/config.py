def can_build(env, platform):
    return not env["disable_physics_2d"]


def _validate_native_source_sha256(key, value, env):
    import re
    if value and re.fullmatch(r"[0-9a-f]{64}", str(value)) is None:
        raise ValueError("hardcore_native_source_sha256 must be empty or 64 lowercase hex digits")


def get_opts(platform):
    return [("hardcore_native_source_sha256", "Exact sealed HardCore Native source SHA256", "", _validate_native_source_sha256)]


def configure(env):
    pass
