# Android build entry integration completeness

The review branch contained the Java helper and probe but omitted the local formal build consumer hook. The builder now selected for integration is byte-identical to the previously reviewed and tested archive `e8167ddb55372b1190e95a5ef2d9851b83a8629b`. No gameplay source, signing, package identity, global environment, network or JDK setting changes here.

The formal builder enters the process-local Java environment before export and restores it in `finally`; the helper restores immediately if its own preflight fails. The original native 32-round Selector/Pipe PASS, normal/failed restoration proof, AST parse claim, original failure logs and exact source fingerprints are retained under `evidence/JAVA_BUILD_ENTRY`. This is reused evidence, not a new probe/export. The current builder, helper, probe and documentation hashes exactly match that evidence. A new 109 build must still preflight its own actual environment.

B07A remains bound to `684824ac7bb59ac903054b26b3435441b8a2f152`, which lacked this consumer hook. A final-source followup must inspect the added hook rather than silently claiming it was covered by B07A. The Windows system-level per-directory cause is MISSING. 109 export and DEVICE TEST are NOT_RUN.
