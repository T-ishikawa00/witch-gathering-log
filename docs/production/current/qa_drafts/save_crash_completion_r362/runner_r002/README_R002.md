# R362 runner R002 preparation

R002 is an additive, not-yet-executed runner revision. R001 and its preparation records remain unchanged.

The crash-child receipt now consistently records and validates `returnCode`. Process cleanup is scoped to captured PID + process start identity + exact command, rooted in the runner's child tree or the unique XCTest bundle. It uses individual PID signals only (TERM, then bounded KILL), and the receipt requires absence of every observed owned PID and any process still bound to the unique bundle. A competing Swift/XCTest guard runs before work begins.

No Swift build/test, Simulator action, save access, or execution attempt occurred while preparing R002. This source has not been executed; the manifest records the exact runner and input-manifest hashes.
