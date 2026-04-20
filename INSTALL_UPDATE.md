# Psi0-handless Install Update

This file summarizes the working install path we converged on for the
`SavvyProp/Psi0-handless` fork.

It is intentionally fork-specific. The upstream `physical-superintelligence-lab/Psi0`
README assumes the top-level `third_party/SIMPLE` submodule can be checked out
normally. In this fork, that gitlink currently points at a SIMPLE commit that is
not available from the public remote, so the reliable setup path is:

1. clone this fork
2. manually clone public `physical-superintelligence-lab/SIMPLE` into
   `third_party/SIMPLE`
3. rewrite SIMPLE's nested SSH submodule fetches to HTTPS during checkout
4. verify `curobo` and the other editable SIMPLE deps before running `uv sync`


## 0. Cross-Check Against Official Psi0 Docs

This file has been checked against the current public docs in
`physical-superintelligence-lab/Psi0`:

- the root `README.md` installation section
- `examples/quick_start/psi.md`
- `real/README.md`
- `baselines/pi05/README.md`

The intent is not to replace the official instructions, but to document the
extra steps this fork needs.

What stays the same as upstream:

- the core repo Python environment still uses `uv venv`, `uv sync`, and
  `flash_attn`
- the real-world deployment environment still uses `real/psi_deploy_env.yaml`
  and a separate `conda` env
- the OpenPI baseline still uses a separate `.venv-openpi` and the
  `transformers_replace` patch step

What is different in this fork:

- the official upstream docs assume the top-level `third_party/SIMPLE`
  checkout works normally; this fork currently needs a manual SIMPLE clone
- the official upstream docs often show GitHub SSH clone URLs; this file uses
  HTTPS equivalents where possible so GitHub SSH keys are not required
- the official upstream root install section is mostly `uv`-first, while the
  official `examples/quick_start/psi.md` already expects a top-level
  `nix develop` shell for the `psi + simple` path; this fork still needs extra
  submodule repair and, on some machines, `LD_PRELOAD` cleanup before that
  shell works reliably


## 1. Prerequisites

Validated target:

- Ubuntu 22.04
- Python 3.10
- NVIDIA GPU for SIMPLE / Isaac Sim workflows
- `git`, `git-lfs`, `curl`, `ffmpeg`, build tools
- `uv`
- `nix` for the composed `psi + simple` runtime shell

Suggested system packages:

```bash
sudo apt update
sudo apt install -y \
  git git-lfs curl ffmpeg \
  build-essential python3-dev python3-venv
```

Install `uv` if needed:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Install `nix` if needed:

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Open a new shell after installing Nix.

If `nix` is still not found in your current shell, source the daemon profile
manually:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```


## 2. Fresh Clone For This Fork

Clone the fork:

```bash
git clone https://github.com/SavvyProp/Psi0-handless.git
cd Psi0-handless
```

Do not rely on a plain top-level:

```bash
git submodule update --init --recursive
```

for this fork. The current top-level `third_party/SIMPLE` gitlink may fail with
an error similar to:

```text
Fetched in submodule path 'third_party/SIMPLE', but it did not contain <sha>
```


## 3. Bootstrap SIMPLE Manually

If you already have a half-initialized `third_party/SIMPLE`, clean it first:

```bash
git submodule deinit -f -- third_party/SIMPLE 2>/dev/null || true
rm -rf third_party/SIMPLE .git/modules/third_party/SIMPLE
```

Keep the repo-local submodule URL pointed at the public SIMPLE repo:

```bash
git config -f .gitmodules submodule.third_party/SIMPLE.url \
  https://github.com/physical-superintelligence-lab/SIMPLE.git
