---
name: security-triage-alert
description: Use this when a security event (e.g., brute force, unauthorized access) is required to be analyzed and categorized.
---

## When to use
When an automated system or manual audit identifies suspicious activity such as repeated failed logins, port scanning, or unauthorized access attempts on specific endpoints.

## Procedure
1. **Identify the Source**: Extract the source IP address and the target endpoint (e.g., `workshop-endpoint`).
2. **Analyze Frequency**: Determine if the login attempts are repetitive within a short timeframe (brute force indicator).
3. **Categorize Alert**: Classify the event as `Authentication / Unauthorized Access Attempt`.
4. **Generate Report**: Create a structured alert containing:
    *   **Status**: Warning/Critical
    *   **Category**: The specific security domain.
    *   **Description**: A clear summary of the incident.
    *   **Action Required**: Specific remediation steps (e.g., rate limiting, IP blocking).
5. **Log & Notify**: Record the event in the security logs and notify the relevant system administrator.
