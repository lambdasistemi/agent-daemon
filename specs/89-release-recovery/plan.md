# Plan: rebase-safe release recovery

1. Extend the workflow contract with failing assertions for safe fallback
   release resolution and the staged-dylib self-ID exception.
2. Add a narrowly guarded release recovery step and route job outputs through
   the resolved result.
3. Teach the Darwin scanner to distinguish self install IDs from dependency
   install names.
4. Run focused RED/GREEN workflow lint, the full gate, final CI, and the live
   v0.2.0 Darwin publisher boundary.