git submodule sync --recursive
```

Clone SIMPLE manually:

```bash
git clone https://github.com/physical-superintelligence-lab/SIMPLE.git third_party/SIMPLE
```


## 4. Initialize SIMPLE Nested Submodules Over HTTPS

SIMPLE's `.gitmodules` currently mixes HTTPS and SSH URLs. On machines without
GitHub SSH keys, nested submodule checkout will fail unless SSH-style
`git@github.com:` URLs are rewritten to HTTPS during the update command.

Use:

```bash
git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init --recursive
```

Notes:

- `url."https://github.com/".insteadOf=git@github.com:` rewrites nested GitHub
  SSH URLs to HTTPS for this command.
- `protocol.file.allow=always` helps on systems where Git blocks local file
  transport inside recursive submodules.


## 5. Repair `curobo` If Needed

The most common remaining blocker after the nested submodule fetch is `curobo`.
Two failure modes showed up during setup:

### 5.1 `uv sync` says `third_party/SIMPLE/third_party/curobo` is not a Python project

This means the `curobo` submodule did not finish checking out. Repair it with:

```bash
git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init third_party/curobo
```

### 5.2 `curobo` checkout fails because `.gitattributes` would be overwritten

If you see:

```text
error: The following untracked working tree files would be overwritten by checkout:
    .gitattributes
```

then remove the stray file and retry:

```bash
rm -f third_party/SIMPLE/third_party/curobo/.gitattributes

git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init third_party/curobo
```

If `curobo` is still broken, do a targeted reset:

```bash
git -C third_party/SIMPLE submodule deinit -f -- third_party/curobo
rm -rf third_party/SIMPLE/third_party/curobo

git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init third_party/curobo
```


## 6. Verify The Editable SIMPLE Dependencies

Before running the repo-level `uv sync`, verify the nested editable packages
that the lockfile expects are present.

Metadata checks:

```bash
test -f third_party/SIMPLE/third_party/curobo/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/curobo/setup.py && echo curobo-meta-ok

test -f third_party/SIMPLE/third_party/decoupled_wbc/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/decoupled_wbc/setup.py && echo decoupled-wbc-meta-ok

test -f third_party/SIMPLE/third_party/gear_sonic/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/gear_sonic/setup.py && echo gear-sonic-meta-ok

test -f third_party/SIMPLE/third_party/unitree_sdk2_python/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/unitree_sdk2_python/setup.py && echo unitree-sdk2-meta-ok

test -f third_party/SIMPLE/third_party/XRoboToolkit-PC-Service-Pybind_X86_and_ARM64/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/XRoboToolkit-PC-Service-Pybind_X86_and_ARM64/setup.py && echo xrobotoolkit-meta-ok

test -f third_party/SIMPLE/third_party/openpi-client/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/openpi-client/setup.py && echo openpi-client-meta-ok
```

Submodule health:

```bash
git -C third_party/SIMPLE submodule status --recursive
```

Interpretation:

- a leading space is good
- a leading `-` means uninitialized
- a leading `+` means checked out at a different commit than SIMPLE expects

For `curobo`, do not proceed until:

- `curobo-meta-ok` prints
- `git -C third_party/SIMPLE submodule status --recursive | grep curobo`
  starts with a space, not `+`


## 7. Git LFS

Install Git LFS:

```bash
git lfs install
```

Install LFS hooks in SIMPLE's nested submodules:

```bash
git -C third_party/SIMPLE submodule foreach --recursive 'git lfs install --local || true'
```

Pulling all LFS content is optional and can be noisy. Only do it after the
recursive submodule update has completed successfully:

```bash
git -C third_party/SIMPLE submodule foreach --recursive 'git lfs pull || true'
```

For the main Python install, using `GIT_LFS_SKIP_SMUDGE=1` is still recommended.


## 8. Main Psi0-handless Python Environment

The official upstream `README.md` shows a minimal `uv`-based install for the
main `psi` environment, while the official `examples/quick_start/psi.md`
expects the top-level Nix dev shell for the third-party SIMPLE path. For this
fork, that Nix-first route is the validated path so `curobo` builds against the
same CUDA toolchain as the repo's PyTorch wheels.

The validated path for the main environment is:

1. enter the integrated Nix shell
2. create `.venv-psi`
3. run the repo-level `uv sync`
4. install `flash_attn`

Commands:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" develop -c bash
```

After the dev shell opens:

