# Linux & Infrastructure Collection Design

## Purpose

This document defines the first technical reference collection for Open WebUI Workspace.

The collection is documentation only. It does not upload content, change COOPER behavior, or alter Workspace structure.

### Collection Scope

- Linux administration
- Pop!_OS
- Ubuntu
- systemd
- SSH
- LUKS
- KVM/QEMU
- GPU passthrough
- Docker host management
- storage management
- backups and recovery

## Intended COOPER Use Cases

The collection should help COOPER with:

- Linux troubleshooting
- migration support
- VM administration
- Docker support
- system recovery
- workstation maintenance

## Category Rules

- Category 1 content is allowed.
- Credentials are prohibited.
- Host-specific secrets are prohibited.
- Private logs are prohibited.
- Incident data is prohibited.

Any material that is not clearly safe for Category 1 use should be excluded or sanitized before upload.

## Candidate Source Material

### Approved

- Official documentation
- Architecture notes
- SOPs
- Build guides
- Non-sensitive personal migration notes that do not contain secrets, host identifiers, or incident detail

### Needs Sanitization

- Personal migration notes with hostnames, usernames, IPs, paths, or operational detail that is not intended for broad reference
- Build guides that include environment-specific values
- Architecture notes with machine identifiers or private network information

### Prohibited

- Credentials
- Private keys
- API tokens
- Host-specific secrets
- Private incident logs
- Sensitive operational exports
- Any Category 2 material that has not been explicitly sanitized for Category 1 use

## Collection Structure

Suggested subtopics:

- Linux Fundamentals
- Pop!_OS
- Virtualization
- Docker
- Storage
- Networking
- Security

## Retrieval Test Questions

Examples:

- How do I check LUKS status?
- How do I mount an encrypted volume?
- How do I configure Docker on Pop!_OS?
- How does GPU passthrough work?

## Maintenance Plan

- Owner: infrastructure maintainer
- Review cycle: monthly or whenever the Linux environment, reference set, or workstation architecture changes
- Update process: add only approved Category 1 material, remove stale references, and re-sanitize any note that drifts toward environment-specific detail

## Definition of Done

Before upload, the collection should satisfy the following:

- source list is approved
- Category 1 boundary is documented
- prohibited material is excluded
- retrieval questions are defined
- maintenance ownership is assigned
- document set is ready for manual Open WebUI ingestion

## Recommended Document Sources

- Official Linux, Pop!_OS, Ubuntu, systemd, SSH, LUKS, KVM/QEMU, and Docker documentation
- Personal migration notes that have been sanitized for reuse
- Internal architecture notes that are non-sensitive
- SOPs for workstation setup, maintenance, backup, and recovery
- Build guides that describe reproducible setup steps without secrets

## Risks

- Host-specific notes leaking into a shared knowledge collection
- Sensitive logs or incident data being used as reference material
- Environment drift making the collection stale
- Mixing troubleshooting references with execution instructions
- Turning the collection into a catch-all infrastructure dump

## Readiness Assessment

The collection is ready for Phase 5B.1 documentation work.

It is not ready for upload until the approved source documents are identified, sanitized where needed, and reviewed against the Category 1 boundary.

