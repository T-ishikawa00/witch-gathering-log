# R362 direct XCTest completion preparation

Prepared, not executed. This is a bounded follow-up to the preserved R362 runner failure. It reuses the already-built XCTest bundle and executable from `runner_root_r003/execution_r002`; it does not invoke SwiftPM, compile, or rebuild.

Before any future launch, the runner verifies all staged package rows against the original R362 input manifest, the exact test-bundle executable hash from the successful seed phase, and the Xcode `xctest` alias/canonical binary identity. It uses three fresh direct `xctest -XCTest` invocations against one new synthetic fixture. During the crash phase, the marker PID must equal the exact process returned by `Popen`, and its live start identity/command, parent, token, process group, operation, fingerprint, and primary bytes must match before a single-PID SIGKILL. It then requires `wait()` to return `-9` and confirms the same process identity is absent. No process-group signal is used.

The existing failed run and its cleanup evidence are untouched. This source has not been built or run; direct XCTest invocation remains unvalidated. Root review is required before execution.
