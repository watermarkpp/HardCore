# B01 ResourceLoader threaded ownership contract

**Status:** source/documentation review only. No Godot run, native test, or production/test edit.

**Engine target:** Godot 4.7.stable.official.5b4e0cb0f. The inspected official engine commit is `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` (the supplied short version is `5b4e0cb0f`). Sources:

- [resource_loader.cpp at the exact commit](https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/core/io/resource_loader.cpp)
- [resource_loader.h at the exact commit](https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/core/io/resource_loader.h)
- [official ResourceLoader API documentation](https://docs.godotengine.org/en/4.5/classes/class_resourceloader.html)

The API documentation is versioned 4.5, while the C++ source is the requested 5b4e0cb0f engine revision. Where behavior is derived from C++, the exact commit wins; the documentation is used for public API intent.

## Contract verified from the engine

### Request creates or attaches a user token

`ResourceLoader::load_threaded_request()` calls `_load_start(..., p_for_user=true)` and returns `OK` when a valid `LoadToken` exists, otherwise `FAILED` (`resource_loader.cpp:3336-3340`). A second request for the same user path does **not** return a distinct owner/token: `_load_threaded_request_reuse_user_token()` finds `user_load_tokens[p_path]`, increments `LoadToken::user_rc`, and logs “Another threaded load ... Not an error” (`3343-3354`). The new request therefore adds one user claim to the same load token.

If no user token exists but a same local path task is already registered, `_load_start()` attaches a new user claim to that task (`3419-3463`). With a cache-ignoring mode and an existing same-path task, it creates an unregistered `task_if_unregistered` copy instead of inserting another task into `thread_load_tasks` (`3535-3542`). This is the meaningful same-path distinction; it is not a generic `ERR_BUSY` ownership error.

The public docs define `THREAD_LOAD_INVALID_RESOURCE=0`, `IN_PROGRESS=1`, `FAILED=2`, and `LOADED=3`; `FAILED` means an error occurred during loading and `LOADED` is the state accepted by `load_threaded_get()` ([docs enum](https://docs.godotengine.org/en/4.5/classes/class_resourceloader.html#enum-resourceloader-threadloadstatus)).

### Polling is a lookup by the original user path

`load_threaded_get_status()` first checks `user_load_tokens.has(p_path)`. If no user claim remains, it returns `THREAD_LOAD_INVALID_RESOURCE` and logs a verbose diagnostic (`resource_loader.cpp:3653-3667`). When present, it resolves the local path and reads the task status, using `task_if_unregistered` when applicable (`3670-3688`). On the main thread, repeated in-progress polling in the same process frame calls `_ensure_load_progress()` once the frame repeats (`3695-3718`). Polling is therefore non-consuming: it does not release a user claim.

A caller must retain the exact request path/key used for the user token. A UID/local-path mismatch or a call after the claim was consumed is `INVALID_RESOURCE`; there is no public cancellation operation in the API shown in the exact header/source.

### `load_threaded_get()` is the consuming operation and may block

The public documentation explicitly says `load_threaded_get()` blocks if status is not `THREAD_LOAD_LOADED`, and recommends polling first ([official docs](https://docs.godotengine.org/en/4.5/classes/class_resourceloader.html#class-resourceloader-method-load-threaded-get)). The exact C++ path does the following:

1. If `user_load_tokens` has no original path, returns an empty `Ref<Resource>` and `ERR_INVALID_PARAMETER` (`resource_loader.cpp:3724-3749`).
2. If still in progress on the main thread, repeatedly drives `_ensure_load_progress()`, sleeps 1 ms, flushes the message queue, and continues until completion or engine exit (`3751-3806`). This is a potentially blocking call, not a poll.
3. Calls `_load_complete_inner(*load_token, r_error, ...)` (`3809`). The worker stores the loader error in `load_task.error` and sets status to `THREAD_LOAD_FAILED` when the error is non-OK, otherwise `THREAD_LOAD_LOADED` (`resource_loader.cpp:3076-3100`, `3259-3267`). Thus a failed `get` returns an invalid resource and the caller must inspect the `Error` out parameter at the C++ binding layer; failure status itself is not a successful resource.
4. Decrements `user_rc`. Only when that count reaches zero does it clear `user_path`, erase `user_load_tokens[p_path]`, release the token reference, and potentially delete the token (`3811-3825`). Every successful request claim must therefore have exactly one corresponding `load_threaded_get()`.

A failed load still consumes the caller’s user claim when `get` is called. It is incorrect to retain a failed token by skipping `get`; it is also incorrect to call `get` twice for one request, because the second call sees no user token and returns `ERR_INVALID_PARAMETER`/empty resource. The exact source logs the missing-token condition through `print_verbose`; application code must retain the status/error in its own receipt if it needs diagnostics after token release.

### Failure, engine teardown, and owner invalidation

The engine has no owner object or cancellation callback in this API. A `Node`/GDScript owner becoming invalid does not cancel the engine’s user token. If the caller abandons the request without calling `load_threaded_get()`, the user token remains in `user_load_tokens` and the task remains owned by the loader until the request is consumed or engine cleanup occurs. “Owner invalid” is therefore an application lifecycle fact, not a `ResourceLoader` status.

During `ResourceLoader` cleanup, `_run_load_task()` detects `cleaning_tasks`, marks the task `THREAD_LOAD_FAILED`, and returns (`resource_loader.cpp:2756-2763`, `3002-3018`). The normal completion path also refuses to wake waiters during cleanup and marks the task failed (`3243-3255`). `LoadToken::clear()` is deliberately defensive: it asserts that a user-facing token has no remaining user claims and that a registered task is already `FAILED` or `LOADED`; removing an in-progress task is described by the source as catastrophic (`2557-2595`). The destructor can wait for a task only after that completed-state invariant (`2620-2634`).

This means an owner’s `_exit_tree()` cannot safely “just free” an outstanding token through public ResourceLoader API. The owner must retain the request identity and either consume the result at a lifecycle boundary or explicitly classify the request as unresolved in its own state. The engine will fail work during global cleanup, but it does not provide a recoverable application-level cancellation receipt.

### Same-path requests and the reported ERR_BUSY question

The exact `load_threaded_request()` implementation does not return `ERR_BUSY` for a second request on the same user path. It reuses the user token and increments `user_rc` (`3343-3354`). A same local path task can also be attached by a new user token (`3448-3463`). The source does not expose an owner-specific “busy” status for this case. Any `ERR_BUSY` observed by B01 must therefore come from a surrounding application wrapper, another API, a loader-specific path, or a different engine revision; it is not the behavior of this exact public threaded-request path established here.

The one caveat is cache-ignore/deep-ignore: an existing same-path task causes a private `task_if_unregistered` to be created (`3535-3542`). This task has its own token lifetime, but still has no public cancel operation. Do not merge its receipt with the ordinary registered task solely by local path; keep the request’s original path, cache mode, and returned status/error.

## Implications for B01 implementation

1. Treat `(original request path, one request claim)` as the ownership key. Multiple calls to `load_threaded_request()` for the same path represent multiple claims on one token, not independent loads.
2. Poll status until `LOADED` or `FAILED`; retain the last status and progress in an application receipt before calling `get`.
3. Call `load_threaded_get()` exactly once per successful request claim, including when status is `FAILED`, and record both the returned resource validity and the `Error` result. Do not infer success from the fact that `get` returned or from progress reaching 1.0.
4. On owner invalidation, mark the application request stale and stop using the owner. Do not claim that the engine canceled the request. A lifecycle barrier should either consume the claim or retain an explicit unresolved token record until engine teardown.
5. On engine cleanup/exit, expect an in-flight task to become `FAILED`; preserve the pre-get receipt and error context because the token may be erased once the claim is consumed.
6. If a wrapper needs to avoid leaking failed requests, its error path must call `get` (or otherwise use the wrapper’s documented release API) and preserve the status/error before releasing the token. Logging alone is insufficient evidence of claim consumption.

## Uncertainty and evidence boundary

The exact public source confirms token reference counting, same-path request reuse, failed-task status, cleanup failure, and consuming `get` semantics. It does not document a public cancellation primitive, owner weak-reference semantics, or a promise that all loader-specific error text is emitted through one global callback. The source stores `load_task.error` and exposes it through `load_threaded_get(..., Error *r_error)`; loader-specific logging/notifications may occur below `ResourceLoader` and must not be treated as a stable contract without inspecting that loader.

**Status:** engine contract facts `PASS` for source/documentation review; owner-cancellation and crash-safe application receipt behavior `MISSING` at the public API boundary; no runtime/native validation performed (`NOT_RUN`).
