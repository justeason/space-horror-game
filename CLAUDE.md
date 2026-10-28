# Autonomous Development Workflow

The user authorizes autonomous execution of the full task described in
each prompt, including all necessary investigation, planning, implementation,
testing, debugging, and final review.

## 1. End-to-End Task Execution

For every development task:

1. Read the relevant project instructions, including this file, and inspect
   the current implementation and Git state.
2. Investigate the problem and identify its root cause before making changes.
3. Formulate an implementation plan based on the user's requirements,
   existing architecture, and project constraints.
4. Execute every implementation stage required by the user's prompt without
   stopping to request intermediate approval.
5. Run relevant automated tests, static analysis, and other appropriate
   validation.
6. Investigate test failures and distinguish pre-existing failures from
   regressions introduced by the current changes.
7. Fix regressions caused by the current changes and rerun affected tests.
8. Review the final diff for unintended modifications, architectural problems,
   incomplete requirements, and potential regressions.
9. Continue working until the requested task is complete or a genuine blocker
   prevents further progress.
10. Produce a concise but complete final report.

A prompt describing a multi-stage task authorizes execution of all its stages.
Do not stop after investigation or planning when implementation was requested.
Do not stop after the first stage merely to ask permission to continue.

Do not ask questions such as:
- "Should I proceed?"
- "Would you like me to implement this?"
- "Should I continue to the next stage?"
- "Do you want me to run the tests?"
- "Would you like me to fix the failures?"

Do not ask equivalent questions when the user's prompt has already authorized
the work.

Choose sensible implementation details independently when they can be
resolved from the requirements, project architecture, existing code, or
established constraints.

Ask the user a question only when:
- A genuine blocker requires information that cannot reasonably be inferred.
- A decision between materially different approaches has important consequences
  that cannot be resolved safely from the available requirements.
- An action requires explicit authorization that the user has not granted.

When a genuine blocker exists, explain the specific issue and ask only the
minimum necessary question. Do not use minor uncertainty or routine technical
decisions as reasons to interrupt the workflow.

## 2. Permissions and Approval Prompts

The user's authorization to implement a task includes the ordinary development
work necessary to complete it, such as:
- Inspecting project files and Git status.
- Reading and editing relevant source files.
- Creating or updating task-related tests.
- Running appropriate tests, linters, type checks, and build commands.
- Investigating failures and correcting regressions caused by the changes.
- Reviewing diffs and validating the implementation.

Do not request conversational approval between these stages.

However, this instruction does not override Claude Code's actual permission
system or authorize actions that require separate approval. If a tool or
command is blocked by a permission restriction, follow the configured
permission workflow rather than attempting to bypass it.

Do not weaken security controls, change permission settings, or perform
sensitive operations merely to avoid an approval prompt.

When an action is blocked, determine whether a safe alternative can complete
the task. Ask the user for assistance only when the restriction is a genuine
blocker.

## 3. Implementation and Regression Policy

Investigate root causes rather than applying arbitrary surface-level fixes.

Prefer solutions that:
- Satisfy the user's explicit requirements and acceptance criteria.
- Preserve the existing architecture and established project conventions.
- Minimize unrelated changes.
- Address the underlying cause rather than masking symptoms.
- Include appropriate regression tests.
- Preserve existing functionality unless the task explicitly requires changing it.

Before editing files, understand relevant dependencies and existing behavior.
Do not make broad rewrites when a focused correction is sufficient.

If a test fails:
1. Inspect the failure and determine its cause.
2. Establish whether it is pre-existing or introduced by the current changes.
3. Fix failures and regressions caused by the current work.
4. Rerun the affected tests.
5. Report any remaining pre-existing failures without misrepresenting them.

Do not spend time fixing documented pre-existing failures unrelated to the task.
Do not claim that a task is fully validated when relevant failures remain
unexplained.

If the requested task cannot be completed fully, finish all safe and useful
work possible and clearly explain what remains blocked.

## 4. Preserve User Work

Preserve all existing uncommitted user changes.

Before making changes:
- Inspect Git status.
- Identify existing modifications and untracked files when relevant.
- Avoid overwriting work that is unrelated to the current task.

Never reset, clean, discard, or overwrite unrelated user work.
Never use destructive commands to make the working tree appear clean.

Do not revert existing changes merely because they are unfamiliar or unrelated
to the current implementation.

## 5. Git Policy

Never commit or push unless the user explicitly authorizes it.

Specifically:
- Do not create commits as part of routine task completion.
- Do not push branches or publish changes.
- Do not amend commits or rewrite Git history.
- Do not force-push.
- Do not interpret authorization to implement, test, or review as authorization
  to commit or push.

Leave completed changes in the working tree and report their status.

## 6. Safety and Scope Boundaries

- Do not delete unrelated files.
- Do not perform irreversible operations without the necessary authorization.
- Do not expose secrets, credentials, tokens, or other sensitive information.
- Do not bypass permission controls.
- Do not introduce unrelated features or refactors.
- Do not silently change established requirements or project constraints.
- Document important assumptions and technical trade-offs in the final report.

If the task has explicit acceptance criteria, verify each criterion before
declaring completion.

## 7. Testing and Verification Standards

Use the strongest practical validation available for the task.

