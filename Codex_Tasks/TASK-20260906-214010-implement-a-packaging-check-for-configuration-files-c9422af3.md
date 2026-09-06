# Implement a packaging check for configuration files.

## Objective
Implement a packaging check for configuration files.

## Background
The recent deployment revealed gaps in the packaging of configuration files, specifically with the `PDA_RetryPolicy.json` and other critical files not being included in the built image. Addressing this will ensure that all necessary configuration files are correctly packaged and available in the deployment environment.

## Current State
Currently, the packaging of configuration files is incomplete, leading to potential failures in the system when these files are not found. This was evidenced by the missing `PDA_RetryPolicy.json` during the last deployment.

## Required Work
- Create a script to verify the presence of all required configuration files in the Docker image.
- Integrate this script into the Docker build process to ensure it runs during the image creation.
- Update the Dockerfile to include the necessary configuration files if they are missing.

## Constraints
- Do not add new frameworks.
- Do not redesign the router or workflow architecture.
- Do not include secrets, credentials, or private data.
- Keep the implementation minimal and reviewable.

## Validation
- Run the Docker build process and ensure the packaging check script executes without errors.
- Verify that all required configuration files are present in the built Docker image using a test container.

## Definition of Done
- The packaging check script is integrated into the Docker build process.
- All required configuration files are confirmed to be present in the Docker image.
- Documentation is updated to reflect the new packaging check process.
