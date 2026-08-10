# Bonsai - Nix Flake

A Nix flake that installs [Bonsai-rx](https://bonsai-rx.org/) on Linux via a patched Wine build.

## What it provides

- `packages.bonsai` — the `bonsai` launcher and `bonsai-setup` helper (auto-initializes the Wine prefix and installs Bonsai on first run). Symlink-joined with `packages.wine` by default.
- `packages.wine` — a patched WineHQ build (default: 11.0, `wow-full`) exposed via shell shims that default `WINEPREFIX` and propagate `extraEnv`, with a `winetricks` shim and matching shims for `wine`, `wine64`, `wineboot`, `wineserver`, `winecfg`, `regedit`, `wineconsole`, `msiexec`, `winefile`, `notepad`, `uninstaller`, `winedbg`.
- `packages.bonsai-cuda` / `packages.wine-cuda` — the same launcher and Wine build with [nvidia-libs](https://github.com/SveSop/nvidia-libs) (CUDA, NVML, NVENC/NVDEC, OptiX, NvAPI) and the Windows CUDA toolkit runtime DLLs bootstrapped into the Wine prefix on first run.
- `packages.nvidia-libs` — the unpacked nvidia-libs release bundle (useful on its own for other prefixes).
- `packages.cuda-redist` — the Windows CUDA runtime and cuDNN DLLs collected from NVIDIA's official redistributable archives.
- `homeManagerModules.bonsai` — a Home Manager module exposing `programs.bonsai`. Adds the resolved package to `home.packages`.
- `nixosModules.bonsai` — a NixOS module exposing the same `programs.bonsai` interface. Adds the resolved package to `environment.systemPackages` for a system-wide install.

Both modules share a common backbone (`nix/common.nix`) that declares submodule options under `programs.bonsai.wine` (version, sha256, variant, mirror, patches, replaceUpstreamPatches, withWinetricks, extraEnv, winePrefixes, prefixName), `programs.bonsai.bonsai` (version, sha256, mirror, prefixName, wineArch, winetricksVerbs, winetricksArgs, winetricksMarkerTag, installerArgs, extraEnv, bundleWine, winePrefixes) `programs.bonsai.nvidiaLibs` (enable, version, sha256, mirror) and `programs.bonsai.cudaRuntime` (enable, package), plus an `installWine` toggle declared by each install-site wrapper.

## Quick start

Install into your profile:

```sh
nix profile install github:ncguilbeault/bonsai-nix
bonsai
```

The first invocation of `bonsai` runs the `bonsai-setup` script, which boots a Wine prefix at `~/.local/share/wineprefixes/wine-bonsai`, applies winetricks (`dotnet48 allfonts gdiplus` by default), and runs the Bonsai setup installer. Subsequent runs reuse the prefix and per-step markers (`.bonsai-booted`, `.bonsai-winetricks-<tag>`, `.bonsai-installed-<version>`) make the setup idempotent. If something fails during the first installation, delete the wine prefix and try running the setup again.

`packages.wine` is exposed separately so you can run `winecfg`, `regedit`, etc. against the same prefix:

```sh
nix run github:ncguilbeault/bonsai-nix#wine -- winecfg
# or, once installed, simply:
winecfg
```

## CUDA support (nvidia-libs)

The `-cuda` package variants (and the `programs.bonsai.nvidiaLibs.enable` module option) bundle the prebuilt [nvidia-libs](https://github.com/SveSop/nvidia-libs) release, which provides `nvcuda`, `nvml`, `nvcuvid`/`nvencodeapi`, `nvoptix` and `nvapi` for Wine.

```sh
nix profile install github:ncguilbeault/bonsai-nix#bonsai-cuda
# or via the modules:
# programs.bonsai.nvidiaLibs.enable = true;
```

On the first run, `bonsai-setup` installs the libraries into the prefix the same way upstream's `setup_nvlibs.sh` does: a `native` DLL override plus a symlink into `system32`/`syswow64` for each DLL, followed by a prefix update so Wine picks up NVML from `WINEDLLPATH`. The symlinks point into the Nix store, and a version-tagged marker (`.bonsai-nvlibs-<version>`) re-runs the step (re-pointing the symlinks) when the nvidia-libs version changes. The wine shims additionally export `WINEDLLPATH` (for NVML) and, on NixOS, prepend `/run/opengl-driver/lib` to `LD_LIBRARY_PATH` so the Wine-side libraries can `dlopen` the host driver's `libcuda.so.1`, `libnvcuvid.so.1` and `libnvidia-encode.so.1`.

nvidia-libs only covers the driver-level libraries. Applications built on the CUDA *toolkit* — for example ONNX Runtime's CUDA execution provider — additionally expect the toolkit runtime DLLs (`cudart64_*`, `cublas64_*`, `cublasLt64_*`, `cufft64_*`, `curand64_*`, `nvrtc64_*`, `cudnn64_9` and its `cudnn_*` sublibraries), which on Windows every application must ship or install separately. The `bonsai-cuda` variant therefore also installs `packages.cuda-redist` into the prefix: the DLLs are collected from NVIDIA's official redistributable archives (component versions and hashes pinned in `nix/cuda-redist.nix`, defaulting to CUDA 12.x + cuDNN 9, ~2.6 GB installed) and symlinked into `system32` under a `.bonsai-cuda-redist-<version>` marker. No DLL overrides are needed for these since Wine has no builtins for them. In the modules this is `programs.bonsai.cudaRuntime.enable`; the component set can be swapped via `programs.bonsai.cudaRuntime.package` (e.g. for a CUDA 13 ONNX Runtime build).

Requirements: the proprietary NVIDIA driver on the host (branch 580+ recommended by upstream) and an x86_64 host. The cuda variants are not exposed on aarch64, since CUDA cannot function under FEX emulation (the emulated x86_64 Wine process cannot load the host's aarch64 driver libraries).

## Patching Wine

Drop one or more `.patch` files into `patches/` (or anywhere reachable) and pass them via the module option. Patches are appended to the upstream Wine patch list by default; set `replaceUpstreamPatches = true` to fully replace them.

```nix
programs.bonsai.wine.patches = [ ./patches/fix-my-bug.patch ];
```

## Home Manager (per-user install)

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your home configuration:
  imports = [ inputs.bonsai-nix.homeManagerModules.bonsai ];
  programs.bonsai = {
    enable = true;

    wine = {
      variant = "wow-full";
      patches = [ ./patches/fix-my-bug.patch ];
    };

    bonsai = {
      version = "2.9.0";
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

    wine.patches = [ ./patches/fix-my-bug.patch ];
    bonsai.winetricksVerbs = [ "dotnet48" "allfonts" "gdiplus" ];
  };
}
```

This puts `bonsai`, `bonsai-setup`, and the patched `wine`/`winecfg`/`regedit`/etc. on every user's `PATH`. The Wine prefix itself remains per-user (stateful, created under each user's `$HOME` on first run), so each user gets their own prefix initialized by `bonsai-setup`.

The HM and NixOS modules expose the same `programs.bonsai` interface — pick one based on whether you want a per-user or system-wide install. Don't import both into the same evaluation.

See `nix/common.nix` for the full option set and defaults.

## Layout

```
flake.nix             # inputs, packages, homeManagerModules, nixosModules
patches/              # drop wine .patch files here
nix/
  wine.nix            # WineHQ tarball override + shell shim wrappers
  bonsai.nix          # installer fetch + bonsai-setup / bonsai scripts
  nvidia-libs.nix     # SveSop/nvidia-libs release bundle (CUDA support)
  cuda-redist.nix     # Windows CUDA/cuDNN runtime DLLs from NVIDIA redist archives
  common.nix          # programs.bonsai options + package construction
  hm-module.nix       # Home Manager wrapper (writes home.packages)
  nixos-module.nix    # NixOS wrapper (writes environment.systemPackages)
```
