# Runbook Standard

## Required Sections
Every active runbook MUST include:
- Purpose and scope
- Severity classification
- Preconditions
- Step-by-step execution
- Validation checkpoints
- Rollback criteria
- Incident logging requirements
- Owner and last review date

## Security Requirements
- Never include plaintext credentials, unseal keys, or privileged tokens.
- Reference secure retrieval process instead of embedding secrets.

## Break-Glass Requirements
- Define role-based authorization to execute break-glass operations.
- Record who executed each privileged action and when.
