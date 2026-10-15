# R371 execution preparation R002

Prepared only; not executed. Uses additive candidate R003 and exact 15-test filter. R001 run and inputs remain untouched. The wrapper exit path now raises `SystemExit(main())` outside the broad exception handler so a successful main return is not misclassified as HOLD. Fixed limits remain one invocation, 120 seconds, 350 MB allocated output, 12 GB free-space floor, and 2 concurrent jobs. Root review is required before execution.
