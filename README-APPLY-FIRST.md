# BBRv3 Plus Extreme Slim — Fast Recovery consolidated code candidate

Parent tested branch: `dateblue/Actions-bbr-v3`, `bbrv3-extreme`, commit `a49a6b7`.

This is an **overlay**, NOT a full kernel source archive. Merge it into an
existing checkout of the branch; the existing `apply-bbrv3-max-profile.sh`,
`apply-bbrv3-extreme-profile.sh`, `kernel-source.sh`, patchset, Oracle A1 Slim
script, and kernel config are intentionally not overwritten.

## Apply on Windows PowerShell

```powershell
Set-Location D:\dev\Actions-bbr-v3
git switch bbrv3-extreme
git status -sb  # require a clean tree
Expand-Archive -LiteralPath 'D:\dev\BBRv3Plus-FastRecovery-Slim-RC.zip' -DestinationPath . -Force
git diff --check
git status --short
git diff --stat
# Review the diff, then stage:
git add .gitattributes .github/workflows/build-extreme.yml scripts/create-bbrv3plus.sh scripts/apply-bbrv3-fast-recovery.py scripts/verify-brutal-module.sh scripts/tests/ docs/FAST-RECOVERY-RELEASE-NOTES.md README-APPLY-FIRST.md
git diff --cached --check
# After review:
git commit -m 'Add guarded BBRv3 Plus Fast Recovery and preflight-first ARM64 release flow'
git push origin bbrv3-extreme
```

**PUSH NOW RUNS ONLY FAST CHECKS, NOT THE 60-MINUTE FULL BUILD.**
The workflow runs an ARM64 object-compile preflight for both BBR objects and
the three official pinned Brutal objects. It catches the previous late-stage
M= path failure before any complete kernel DEB compile.

When the push/preflight is green, trigger the Actions workflow manually,
set `kernel_version=7.3.1`, `build_mode=release` **only once**. Kernel DEBs are
uploaded immediately after the full kernel build, even if subsequent Brutal
module ABI validation fails. Do NOT push and then independently rerun a full
build while the preflight is red.

Read docs/FAST-RECOVERY-RELEASE-NOTES.md for design limits and validation.

## Safety

The full ARM64 kernel and target Brutal `.ko` were NOT compiled in this offline
workspace. Do not install this RC on KR/SG before the fast CI check, full kernel
build and Oracle A1 startup tests are green. Preserve GRUB old-kernel fallback.