```bash
uv venv .venv-psi --python 3.10
source .venv-psi/bin/activate

GIT_LFS_SKIP_SMUDGE=1 uv sync --all-groups --index-strategy unsafe-best-match --active
uv pip install flash_attn==2.7.4.post1 --no-build-isolation

cp .env.sample .env
```

Sanity checks:

```bash
python -c "import psi; print(psi.__version__)"
python -c "import simple; print(simple.__version__)"
python -c "from psi.data.lerobot.compat import LEROBOT_LAYOUT; print(LEROBOT_LAYOUT)"
```

Important CUDA note:

- `nvidia-smi` reports the driver/runtime compatibility level, not necessarily
  the CUDA toolkit that extension builds will use.
- For this repo, the intended build toolchain comes from the Nix shell and is
  pinned to CUDA `12.8`.
- If you run `uv sync` outside the Nix shell, `curobo` may pick up a host CUDA
  toolkit such as `11.5`, which will fail against the repo's PyTorch
  `cu128` wheels.

Useful checks inside the shell that will run `uv sync`:

```bash
which nvcc
nvcc --version
echo "$CUDA_HOME"
python -c "import torch; print(torch.version.cuda)"
```

Expected shape:

- `torch.version.cuda` should be `12.8`
- `nvcc --version` should also report CUDA `12.8`
- `CUDA_HOME` should point into the Nix shell's CUDA toolkit

If `nvcc --version` reports something else such as `11.5`, do not proceed with
`uv sync` until you have entered the Nix shell correctly.

If `nvidia-smi` works but PyTorch still reports no CUDA devices, for example:

```text
RuntimeError: Found no NVIDIA driver on your system
```

or:

```bash
python - <<'PY'
import torch
print(torch.cuda.is_available())
print(torch.cuda.device_count())
PY
```

prints `False` and `0`, then the problem is usually CUDA driver visibility
inside the Python/Nix environment, not the repo itself.

Check the current PyTorch and driver-library view:

```bash
python - <<'PY'
import os, ctypes, ctypes.util, torch
print("torch", torch.__version__)
print("torch.version.cuda =", torch.version.cuda)
print("LD_LIBRARY_PATH =", os.environ.get("LD_LIBRARY_PATH"))
print("find_library(cuda) =", ctypes.util.find_library("cuda"))
for lib in ["libcuda.so.1", "libnvidia-ml.so.1"]:
    try:
        ctypes.CDLL(lib)
        print(lib, "OK")
    except OSError as e:
        print(lib, "FAIL", e)
PY

ldconfig -p | grep -E 'libcuda\.so\.1|libnvidia-ml\.so\.1' || true
```

On Ubuntu-like systems, a common fix is that `libcuda.so.1` exists in
`/usr/lib/x86_64-linux-gnu`, but that directory is not visible enough inside
the shell. In that case, retry with:

```bash
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/nvidia/current:/usr/lib/nvidia-590:${LD_LIBRARY_PATH:-}
export TRITON_LIBCUDA_PATH=/usr/lib/x86_64-linux-gnu
```

This repo also includes a helper that tries the common host-driver library
locations and reruns the sanity check for the current shell:

```bash
source scripts/fix_cuda_env.sh
```

Then re-test:

```bash
python - <<'PY'
import torch
print("cuda_available =", torch.cuda.is_available())
print("device_count   =", torch.cuda.device_count())
PY
```

If the host uses A100 SXM / HGX hardware, also check whether Fabric Manager is
running:

```bash
systemctl status nvidia-fabricmanager.service --no-pager
```

If it is inactive, start it and retry:

```bash
sudo systemctl enable --now nvidia-fabricmanager.service
```

Only proceed to `uv sync`, model serving, or training once
`torch.cuda.is_available()` is `True`.

If `uv sync` fails while extracting large CUDA wheels such as
`nvidia-cudnn-cu12` with:

```text
No space left on device (os error 28)
```

then the target machine has run out of space in the filesystem backing
`~/.cache/uv` (or the temporary directory used by `uv`). The full `psi +
simple` environment is large, so this can happen even after the Nix shell is
working correctly.

Check available space:

```bash
df -h ~ ~/.cache /tmp
du -sh ~/.cache/uv 2>/dev/null || true
```