Depending on the changes, this may include:
- Focused regression tests.
- Relevant existing test suites.
- Static analysis, linting, and type checking.
- Build or import validation.
- Integration tests.
- Runtime or headless application checks.
- Inspection of the final Git diff.

Do not rely solely on newly written tests. Run relevant existing tests to
check for regressions.

Distinguish clearly between:
- Automated tests that passed.
- Automated tests that failed.
- Static inspection.
- Headless runtime validation.
- Actual visual or interactive verification performed by a human.

Never claim that visual appearance, gameplay feel, or interactive behavior
has been verified when only static inspection or headless tests were performed.

If manual verification is necessary, do not treat it as a reason to stop
the implementation early. Complete all available automated validation first,
then provide the user with explicit, step-by-step instructions for the
remaining manual checks.

For visual or gameplay tasks, identify the specific things the user needs
to inspect, such as camera framing, collision behavior, interaction prompts,
input handling, and transitions between states.

## 8. Final Report

After completing the task, provide a concise but sufficiently detailed report
containing:

1. **Status:** Whether the requested task is complete and whether all
   acceptance criteria were satisfied.
2. **Root causes:** The underlying issues identified and how they were resolved.
3. **Implementation:** The important changes and decisions made.
4. **Files changed:** The relevant files created, modified, or deleted.
5. **Tests and validation:** Commands or test suites run and their exact results,
   including counts and failures when available.
6. **Regression status:** Whether any new regressions were identified and
   whether documented pre-existing failures remain.
7. **Manual verification:** Any remaining user-performed checks, with
   step-by-step instructions.
8. **Git status:** Confirmation that no commit or push occurred unless the
   user explicitly authorized it.

Do not report a test as passing unless it actually ran and passed.
Do not claim a file was modified unless the change was made.
Do not claim visual or interactive behavior was verified unless that
verification actually occurred.

## 9. Definition of Done

A task is complete when:
- All requested implementation stages have been executed.
- The requested functionality has been implemented.
- Relevant automated validation has been run.
- Regressions caused by the changes have been corrected where possible.
- The final diff has been reviewed.
- Remaining failures, limitations, and manual verification requirements
  have been documented.
- The final report accurately reflects the actual state of the project.

Do not stop early to request permission for work already authorized.
Do not declare completion merely because implementation has stopped.

## Efficient Command Execution

- Complete the requested task autonomously, including inspection,
  implementation, testing, regression fixes, and final diff review.
- Do not ask for approval between internal implementation stages.
- Prefer existing project tools and test runners over custom shell
  command sequences.
- Prefer simple, explicit commands over commands that combine
  background processes, subshells, heredocs, pipelines, and dynamic
  path substitutions.
- Reuse an existing diagnostic or test runner whenever possible.
- If a diagnostic is needed repeatedly, create a small, reusable,
  well-scoped script rather than repeatedly constructing new commands.
- Keep temporary diagnostics separate from production code.
- Avoid unnecessary shell wrappers that only print exit codes or
  filter a few lines of output.
- Do not retry a denied operation repeatedly.
- If a command is denied, use an authorized alternative when possible.
  Otherwise, report the exact blocker.
- Never split a prohibited operation into smaller commands to bypass
  a permission restriction.
- Never change permission settings or broaden permissions without
  explicit authorization.
- Preserve all uncommitted work.
- Never commit or push without explicit authorization.
- Ask the user only when a genuine decision or consequential action
  requires their input.

## Reusable Test Runner

The project's Godot headless regression suite lives in `tests/` (not in
the Claude scratchpad, which is ephemeral and does not persist between
sessions). Run it with `tests/run_tests.sh` (or `bash tests/run_tests.sh`),
optionally followed by one or more test names to run a subset, e.g.
`tests/run_tests.sh test_sleep_wake test_day_plan`. It prints each test's
own output plus a final PASS/FAIL/SKIPPED summary line per test, and exits
nonzero if anything failed or a named script was not found.

Every run also writes its full output to `tests/.last_run.log` (a fixed,
gitignored path, overwritten each run) on its own — never pipe or
redirect the runner's own output (`... > somefile.log`) to get a log;
the file is already there afterward. Likewise, invoke it as a plain
`tests/run_tests.sh [args]` from the project root — do not prefix it
with `cd <path> &&` (the shell's working directory already persists
between commands in the same session) or wrap it in extra pipes. Each
of those additions makes the literal command text different from the
permitted pattern and is the actual reason routine test runs end up
re-prompting for approval — it is a command-construction habit to avoid,
not something more permission rules should chase.

For a single Godot smoke/parse check (no test suite), the plain,
already-permitted command is `godot --headless --path . --quit-after 3`
— again, invoke it directly, not wrapped in `cd`/pipes/redirection.

When adding a new durable regression test, save it to `tests/<name>.gd`
and add `<name>` to the `TESTS` array near the top of
`tests/run_tests.sh`, rather than leaving it in the scratchpad or writing
a new one-off permission rule for it. One-off, throwaway diagnostics that
are not meant to be re-run later can still live in the scratchpad as
before — do not promote a scratchpad experiment into `tests/` unless its
behavior is genuinely useful and gets documented like the rest of the
suite.

This note describes the approved, already-permitted way to run tests
efficiently — it does not grant any permission by itself. Claude Code's
actual permission settings (`.claude/settings.local.json`) are the only
thing that controls which commands run without a prompt, and this file
cannot expand, override, or bypass them.