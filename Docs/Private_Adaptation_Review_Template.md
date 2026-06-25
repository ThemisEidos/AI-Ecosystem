# Private Adaptation Review Template

## Purpose

Provide the required review template for evaluating whether an Open workflow, tool, skill, or capability can be ported into Private without weakening isolation or shared contract integrity.

## When Required

Use this template before any Open-to-Private port decision involving:

- workflow behavior
- tool role replacement
- skill adoption
- integration reuse
- capability migration with non-local assumptions

## Review Record

### Workflow / Tool / Skill Being Ported

- Name:
- Type:
- Open workshop role:

### Open Dependencies

- Open-only services:
- Open runtime assumptions:
- Open storage assumptions:

### Cloud / Internet / API Dependencies

- cloud dependency present:
- outbound internet dependency present:
- external API dependency present:
- assumption tags applied:

### Private-Data Exposure Risk

- private-data exposure risk:
- boundary risk summary:

### Required Local Alternative

- local alternative required:
- replacement approach:

### Removed Capabilities

- removed for Private:
- reason:

### Changed Implementation Details

- implementation differences:
- local restrictions added:

### Unchanged Shared Contract

- contract name:
- contract behavior preserved:
- approval semantics preserved:
- evidence expectations preserved:

### Test Evidence

- local test evidence:
- isolation verification reference:
- workflow validation reference:

### Approval Record

- reviewer role:
- review date:
- decision notes:

### Final Decision

- portable now
- portable with local alternative work
- Open-only for now
- rejected for Private

## Use Notes

- Open implementation details are not portable by default
- contract preservation is required
- Private isolation requirements override convenience
- missing evidence should be treated as review failure

## Related Documents

- [AI_Ecosystem_Implementation_Strategy.md](../Docs/AI_Ecosystem_Implementation_Strategy.md)
- [Private_Isolation_Verification_Standard.md](../Docs/Private_Isolation_Verification_Standard.md)