If needed, clean only the incomplete `uv` temporary extracts and retry:

```bash
rm -rf ~/.cache/uv/.tmp*
```

If your home directory is small, point `uv` at a larger filesystem and rerun:

```bash
mkdir -p /path/with-space/.uv-cache

UV_CACHE_DIR=/path/with-space/.uv-cache \
GIT_LFS_SKIP_SMUDGE=1 \
uv sync --all-groups --index-strategy unsafe-best-match --active
```

If `flash_attn` then fails with:

```text
ModuleNotFoundError: No module named 'setuptools'
```

that usually means the earlier `uv sync` did not finish, so the environment is
only partially populated. First complete `uv sync` successfully. Then run:

```bash
uv pip install setuptools wheel
uv pip install flash_attn==2.7.4.post1 --no-build-isolation
```


## 9. Optional Baseline Environments

The repo uses a shared codebase with separate optional environments for
baselines. The main `psi` environment is not the only environment in the repo.

### H-RDT

```bash
cd src/h_rdt
uv sync --frozen
```

### EgoVLA

```bash
cd src/egovla
uv sync --frozen
```

### GR00T

```bash
cd src/gr00t
uv sync --frozen
```

### InternVLA-M1

```bash
cd src/InternVLA-M1
uv sync --python 3.10
```

### OpenPI pi0.5

If you have not already loaded `.env`, do it first so `PSI_HOME` is available.
This matches the assumption in the official `baselines/pi05/README.md`.

```bash
source .env
```

```bash
uv venv .venv-openpi --python 3.10
source .venv-openpi/bin/activate

VIRTUAL_ENV=.venv-openpi uv pip install -e .
VIRTUAL_ENV=.venv-openpi uv pip install -e src/openpi/openpi-client
VIRTUAL_ENV=.venv-openpi GIT_LFS_SKIP_SMUDGE=1 uv pip install -r baselines/pi05/requirements-openpi.txt

cp -r src/openpi/models_pytorch/transformers_replace/* \
  .venv-openpi/lib/python3.10/site-packages/transformers/
```

### Diffusion Policy

```bash
uv venv .venv-dp --python 3.10
source .venv-dp/bin/activate

GIT_LFS_SKIP_SMUDGE=1 uv sync --group serve --group viz --active --frozen
VIRTUAL_ENV=.venv-dp uv pip install -e .
VIRTUAL_ENV=.venv-dp uv pip install -r baselines/dp/requirements-dp.txt

cp src/lerobot_patch/common/datasets/lerobot_dataset.py \
  .venv-dp/lib/python3.10/site-packages/lerobot/common/datasets/lerobot_dataset.py
```

### ACT

```bash
uv venv .venv-act --python 3.10
source .venv-act/bin/activate

GIT_LFS_SKIP_SMUDGE=1 uv sync --group psi --group serve --group viz --active --frozen

cp src/lerobot_patch/common/datasets/lerobot_dataset.py \
  .venv-act/lib/python3.10/site-packages/lerobot/common/datasets/lerobot_dataset.py
```


## 10. Real-World Deployment Environment

The real-world teleoperation / RTC deployment path under `real/` is separate
from the repo-level `.venv-psi` environment. This matches the official
`real/README.md`, except the Unitree SDK clone below uses HTTPS instead of SSH.

Create the Conda env:

```bash
cd real
conda env create -f psi_deploy_env.yaml
conda activate psi_deploy
```

Install Unitree SDK2 Python:

```bash
git clone https://github.com/physical-superintelligence-lab/unitree_sdk2_python.git
cd unitree_sdk2_python
pip install -e .
cd ..
```

Install the local `real/` package:

```bash
pip install -e .
```

Start the host-side RTC client:

```bash
bash ./scripts/deploy_psi0-rtc.sh
```

Robot-side image server environment:

```bash
conda create -n vision python=3.8
conda activate vision
pip install pyrealsense2 opencv-python zmq numpy
```

On the robot PC, start the image server from `real/teleop/image_server`:

```bash
python realsense_server.py
```


