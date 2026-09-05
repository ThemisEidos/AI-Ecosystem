FROM python:3.12-slim

# PowerShell for executor.py (registry tools run .ps1 scripts; executor tries
# powershell.exe then pwsh). Official binary tarball — the Microsoft apt repo
# signs with SHA1, which apt rejects since 2026-02-01. Invariant globalization
# avoids the libicu dependency (fine for local script execution).
ARG PWSH_VERSION=7.4.6
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget ca-certificates git \
 && wget -q "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-x64.tar.gz" -O /tmp/pwsh.tar.gz \
 && mkdir -p /opt/microsoft/powershell/7 \
 && tar zxf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
 && chmod +x /opt/microsoft/powershell/7/pwsh \
 && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
 && rm /tmp/pwsh.tar.gz \
 && apt-get purge -y wget \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

WORKDIR /app/cooper-core

COPY cooper-core/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY cooper-core/ .
# _REPO_ROOT resolves to /app — these paths must mirror the repo layout (spec §5, §8.2-8.3)
COPY Models/cooper-personality/Modelfile /app/Models/cooper-personality/Modelfile
COPY Config/general_tool_registry.yaml Config/private_tool_registry.yaml Config/skills_registry.yaml /app/Config/
# PDA_RetryPolicy.json is load-bearing, not documentation: retry_policy.py fails
# open to built-in defaults when it is absent, so omitting it here silently
# reverts every per-role timeout/retry budget to the fallback (Step 15f-ii).
COPY Scripts/Test-Exec.ps1 Scripts/Test-PDAStack.ps1 Scripts/PDA_ModelRouting.json Scripts/PDA_RetryPolicy.json /app/Scripts/
COPY Scripts/Python/ /app/Scripts/Python/
COPY Skills/ /app/Skills/
COPY PDA-Fabric/ /app/PDA-Fabric/

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
