# Implement a packaging check for configuration files.

## Objective
Implement a packaging check for configuration files.

## Background
A recent review identified that configuration files were not being packaged correctly, leading to silent failures. Addressing this issue is crucial to ensure that all necessary files are included in the deployment, preventing future runtime errors.

## Current State
Currently, the packaging process does not verify the inclusion of critical configuration files, which can lead to missing files in the deployed environment. This has already caused issues in previous deployments.

## Required Work
- Create a script to check for the presence of required configuration files in the build context.
- Integrate the script into the existing build process to run before the final image is created.
- Log any missing files as warnings during the build process.

## Constraints
- Do not add new frameworks.
- Do not redesign the router or workflow architecture.
- Do not include secrets, credentials, or private data.
- Keep the implementation minimal and reviewable.

## Validation
- Run the build process with the new script and verify that it correctly identifies missing configuration files.
- Ensure that the build fails if any required configuration files are not present.

## Definition of Done
- The packaging check script is implemented and integrated into the build process.
- All required configuration files are verified during the build.
- Documentation is updated to reflect the new packaging check process.