## 11. Handless Runtime Notes

Current short notes from `HandlessREADME.md`:

- simulator server script: `psi0_serve_simple.py`
- deployment server script: `psi_serve_rtc-trainingtimertc.py`
- teleop policy modified for try/except hand launch: `master_whole_body.py`

Observed runtime flow:

- start and stand for around 30 seconds
- switch to VLA
- execute one VLA task

Commands:

```bash
bash ./scripts/deploy/serve_psi0-rtc.sh
bash ./real/scripts/deploy_psi0-rtc.sh
```


## 12. Troubleshooting Summary

### Top-level SIMPLE submodule fails with missing commit

Symptom:

```text
Fetched in submodule path 'third_party/SIMPLE', but it did not contain <sha>
```

Fix: do not rely on the fork's top-level SIMPLE gitlink. Use the manual SIMPLE
clone workflow in sections 2 through 4.

### Nested SIMPLE submodules fail with `Permission denied (publickey)`

Symptom:

```text
git@github.com: Permission denied (publickey)
```

Fix: rerun the SIMPLE recursive submodule update with:

```bash
-c url."https://github.com/".insteadOf=git@github.com:
```

### `uv sync` fails on `nvidia-curobo`

Symptom:

```text
Failed to generate package metadata for nvidia-curobo
```

Fix: repair `third_party/SIMPLE/third_party/curobo` first, then verify:

```bash
test -f third_party/SIMPLE/third_party/curobo/pyproject.toml -o \
     -f third_party/SIMPLE/third_party/curobo/setup.py && echo curobo-meta-ok

git -C third_party/SIMPLE submodule status --recursive | grep curobo
```

If the error instead says:

```text
The detected CUDA version ... mismatches the version that was used to compile PyTorch
```

then the issue is not the `curobo` checkout. It means the extension build is
using the wrong CUDA toolkit. For this repo, PyTorch is expected to use CUDA
`12.8`, and the matching toolkit is supplied by the Nix shell.

Check:

```bash
which nvcc
nvcc --version
echo "$CUDA_HOME"
python -c "import torch; print(torch.version.cuda)"
```

If `torch.version.cuda` is `12.8` but `nvcc --version` reports `11.5`, you are
building against the host CUDA toolkit instead of the repo's Nix-provided
toolchain. Re-enter the Nix shell and rerun `uv sync`.

### `nix` is not found or `nix develop` shows preload noise

Symptoms:

```text
env: 'nix': No such file or directory
```

or repeated messages like:

```text
ERROR: ld.so: object '...libxalt_init.so' from LD_PRELOAD cannot be preloaded
```

Fix:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" develop -c bash
```

On managed machines, clearing `LD_PRELOAD` is often necessary before entering
the repo's Nix shell.

### `curobo` checkout blocked by `.gitattributes`

Fix:

```bash
rm -f third_party/SIMPLE/third_party/curobo/.gitattributes
```

then rerun the targeted `curobo` submodule update.

### `git lfs pull` errors inside nested repos

Do not debug LFS until the recursive submodule checkout is clean. LFS issues are
secondary if the working tree is still incomplete.


## 13. Recommended Order

If setting this up from zero, the shortest reliable order is:

```bash
git clone https://github.com/SavvyProp/Psi0-handless.git
cd Psi0-handless

git submodule deinit -f -- third_party/SIMPLE 2>/dev/null || true
rm -rf third_party/SIMPLE .git/modules/third_party/SIMPLE

git config -f .gitmodules submodule.third_party/SIMPLE.url \
  https://github.com/physical-superintelligence-lab/SIMPLE.git
git submodule sync --recursive

git clone https://github.com/physical-superintelligence-lab/SIMPLE.git third_party/SIMPLE

git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init --recursive

rm -f third_party/SIMPLE/third_party/curobo/.gitattributes

git -C third_party/SIMPLE \
  -c url."https://github.com/".insteadOf=git@github.com: \
  -c protocol.file.allow=always \
  submodule update --init third_party/curobo

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" develop -c bash
```

Then, inside that dev shell:

```bash
uv venv .venv-psi --python 3.10
source .venv-psi/bin/activate

