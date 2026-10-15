# x.ai-grok-bot

Nix-native packaging for the xAI Grok Bot desktop agent.

Upstream publishes Linux builds as a `.deb` (plus `.rpm` and AppImage). This repo unpacks the official `.deb` into the Nix store instead of using apt:

- Reproducible package (`pkgs/grok-bot.nix`) pinned by version, commit, and hash
- Flake outputs for package, app, and dev shell
- NixOS module (`nixos.nix`)
- Home Manager module (`home.nix`)
- Non-flake compatibility (`default.nix`, `shell.nix`)

The package keeps upstream's bundled Electron. Native modules in the `.deb` are built against that runtime.

## Pinned upstream version

The source of truth is `pkgs/grok-bot.nix`: `version`, `commit`, and the `x86_64-linux` / `aarch64-linux` artifact URLs and hashes.

Versions come from the stable download manifest:

- `https://api2.cursor.sh/updates/api/download/stable/linux-x64/sand`
- `https://api2.cursor.sh/updates/api/download/stable/linux-arm64/sand`

Each manifest has `version`, `commitSha`, and `debUrl`.

## Quick start (flake)

Run Grok Bot:

`nix run github:timoteuszelle/x.ai-grok-bot`

Install to your profile:

`nix profile install github:timoteuszelle/x.ai-grok-bot`

## NixOS module usage

In your flake inputs:

```nix
xai-grok-bot = {
  url = "github:timoteuszelle/x.ai-grok-bot";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

In your NixOS modules list:

`xai-grok-bot.nixosModules.default`

Then enable:

`programs.grok-bot.enable = true;`

The overlay does not set `allowUnfree`. The NixOS configuration has to allow unfree packages, because the upstream binary is unfree. This flake's own `nix build` and `nix run` outputs allow it so those commands work on their own.

## Home Manager usage

Add the same flake input, then:

`xai-grok-bot.homeManagerModules.default`

`programs.grok-bot.enable = true;`

## What the package changes compared with the .deb

- `chrome-sandbox` is omitted. It only works as setuid root, which the Nix store cannot represent. NixOS kernels allow user namespaces, so the Chromium sandbox still runs.
- The bundled Vulkan loader is replaced with `vulkan-loader` from nixpkgs so ICD discovery works.
- The desktop file launches the Nix wrapper. `grokbot://` and `sand://` stay registered. `sand` on `PATH` is a compatibility alias for the older executable name.
- On Wayland, when `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are set, the wrapper passes `--ozone-platform-hint=auto`.
- The `.deb` postinst also registers an apt source and an AppArmor profile. Those are Debian/Ubuntu mechanisms and are not installed.

## Updating to a new Grok Bot version

1. Read `debUrl`, `version`, and `commitSha` from both manifest URLs above.
2. Prefetch hashes:
   - `nix store prefetch-file --json <x64 debUrl>`
   - `nix store prefetch-file --json <arm64 debUrl>`
3. Replace `version`, `commit`, and both artifact entries in `pkgs/grok-bot.nix`.
4. Validate:
   - `nix flake show`
   - `nix build .#grok-bot`

GitHub Actions does this on a schedule. See below.

## Automation (GitHub Actions)

- `.github/workflows/update-grok-bot.yml`
  - Triggers: scheduled (`17 4,16 * * *`, twice a day) and manual (`workflow_dispatch`)
  - Reads both Linux download manifests
  - When the pinned `.deb` URLs differ, updates `pkgs/grok-bot.nix` (version, commit, URLs, hashes)
  - Builds `.#grok-bot`
  - Opens a pull request labeled `automerge`

- `.github/workflows/release-from-pin.yml`
  - Triggers: push to `main` when `pkgs/grok-bot.nix` changes, and manual dispatch
  - Also dispatched after a bot merge. A merge made with `GITHUB_TOKEN` does not start `push` workflows
  - Tags `v<version>` and creates a GitHub Release for that pin

- `.github/workflows/automerge-grok-bot-bumps.yml`
  - Runs after a successful Update Grok Bot workflow, and on manual dispatch
  - Merges bot-authored bump PRs (title and branch match, `automerge` label, open, non-draft, same repository)
  - Dispatches the release workflow for the merge commit

The repository setting "Allow GitHub Actions to create and approve pull requests" must stay enabled. Without it, the update workflow can push the bump branch and still fail while opening the pull request.

Manual dispatch:

- `gh workflow run update-grok-bot.yml --repo timoteuszelle/x.ai-grok-bot`
- `gh workflow run automerge-grok-bot-bumps.yml --repo timoteuszelle/x.ai-grok-bot`
- `gh workflow run release-from-pin.yml --repo timoteuszelle/x.ai-grok-bot`

Pushing workflow-file changes over HTTPS needs a token with the `workflow` scope.

## License

Repository code: see `LICENSE`.
Upstream Grok Bot binary: licensed by xAI.
