#!/usr/bin/env bash

# Source this file from an existing shell to expose host NVIDIA driver libraries
# inside the repo's Nix + uv environment:
#
#   source scripts/fix_cuda_env.sh
#
# This is useful when `nvidia-smi` works but PyTorch reports:
#   torch.cuda.is_available() == False
# or:
#   RuntimeError: Found no NVIDIA driver on your system

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This script must be sourced so its exports affect your current shell."
  echo "Use:"
  echo "  source scripts/fix_cuda_env.sh"
  exit 1
fi

_fix_cuda_prepend_path() {
  local var_name="$1"
  local new_path="$2"
  local current_value="${!var_name:-}"
  local updated_value=""
  local seen=""

  if [[ -z "$new_path" || ! -d "$new_path" ]]; then
    return 0
  fi

  if [[ -n "$current_value" ]]; then
    IFS=':' read -r -a _fix_cuda_parts <<< "$current_value"
    for _fix_cuda_part in "${_fix_cuda_parts[@]}"; do
      if [[ -n "$_fix_cuda_part" && "$_fix_cuda_part" == "$new_path" ]]; then
        return 0
      fi
    done
  fi

  if [[ -n "$current_value" ]]; then
    updated_value="${new_path}:${current_value}"
  else
    updated_value="${new_path}"
  fi

  export "${var_name}=${updated_value}"
}

_fix_cuda_print_header() {
  echo "== CUDA driver visibility helper =="
}

_fix_cuda_print_header

declare -a _fix_cuda_candidate_dirs=(
  /usr/lib/x86_64-linux-gnu
  /usr/lib/x86_64-linux-gnu/nvidia/current
  /usr/lib/x86_64-linux-gnu/nvidia
  /usr/lib/nvidia
  /usr/lib/nvidia-590
  /usr/lib/nvidia-580
  /usr/lib/nvidia-575
  /usr/lib/nvidia-570
  /lib/x86_64-linux-gnu
  /run/opengl-driver/lib
  /usr/lib/wsl/lib
)

declare -a _fix_cuda_added_dirs=()
_fix_cuda_libcuda_dir=""
_fix_cuda_nvml_dir=""

for _fix_cuda_dir in "${_fix_cuda_candidate_dirs[@]}"; do
  [[ -d "$_fix_cuda_dir" ]] || continue

  _fix_cuda_add_dir=0
  if [[ -e "$_fix_cuda_dir/libcuda.so.1" ]]; then
    [[ -n "$_fix_cuda_libcuda_dir" ]] || _fix_cuda_libcuda_dir="$_fix_cuda_dir"
    _fix_cuda_add_dir=1
  fi
  if [[ -e "$_fix_cuda_dir/libnvidia-ml.so.1" ]]; then
    [[ -n "$_fix_cuda_nvml_dir" ]] || _fix_cuda_nvml_dir="$_fix_cuda_dir"
    _fix_cuda_add_dir=1
  fi

  if [[ "$_fix_cuda_add_dir" -eq 1 ]]; then
    _fix_cuda_prepend_path LD_LIBRARY_PATH "$_fix_cuda_dir"
    _fix_cuda_added_dirs+=("$_fix_cuda_dir")
  fi
done

if [[ -n "$_fix_cuda_libcuda_dir" ]]; then
  export TRITON_LIBCUDA_PATH="$_fix_cuda_libcuda_dir"
fi

if [[ "${#_fix_cuda_added_dirs[@]}" -gt 0 ]]; then
  echo "Added or confirmed NVIDIA library directories:"
  printf '  %s\n' "${_fix_cuda_added_dirs[@]}"
else
  echo "Could not find libcuda.so.1 or libnvidia-ml.so.1 in the common host locations."
  echo "Check the host driver install before retrying."
fi

echo "TRITON_LIBCUDA_PATH=${TRITON_LIBCUDA_PATH:-<unset>}"

if command -v nvidia-smi >/dev/null 2>&1; then
  _fix_cuda_gpu_names=""
  if _fix_cuda_gpu_names="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)"; then
    :
  else
    _fix_cuda_gpu_names=""
  fi

  if [[ -n "$_fix_cuda_gpu_names" ]]; then
    echo "Detected GPU(s):"
    while IFS= read -r _fix_cuda_gpu_name; do
      [[ -n "$_fix_cuda_gpu_name" ]] && echo "  $_fix_cuda_gpu_name"
    done <<< "$_fix_cuda_gpu_names"
  fi

  if echo "$_fix_cuda_gpu_names" | grep -Eq 'A100-SXM|H100|H800|A800|HGX'; then
    if command -v systemctl >/dev/null 2>&1; then
      _fix_cuda_fm_status="$(systemctl is-active nvidia-fabricmanager.service 2>/dev/null || true)"
      if [[ "$_fix_cuda_fm_status" == "active" ]]; then
        echo "nvidia-fabricmanager.service is active."
      else
        echo "Warning: nvidia-fabricmanager.service is not active."
        echo "If CUDA still fails, start it with:"
        echo "  sudo systemctl enable --now nvidia-fabricmanager.service"
      fi
    fi
  fi
fi

if command -v python >/dev/null 2>&1; then
  python - <<'PY'
import ctypes
import os
import sys

print("== Python CUDA sanity check ==")
for lib in ("libcuda.so.1", "libnvidia-ml.so.1"):
    try:
        ctypes.CDLL(lib)
        print(f"{lib}: OK")
    except OSError as exc:
        print(f"{lib}: FAIL ({exc})")

try:
    import torch
except Exception as exc:
    print(f"torch import: FAIL ({exc})")
    sys.exit(0)

print(f"torch = {torch.__version__}")
print(f"torch.version.cuda = {torch.version.cuda}")
print(f"torch.cuda.is_available() = {torch.cuda.is_available()}")
print(f"torch.cuda.device_count() = {torch.cuda.device_count()}")
print(f"LD_LIBRARY_PATH = {os.environ.get('LD_LIBRARY_PATH')}")
PY
fi

echo "If torch.cuda.is_available() is still False, retry after:"
echo "  1. reopening the Nix dev shell"
echo "  2. sourcing this helper again"
echo "  3. starting nvidia-fabricmanager on A100/HGX systems if needed"

unset _fix_cuda_dir
unset _fix_cuda_add_dir
unset _fix_cuda_gpu_name
unset _fix_cuda_gpu_names
unset _fix_cuda_fm_status
unset _fix_cuda_libcuda_dir
unset _fix_cuda_nvml_dir
unset _fix_cuda_candidate_dirs
unset _fix_cuda_added_dirs
unset -f _fix_cuda_prepend_path
unset -f _fix_cuda_print_header
