# NotebookLM Sanitization Checklist

Updated: 2026-06-06

## Goal

Convert source material into a NotebookLM-safe learning package without leaking Category 2 content.

## Classification

- [ ] I reviewed the source material first.
- [ ] I classified the source as Category 1 or Category 2.
- [ ] I confirmed whether the content can safely be sanitized.

## Redaction Checklist

- [ ] Remove secrets
- [ ] Remove credentials
- [ ] Remove API keys
- [ ] Remove passwords
- [ ] Remove private keys
- [ ] Remove client names if they are sensitive
- [ ] Remove active operational details
- [ ] Remove internal hostnames or infrastructure identifiers if sensitive
- [ ] Remove raw logs that contain private data
- [ ] Remove screenshots containing sensitive UI or identifiers
- [ ] Remove protected source documents that cannot be shared

## Sanitization Rules

- [ ] Rewrite examples so they are generic
- [ ] Replace unique identifiers with placeholders
- [ ] Summarize rather than copy sensitive passages
- [ ] Keep only the learning value
- [ ] Preserve the concept, not the source exposure
- [ ] If the material still feels risky, do not upload it

## Upload Gate

Only upload when all of the following are true:

- [ ] The package is Category 1
- [ ] The package is clearly labeled sanitized
- [ ] The package contains no raw Category 2 material
- [ ] The package has a manifest and source list
- [ ] The package questions are specific and safe

## Local-Only Stop Conditions

Stop and keep the material local if any of these are true:

- [ ] The material includes secrets or credentials
- [ ] The material includes private operational details
- [ ] The material includes client-sensitive or investigative data
- [ ] The material cannot be safely generalized
- [ ] The material would be risky if uploaded to a cloud service

## Output Standard

Sanitized output should be:

- readable
- source-grounded
- useful for learning
- safe to upload to NotebookLM
- suitable for later Obsidian and PDA memory capture

