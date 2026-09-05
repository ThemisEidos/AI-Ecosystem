# Implement a packaging check for configuration files.

## Objective
Implement a packaging check for configuration files.

## Background
Recent deployments revealed that configuration files were missing from the built image, leading to silent failures. This task aims to ensure that all necessary configuration files are included in the Docker image to prevent future issues.

## Current State
Currently, the `PDA_RetryPolicy.json` file was not included in the built image, causing the system to revert to built-in fallbacks without any error or warning. This has been identified as a recurring issue during live verifications.

## Required Work
- Create a script to check for the presence of required configuration files in the Docker image.
- Integrate the script into the Docker build process to ensure it runs during the image creation.
- Log any missing files as errors during the build process.

## Constraints
- Do not add new frameworks.
- Do not redesign the router or workflow architecture.
- Do not include secrets, credentials, or private data.
- Keep the implementation minimal and reviewable.

## Validation
- Run the Docker build process and confirm that the script checks for the required configuration files.
- Verify that any missing files trigger an error message during the build.

## Definition of Done
- The script is integrated into the Docker build process.
- All required configuration files are checked and logged appropriately.
- No missing configuration files are allowed in the final Docker image.
