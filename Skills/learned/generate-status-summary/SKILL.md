---
name: generate-status-summary
description: Use when the system needs to provide a concise overview of current operational status and context.
---

## When to use
When an end-user or internal monitor requests a summary of the current state, environment details, or recent interactions.

## Procedure
1. Identify the current timestamp and location/environment identifier (e.g., 'private workshop').
2. Check for available conversation history at the current layer.
3. If no prior history exists, report the status as a standalone operational summary including time and environment.\n4. Format the output clearly: 
   - **[Status Summary]** Header
   - Environment/Location details
   - Timestamp (UTC)
   - Current Request context.