GIT_LFS_SKIP_SMUDGE=1 uv sync --all-groups --index-strategy unsafe-best-match --active
uv pip install flash_attn==2.7.4.post1 --no-build-isolation
```

That is the working install path this file is meant to preserve.


## 14. Nix Flake Compatibility Note

The public SIMPLE repo's flake may require an input named
`nixpkgs-unstable`. If the root dev shell fails with an error like:

```text
function 'outputs' called without required argument 'nixpkgs-unstable'
```

then the checked-out `third_party/SIMPLE/flake.nix` needs to declare that
input name, and the root `flake.nix` in this fork should wire SIMPLE's
stable and unstable package inputs separately.

Expected root-flake snippet:

```nix
nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-24.11";

simple = {
  url = "path:./third_party/SIMPLE";
  inputs.nixpkgs.follows = "nixpkgsStable";
  inputs.nixpkgs-unstable.follows = "nixpkgs";
};
```

The top-level `outputs` function must also accept the additional input, for
example:

```nix
outputs = { self, nixpkgs, simple, ... }:
```

Otherwise Nix will fail with:

```text
function 'outputs' called with unexpected argument 'nixpkgsStable'
```

Do not make `simple.inputs.nixpkgs` follow the root `nixpkgs` input here. The
root shell in this fork uses `nixos-unstable`, but SIMPLE's flake currently
expects its main `nixpkgs` input to remain on a branch that still exposes
`pkgs.python310`.

If you instead see both of these messages together:

```text
warning: input 'simple' has an override for a non-existent input 'nixpkgs-unstable'
function 'outputs' called without required argument 'nixpkgs-unstable'
```

then the problem is slightly different: the checked-out
`third_party/SIMPLE/flake.nix` is internally inconsistent. Its `outputs`
function expects `nixpkgs-unstable`, but its `inputs` block does not actually
declare that input name, so the root override cannot attach to it.

In that case, patch `third_party/SIMPLE/flake.nix` on the target machine so
its `inputs` block declares `nixpkgs-unstable`, for example:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  # ... the rest of SIMPLE's inputs ...
};
```

If you want a copy-paste shell command instead of editing by hand, this
repo-local patch is the smallest change:

```bash
grep -q 'nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";' \
  third_party/SIMPLE/flake.nix || \
  sed -i '/nixpkgs.url = "github:NixOS\/nixpkgs\/nixos-24.11";/a\    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";' \
  third_party/SIMPLE/flake.nix
```

Then rerun:

```bash
env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" flake lock

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" develop -c bash
```

The lockfile refresh matters here. If the root `flake.lock` still records the
old SIMPLE input graph, Nix may continue to think `simple` only has a
`nixpkgs` input and will keep printing:

```text
warning: input 'simple' has an override for a non-existent input 'nixpkgs-unstable'
```

You can inspect that case by checking whether the `simple` node in the root
`flake.lock` only lists `nixpkgs` under `inputs`. If `flake lock` is not
enough, recreate the root lockfile once:

```bash
mv flake.lock flake.lock.before-simple-input-fix

env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  nix --extra-experimental-features "nix-command flakes" flake lock
```

Then retry `nix develop`.

If the `nixpkgs-unstable` wiring error is fixed but `nix develop` then fails
with:

```text
error: attribute 'python310' missing
```

that means the root flake is still forcing SIMPLE's main `nixpkgs` input onto a
recent `nixos-unstable` revision. Upstream SIMPLE currently imports:

```nix
pkgs = import nixpkgs { ... };
unstablePkgs = import nixpkgs-unstable { ... };
pythonPkg = pkgs.python310;
```

and this fork's root Python environment is also pinned to Python 3.10. The
fix is to keep SIMPLE's `nixpkgs` input on a stable branch that still exposes
`python310` and only let SIMPLE's `nixpkgs-unstable` input follow the root
unstable package set.

If you prefer not to patch the vendored SIMPLE checkout manually, update
`third_party/SIMPLE` to a commit where its `flake.nix` declares the same input
names that its `outputs` function expects.
