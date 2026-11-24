# Bonsai - Nix Flake

A Nix flake that installs [Bonsai-rx](https://bonsai-rx.org/) on Linux and macOS via a patched Wine build. Packages are provided for `x86_64-linux`, `aarch64-linux` (the x86_64 Wine build run through FEX), `x86_64-darwin` and `aarch64-darwin` (see [macOS](#macos)).

## What it provides

Every package is built from the release sets in `nix/releases.nix`, each of which pins a Bonsai version together with its dependencies. Bonsai packages are named after the Bonsai version and dependency packages after their own version; the unversioned names below build the latest release. See [Releases](#releases).

- `packages.bonsai` (also `packages.default`) — the `bonsai` launcher, the `bonsai-setup` helper, which initializes the Wine prefix and installs Bonsai into it, and `bonsai-wine`, which runs a command (`winecfg`, `winetricks`, `wine ...`) with the release's Wine against that prefix. The Wine tools themselves are not put on `PATH`.
- `packages.wine` — a patched WineHQ build (the Wine version and patches of the release set with the wine-staging patchset, nixpkgs `full` variant) exposed via shell shims: a `winetricks` shim and shims for `wine`, `wine64`, `wineboot`, `wineserver`, `winecfg`, `regedit`, `wineconsole`, `msiexec`, `winefile`, `notepad`, `uninstaller`, `winedbg`. It sets no `WINEPREFIX`, so Wine's own default prefix applies.
- `packages.bonsai-python` — the same launcher with a python.org Windows Python installed into the Wine prefix by `bonsai-setup`, for `Bonsai.Scripting.Python`.
- `packages.python-installer` — the fetched python.org amd64 installer (useful on its own for other prefixes).
- `packages.bonsai-cuda` — the same launcher with [nvidia-libs](https://github.com/SveSop/nvidia-libs) (CUDA, NVML, NVENC/NVDEC, OptiX, NvAPI) and the Windows CUDA toolkit runtime DLLs installed into the Wine prefix by `bonsai-setup`.
- `packages.bonsai-cuda-python` — `bonsai-cuda` with Python.
- `packages.nvidia-libs` — the unpacked nvidia-libs release bundle (useful on its own for other prefixes). When the release set pins nvcuda, the bundle's `nvcuda.dll` is replaced by the source-built one.
- `packages.cuda-redist` — the Windows CUDA runtime and cuDNN DLLs collected from NVIDIA's official redistributable archives.
- `packages.<name>_<bonsai version>` (e.g. `bonsai_2_9_1`, `bonsai-python_2_9_1`, `bonsai-cuda_2_9_1`, `bonsai-cuda-python_2_9_1`) — each of the Bonsai packages above pinned to one release set.
- `packages.<name>_<own version>` (e.g. `wine_11_22`, `nvidia-libs_1_0_5`, `cuda-redist_13_5_cudnn9_28_1`, `python-installer_3_12_10`) — each dependency pinned to one of its versions, built once and shared by the release sets that use it.
- `packages.nvcuda_<revision>` (e.g. `nvcuda_772b344`) — [nvcuda](https://github.com/SveSop/nvcuda) built from source at a pinned revision with that pin's patches. It exists only for revisions pinned by a release set, and an unversioned `packages.nvcuda` exists only when the latest release set pins nvcuda.
- `homeManagerModules.bonsai` — a Home Manager module exposing `programs.bonsai`. Adds the resolved package to `home.packages`.
- `nixosModules.bonsai` — a NixOS module exposing the same `programs.bonsai` interface. Adds the resolved package to `environment.systemPackages` for a system-wide install.

The `cuda` packages (`bonsai-cuda`, `bonsai-cuda-python`, `nvidia-libs`, `nvcuda`, `cuda-redist` and their pinned forms) are exposed on `x86_64-linux` only.

Both modules share a common backbone (`nix/common.nix`) that declares `programs.bonsai.enable`, `programs.bonsai.prefixName`, `programs.bonsai.winePrefixes`, the read-only `programs.bonsai.package` and `programs.bonsai.winePackage`, and submodule options under `programs.bonsai.wine` (version, sha256, stagingSha256, variant, mirror, patches, replaceUpstreamPatches, withWinetricks, extraEnv, emulator), `programs.bonsai.bonsai` (version, sha256, mirror, wineArch, winetricksVerbs, winetricksArgs, winetricksMarkerTag, installerArgs, extraEnv, bundleWine), `programs.bonsai.nvidiaLibs` (enable, version, sha256, mirror), `programs.bonsai.cudaRuntime` (enable, version, mirror, components, package) and `programs.bonsai.python` (enable, version, sha256, mirror, installerArgs, packages). Each module adds `programs.bonsai.installWine`, which installs the Wine package as a separate entry when `bonsai.bundleWine` is false. Version and hash options default from the release set of `programs.bonsai.bonsai.version`.

## Quick start

Install into your profile:

```sh
nix profile install github:ncguilbeault/bonsai-nix
bonsai
```

On a prefix that is not set up, `bonsai` runs `bonsai-setup` and exits without starting Bonsai, since the Bonsai installer offers to launch it when it finishes; on a prefix that is set up, `bonsai` starts Bonsai. The setup boots a Wine prefix at `~/.local/share/wineprefixes/wine-bonsai`, applies winetricks (`dotnet48 allfonts gdiplus`), and runs the Bonsai setup installer. Per-step markers in the prefix (`.bonsai-booted`, `.bonsai-winetricks-<tag>`, `.bonsai-installed-<version>`) make the setup idempotent. If something fails during the first installation, delete the wine prefix and try running the setup again.

`WINEPREFIX` overrides the prefix location for `bonsai`, `bonsai-setup` and `bonsai-wine`.

`bonsai-wine <command> [args...]` runs a command in the environment the launcher uses: the same prefix and `WINEARCH`, with the release's Wine tools first on `PATH`. Use it to run `winecfg`, `regedit`, `winetricks`, etc. against the Bonsai prefix:

```sh
bonsai-wine winecfg
bonsai-wine winetricks corefonts
bonsai-wine wine reg query 'HKCU\Software\Wine\X11 Driver'
```

`packages.wine` is the same Wine build on its own. It has no default prefix, so its commands act on Wine's default prefix (`~/.wine`) unless `WINEPREFIX` is set:

```sh
nix run github:ncguilbeault/bonsai-nix#wine -- winecfg
```

## Wine workarounds

`bonsai-setup` sets `UseEGL=N` under `HKCU\Software\Wine\X11 Driver` in the prefix. Wine >= 10.17 implements WGL through EGL in the X11 driver by default, and on the NVIDIA proprietary driver the EGL path exposes no pixel formats that OpenTK accepts, so Bonsai.Shaders window creation fails with `The requested GraphicsMode is not supported` ([opentk/opentk#523](https://github.com/opentk/opentk/issues/523)). Forcing the deprecated GLX backend restores a working format list. This is a temporary workaround; drop it once Wine's EGL path works on the NVIDIA driver. The value is set on every run of `bonsai-setup`, and can be set by hand:

```sh
bonsai-wine wine reg add 'HKCU\Software\Wine\X11 Driver' /v UseEGL /t REG_SZ /d N /f
```

## Releases

`nix/releases.nix` lists release sets: each Bonsai version together with every dependency it is released against.

- `bonsai.sha256` — the Bonsai installer hash;
- `wine` — the Wine version, its source hash, the wine-staging hash and the patches;
- `nvidiaLibs` — the nvidia-libs release version and hash;
- `nvcuda` — optional: the nvcuda revision, its hash and the patches for a source build. A release set without it uses the `nvcuda.dll` bundled with nvidia-libs;
- `cudaRedist` — a version label and the CUDA runtime and cuDNN archives (name, path and hash of each);
- `python` — the python.org Windows Python version and installer hash.

Each dependency pin is bound once in the `let` block at the top of the file (`wine_11_22`, `nvidiaLibs_1_0_5`, `nvcuda_772b344`, ...) and referenced by name from the release sets that use it (`wine = wine_11_22;`).

### Package names

The Bonsai packages (`bonsai`, `bonsai-python`, `bonsai-cuda`, `bonsai-cuda-python`) are keyed by Bonsai version: the unversioned name builds the highest version listed, and `<name>_<bonsai version>` (dots replaced by underscores) builds one release set.

Every dependency package is keyed by its own version: `wine_<version>`, `nvidia-libs_<version>`, `cuda-redist_<version label>`, `python-installer_<version>` and `nvcuda_<first seven characters of the revision>`, with dots and hyphens replaced by underscores. An nvidia-libs package that carries a source-built nvcuda is named `nvidia-libs_<version>_nvcuda_<revision>`. The unversioned names (`wine`, `nvidia-libs`, `cuda-redist`, `python-installer`, and `nvcuda` when the highest release set pins it) build the pins of the highest release set.

Each pin is built once and shared by the release sets that use it:

| Release | Wine | nvidia-libs | nvcuda | CUDA runtime | Python |
| --- | --- | --- | --- | --- | --- |
| 2.9.0 | `wine_11_8` | `nvidia-libs_1_0_2_nvcuda_772b344` | `nvcuda_772b344` | `cuda-redist_12_8_cudnn9_25_0` | `python-installer_3_12_10` |
| 2.9.1 | `wine_11_12` | `nvidia-libs_1_0_2_nvcuda_772b344` | `nvcuda_772b344` | `cuda-redist_12_8_cudnn9_25_0` | `python-installer_3_12_10` |
| 2.9.2 | `wine_11_22` | `nvidia-libs_1_0_2_nvcuda_772b344` | `nvcuda_772b344` | `cuda-redist_12_8_cudnn9_25_0` | `python-installer_3_12_10` |
| 2.9.3 | `wine_11_22` | `nvidia-libs_1_0_5` | bundled with nvidia-libs | `cuda-redist_13_5_cudnn9_28_1` | `python-installer_3_12_10` |

Since a package name stands for one pin, the flake's packages fail to evaluate with an error when two release sets carry different pins for the same version of a dependency (or the same nvcuda revision).

Each distinct Wine version is a separate source build. nvcuda is built once per pinned revision, with the oldest Wine among the release sets that pin that revision, so those release sets share one nvcuda build and one nvidia-libs package.

### Pinned releases

A pinned Bonsai package differs from the unversioned one in two ways, so that it installs next to it and next to other pinned releases:

- its commands are named `bonsai-<version>`, `bonsai-setup-<version>` and `bonsai-wine-<version>`;
- it defaults to a prefix of its own, `wine-bonsai-<version>` (`WINEPREFIX` still overrides it).

```sh
nix profile install github:ncguilbeault/bonsai-nix#bonsai github:ncguilbeault/bonsai-nix#bonsai_2_9_1
bonsai                      # latest release, in wine-bonsai
bonsai-2.9.1                # Bonsai 2.9.1 on its release's Wine, in wine-bonsai-2.9.1
bonsai-wine-2.9.1 winecfg   # winecfg of that release's Wine, on wine-bonsai-2.9.1
```

A versioned Wine package suffixes every command with its version (`wine-11.22`, `winecfg-11.22`, `winetricks-11.22`, ...), so several Wine versions install side by side with each other and with the unversioned `wine` package. Like `wine`, they set no `WINEPREFIX`:

```sh
nix profile install github:ncguilbeault/bonsai-nix#wine_11_12 github:ncguilbeault/bonsai-nix#wine_11_22
WINEPREFIX=~/prefixes/test winecfg-11.12
```

### Releases in the modules

`programs.bonsai.bonsai.version` selects the release set and defaults to the highest version listed. The Bonsai installer hash, `wine.version`, `wine.sha256`, `wine.stagingSha256`, `wine.patches`, `nvidiaLibs.version`, `nvidiaLibs.sha256`, `cudaRuntime.version`, `cudaRuntime.components`, `python.version` and `python.sha256` all default from that release set, so setting the Bonsai version alone selects a complete release:

```nix
programs.bonsai.bonsai.version = "2.9.1";
```

Setting any of those options overrides that dependency alone and leaves the rest on the release set. A version is overridden together with its hash:

```nix
programs.bonsai.python = {
  enable = true;
  version = "3.13.5";
  sha256 = "sha256-...";
};
```

Setting `wine.version` requires `wine.sha256` and `wine.stagingSha256` for that version; `wine.stagingSha256 = null` builds Wine without the wine-staging patches. A Bonsai version that is not listed in `nix/releases.nix` requires `bonsai.sha256` and takes its other dependencies from the latest release set.

A module install differs from the flake packages in four ways:

- the commands are always named `bonsai`, `bonsai-setup` and `bonsai-wine`, whichever version is selected;
- the prefix is `programs.bonsai.winePrefixes`/`programs.bonsai.prefixName`, by default `~/.local/share/wineprefixes/bonsai` (the flake packages use `wine-bonsai`);
- the Wine tools are on `PATH` under their plain names (`wine`, `winecfg`, `winetricks`, ...) and default to the same prefix as `bonsai`: with `bonsai.bundleWine` (the default) they are part of the Bonsai package, otherwise `installWine` (the default) installs the Wine package as a separate entry;
- the `nvcuda` pin of the release set is not used: nvidia-libs is installed with the `nvcuda.dll` it bundles.

The nvidia-libs environment (`WINEDLLPATH`, `LD_LIBRARY_PATH`) and `bonsai.extraEnv` are exported by `bonsai`, `bonsai-setup` and `bonsai-wine`, not by the Wine commands. With `nvidiaLibs.enable`, a bare `wine` therefore runs without that environment; use `bonsai-wine wine ...` for anything that needs the NVIDIA libraries.

## CUDA support (nvidia-libs)

The `-cuda` package variants (and the `programs.bonsai.nvidiaLibs.enable` module option) bundle the prebuilt [nvidia-libs](https://github.com/SveSop/nvidia-libs) release, which provides `nvcuda`, `nvml`, `nvcuvid`/`nvencodeapi`, `nvoptix` and `nvapi` for Wine.

```sh
nix profile install github:ncguilbeault/bonsai-nix#bonsai-cuda
# or via the modules:
# programs.bonsai.nvidiaLibs.enable = true;
# programs.bonsai.cudaRuntime.enable = true;
```

`bonsai-setup` installs the libraries into the prefix the same way upstream's `setup_nvlibs.sh` does: a `native` DLL override plus a symlink into `system32`/`syswow64` for each DLL, followed by a prefix update so Wine picks up NVML from `WINEDLLPATH`. The symlinks point into the Nix store, and a version-tagged marker (`.bonsai-nvlibs-<version>`) re-runs the step (re-pointing the symlinks) when the nvidia-libs version changes. At run time `bonsai`, `bonsai-setup` and `bonsai-wine` export `WINEDLLPATH` (for NVML) and, where `/run/opengl-driver/lib` exists (NixOS), prepend it to `LD_LIBRARY_PATH` so the Wine-side libraries can `dlopen` the host driver's `libcuda.so.1`, `libnvcuvid.so.1` and `libnvidia-encode.so.1`. The Wine packages carry no NVIDIA environment, so a Wine command that needs these libraries is run through `bonsai-wine`.

In the flake packages, a release set that pins `nvcuda` replaces the bundle's prebuilt `nvcuda.dll` with one built from source, which allows patches to be applied to it. `patches/0002-nvcuda-relay-cuLaunchHostFunc-through-callback-worker.patch` is such a patch: without it, applications that use CUDA host functions, such as ONNX Runtime, crash. Releases 2.9.0 to 2.9.2 pin the same nvcuda revision with this patch and share one build of it, compiled with Wine 11.8, the oldest Wine among them; 2.9.3 uses the `nvcuda.dll` bundled with nvidia-libs.

nvidia-libs only covers the driver-level libraries. Applications built on the CUDA *toolkit* — for example ONNX Runtime's CUDA execution provider — additionally expect the toolkit runtime DLLs (`cudart64_*`, `cublas64_*`, `cublasLt64_*`, `cufft64_*`, `curand64_*`, `nvrtc64_*`, `cudnn64_9` and its `cudnn_*` sublibraries), which on Windows every application must ship or install separately. The `bonsai-cuda` variant therefore also installs `packages.cuda-redist` into the prefix: the DLLs are collected from NVIDIA's official redistributable archives and symlinked into `system32` under a `.bonsai-cuda-redist-<version>` marker. No DLL overrides are needed for these since Wine has no builtins for them. In the modules this is `programs.bonsai.cudaRuntime.enable`, which is independent of `nvidiaLibs.enable` but only useful together with it.

The component versions and hashes are pinned per release set, and the CUDA major version differs between release sets: 2.9.0 to 2.9.2 carry CUDA 12.8 with cuDNN 9.25 (about 2.3 GiB installed), 2.9.3 carries CUDA 13.5 with cuDNN 9.28. The major version is part of the DLL names (`cudart64_12.dll`, `cudart64_13.dll`), so an application needs the release whose CUDA major version it was built against. In the modules the component set can be swapped via `programs.bonsai.cudaRuntime.components` together with `programs.bonsai.cudaRuntime.version`, or replaced by a prebuilt package via `programs.bonsai.cudaRuntime.package`.

Requirements: the proprietary NVIDIA driver on the host (branch 580+ recommended by upstream) and an x86_64 Linux host. The cuda variants are not exposed on aarch64-linux, since CUDA cannot function under FEX emulation (the emulated x86_64 Wine process cannot load the host's aarch64 driver libraries), nor on macOS, where the Linux driver libraries that nvidia-libs dlopens do not exist.

## Python in the prefix (Bonsai.Scripting.Python)

The `-python` package variants (and the `programs.bonsai.python.enable` module option) run the official python.org Windows installer inside the prefix during `bonsai-setup`, unattended (`/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=0` by default). This installs to `C:\Program Files\Python<XY>` and prepends it to the system `PATH` in the prefix registry, which is how `Bonsai.Scripting.Python` finds the runtime when `PythonHome` is left empty: it searches `PATH` for `python.exe` and derives the DLL name (`python312.dll` for Python 3.12) from the install directory's leaf name. Keep `InstallAllUsers=1` and `PrependPath=1` if you change `installerArgs`.

The Python version is pinned per release set in `nix/releases.nix`; every release set listed pins 3.12.10. It has to be a release with a Windows amd64 installer on python.org (late patch releases of a series have none) and one that the pythonnet version used by `Bonsai.Scripting.Python` supports (pythonnet 3.0.5 supports Python 3.7 through 3.13).

```sh
nix profile install github:ncguilbeault/bonsai-nix#bonsai-python
# or via the modules:
# programs.bonsai.python.enable = true;
# programs.bonsai.python.packages = [ "numpy" ];
```

The step runs under a `.bonsai-python-<version>` marker, so a different Python version (from another release set, or from `programs.bonsai.python.version` and `sha256`) installs next to the old one. `programs.bonsai.python.packages` is a list of pip requirement specifiers installed afterwards with the prefix's `python -m pip`; it runs under a marker keyed on the list, so editing the list re-runs pip. `installerArgs` and `packages` are module options; the flake packages use the default installer arguments and install no pip packages. The prefix's Python is also reachable from the shell through `bonsai-wine`:

```sh
bonsai-wine wine python -m pip install numpy
```

## macOS

The flake exposes `x86_64-darwin` and `aarch64-darwin` outputs for the non-cuda packages. Wine has no native arm64 macOS build, so on Apple Silicon the flake reuses the `x86_64-darwin` Wine build, whose binaries run transparently under Rosetta 2. Building (or substituting) that package on an Apple Silicon machine requires Rosetta to be installed (`softwareupdate --install-rosetta`) and `extra-platforms = x86_64-darwin` in `nix.conf`. Only the `full` wine variant is available on macOS; `waylandFull` is Linux-only, as are the NixOS module and the `-cuda` packages.

## Patching Wine

Wine patches for the flake packages are listed in the release set in `nix/releases.nix`, with the patch files in `patches/`.

In the modules, `programs.bonsai.wine.patches` defaults to the patches of the release set. Setting it replaces them, so include the release set's patches to keep them:

```nix
programs.bonsai.wine.patches =
  (import "${inputs.bonsai-nix}/nix/releases.nix")."2.9.3".wine.patches
  ++ [ ./patches/fix-my-bug.patch ];
```

The patches are appended to the patches nixpkgs applies to Wine; set `programs.bonsai.wine.replaceUpstreamPatches = true` to apply them in place of the nixpkgs patches.

## Home Manager (per-user install)

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your home configuration:
  imports = [ inputs.bonsai-nix.homeManagerModules.bonsai ];
  programs.bonsai = {
    enable = true;

    wine.variant = "waylandFull";

    bonsai = {
      # selects the release set; omit to track the latest release
      version = "2.9.1";
      winetricksVerbs = [ "dotnet48" "allfonts" "gdiplus" ];
    };
  };
}
```

## NixOS module (system-wide install)

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your system configuration:
  imports = [ inputs.bonsai-nix.nixosModules.bonsai ];
  programs.bonsai = {
    enable = true;

    nvidiaLibs.enable = true;
    cudaRuntime.enable = true;
    python.enable = true;
  };
}
```

This puts `bonsai`, `bonsai-setup`, `bonsai-wine` and the patched `wine`/`winecfg`/`regedit`/etc. on every user's `PATH`. The Wine prefix itself remains per-user (stateful, created under each user's `$HOME` by `bonsai-setup`), so each user gets their own prefix.

The HM and NixOS modules expose the same `programs.bonsai` interface — pick one based on whether you want a per-user or system-wide install. Don't import both into the same evaluation.

See `nix/common.nix` for the full option set and defaults.

## Layout

```
flake.nix             # inputs, packages (Bonsai per release, dependencies per pin), homeManagerModules, nixosModules
flake.lock            # pinned nixpkgs revision
patches/              # Wine and nvcuda patches referenced by the release sets
nix/
  releases.nix        # release sets: Bonsai version + the version and hash of every dependency
  wine.nix            # WineHQ tarball override + shell shim wrappers
  bonsai.nix          # installer fetch + bonsai-setup / bonsai / bonsai-wine scripts
  nvidia-libs.nix     # SveSop/nvidia-libs release bundle (CUDA support)
  nvcuda.nix          # SveSop/nvcuda built from source with patches
  cuda-redist.nix     # Windows CUDA/cuDNN runtime DLLs from NVIDIA redist archives
  python.nix          # python.org Windows installer fetch
  common.nix          # programs.bonsai options (defaults from releases.nix) + package construction
  hm-module.nix       # Home Manager wrapper (writes home.packages)
  nixos-module.nix    # NixOS wrapper (writes environment.systemPackages)
```

## Installing from Binary Cache

This procedure builds the `bonsai` package into a signed binary cache on a USB drive, from which another x86_64-linux machine installs it without building. The examples use `/dev/sda` for the drive and `/run/media/$USER/BONSAI-NIX` for its mount point.

### Step 1 — build

Build before touching the drive, so that a failed build does not leave it wiped. This is the slow step.

```shell
nix build github:ncguilbeault/bonsai-nix#bonsai --out-link ~/bonsai-cache
nix path-info -Sh ~/bonsai-cache
```

### Step 2 — signing key (once, reuse for every drive)

Keep the secret key off the drives. Regenerating it invalidates drives made with the old key.

```shell
mkdir -p ~/.keys
nix-store --generate-binary-cache-key bonsai-usb-1 ~/.keys/bonsai-usb.sec ~/.keys/bonsai-usb.pub
chmod 600 ~/.keys/bonsai-usb.sec
cat ~/.keys/bonsai-usb.pub
```

### Step 3 — find the drive, wipe it and repartition

List the drives visible on the system and identify the USB drive. Every later step uses its device path, and the wrong path destroys the data on another drive.

```shell
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,TRAN,RM,MODEL,SERIAL
```

Unmount the drive if it is mounted (no root needed):

```shell
udisksctl unmount -b /dev/sda1
```

Confirm the device once more, then wipe and partition it:

```shell
lsblk -o PATH,SIZE,TRAN,RM,MODEL,SERIAL /dev/sda   # CONFIRM CORRECT DRIVE

sudo wipefs -a /dev/sda
sudo sfdisk /dev/sda <<'EOF'
label: gpt
start=1MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="bonsai-cache"
EOF
sync && sudo udevadm settle
```

The Microsoft-basic-data type GUID is what makes the partition recognisable on Windows and macOS as well as Linux.

### Step 4 — format exFAT

Format using `mkfs.exfat`. The label is capped at 11 characters, hence BONSAI-NIX:

```shell
MKFS="$(nix build --no-link --print-out-paths 'nixpkgs#exfatprogs^out')/bin/mkfs.exfat"
sudo "$MKFS" -L BONSAI-NIX /dev/sda1
sync && sudo udevadm settle
```

### Step 5 — mount and copy the closure

```shell
udisksctl mount -b /dev/sda1

nix copy \
  --to "file:///run/media/$USER/BONSAI-NIX/bonsai-cache?compression=zstd&secret-key=$HOME/.keys/bonsai-usb.sec" \
  github:ncguilbeault/bonsai-nix#bonsai
```

### Step 6 — ship the public key and instructions alongside it

```shell
cp ~/.keys/bonsai-usb.pub "/run/media/$USER/BONSAI-NIX/"

cat > "/run/media/$USER/BONSAI-NIX/README.md" <<EOF
# Bonsai binary cache (x86_64-linux)

Prebuilt closure for \`github:ncguilbeault/bonsai-nix#bonsai\`, for x86_64-linux only.

Public key: $(cat ~/.keys/bonsai-usb.pub)

## Install

Run from the root of this drive, as root or as a user listed in Nix's \`trusted-users\`. A non-trusted user's \`--extra-substituters\` is ignored silently and the package is rebuilt from source.

    nix profile install github:ncguilbeault/bonsai-nix#bonsai \\
      --extra-substituters "file://\$(pwd)/bonsai-cache" \\
      --extra-trusted-public-keys "$(cat ~/.keys/bonsai-usb.pub)"
EOF
```

### Step 7 — flush and eject

exFAT writes are heavily buffered; skipping the sync risks a truncated cache. This step can take some time.

```shell
sync
udisksctl unmount -b /dev/sda1
udisksctl power-off -b /dev/sda
```
