# Simplify: Find and Implement One Code Abstraction

Analyze the codebase for repeated or near-duplicate code patterns and implement
exactly **one** refactoring to reduce duplication.

## Goal

Find the single highest-value abstraction opportunity in the codebase and
implement it. This means extracting duplicated logic into a shared helper,
utility function, or common module — then updating all call sites to use it.

## Process

### 1. Scan for Duplication

Search the codebase for repeated patterns:
- Functions with similar signatures and logic across different files
- Copy-pasted code blocks with minor variations (different variable names,
  slightly different parameters)
- Repeated error handling, validation, or formatting patterns
- Similar struct/type definitions that could share a common base

**Exclude from analysis:**
- Test files (`*_test.*`, `test_*.*`, files in `test/` or `tests/` directories)
- Generated code and vendored dependencies
- Standard boilerplate (imports, license headers, package declarations)
- Small snippets under 5 lines unless repeated 4+ times

### 2. Evaluate and Pick One

Rank candidates by:
- **Lines saved**: more duplication eliminated = higher value
- **Maintainability**: reducing places where a bug fix must be applied
- **Clarity**: the abstraction makes the code easier to understand, not harder

Pick the single best candidate. If no significant duplication exists (nothing
over 10 duplicated lines or fewer than 3 instances), skip the task.

### 3. Implement the Refactoring

- Extract the shared logic into a well-named helper function or module
- Update all call sites to use the new abstraction
- Ensure the abstraction lives in a sensible location (e.g., a `utils` or
  `helpers` package, or alongside related code)
- Do not change behavior — this is a pure refactoring

### 4. Verify

- Run the relevant tests to confirm nothing is broken
- If tests fail, fix the issues before declaring success

## Constraints

- Implement exactly **one** abstraction. Do not bundle multiple refactorings.
- Do not change external behavior or public APIs.
- Do not refactor test code itself — only production code.
- Keep the abstraction simple. If it requires more than one new file or a
  complex generic type, it is probably too ambitious — pick a simpler candidate.
