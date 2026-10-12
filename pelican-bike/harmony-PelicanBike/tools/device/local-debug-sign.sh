#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ps_script="$(cygpath -w "${script_dir}/local-debug-sign.ps1")"

powershell_bin="/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [[ ! -x "${powershell_bin}" ]]; then
  powershell_bin="$(command -v powershell.exe || true)"
fi
if [[ -z "${powershell_bin}" || ! -x "${powershell_bin}" ]]; then
  printf 'ERROR: Windows PowerShell was not found.\n' >&2
  exit 1
fi

# Disable MSYS argument rewriting. The PowerShell script accepts Windows and /d/... paths.
MSYS2_ARG_CONV_EXCL='*' exec "${powershell_bin}" \
  -NoLogo \
  -NoProfile \
  -NonInteractive \
  -ExecutionPolicy Bypass \
  -File "${ps_script}" \
  "$@"
