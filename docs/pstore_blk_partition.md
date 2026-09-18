# pstore_blk dynamic partition — build-system patches

A51 6.12 rebase, 2026-05-29.

## What

A new dynamic partition `pstore_blk` (8 MB, raw, no filesystem) carved out
of the `super` partition. Used by the kernel's `pstore_blk` backend
(`CONFIG_PSTORE_BLK=y`) to persist kmsg dumps across cold reset, so we can
recover logs when the in-kernel shutdown intercept in `a51_bouncer.c`
misses the trigger (e.g. PMIC autonomous shutdown, modem-induced
power-off, anything that bypasses `reboot_notifier_list`).

Cmdline (set in DTS bootargs):

```
pstore_blk.blkdev=/dev/block/by-name/pstore_blk
pstore_blk.kmsg_size=1024 pstore_blk.console_size=512 pstore_blk.max_reason=4
```

Records are read back as `/sys/fs/pstore/dmesg-pstore_blk-N` after the
next boot.

## Why this needs build-system patches

AOSP's Soong has a **hardcoded allowlist** of partition names that may
appear inside super:

  `system`, `system_ext`, `product`, `vendor`, `odm`,
  `system_dlkm`, `vendor_dlkm`, `odm_dlkm`

This is not a runtime/correctness restriction — `lpmake` (which actually
builds `super.img`) accepts any name, and the block device shows up as
`/dev/block/by-name/<name>` just fine. The constraint comes from Soong's
super-image module having **typed Go struct fields** for each known
partition. Adding a name not in the allowlist hits the `default:` arm of
the dispatch switch and Soong errors out at analysis time:

> `partition "pstore_blk" is not a super image supported partition`

To add a custom partition, two small Soong-side additions are needed.

## Patched files

1. **`build/soong/filesystem/super_image.go`**
   - Added field `Pstore_blk_partition *string` to
     `SuperImagePartitionNameProperties`.
   - Added `addDependencyIfDefined(s.partitionProps.Pstore_blk_partition)`
     in `super_image_deps`.
   - Added `case "pstore_blk":` branches in **both** switches —
     `handleSubPartition` (the main dispatch) and `filterMissingPartitions`
     (the optional-partition filter).

2. **`build/soong/fsgen/filesystem_creator.go`**
   - Added `case "pstore_blk":` in the filesystem-image dispatch switch
     so fsgen knows to emit `pstore_blk.img` (no Security_patch, no
     symlinks — just a raw image stem). Does NOT need an entry in
     `createPrebuiltKernelModules` (that's only for `*_dlkm` partitions).

3. **`device/samsung/universal9611-common/fsconfig_dynamic.mk`**
   - Added `pstore_blk` to `BOARD_SAMSUNG_DYNAMIC_PARTITIONS_PARTITION_LIST`.
   - Added `BOARD_PSTORE_BLKIMAGE_PARTITION_SIZE := 8388608`.
   - Added `BOARD_PSTORE_BLKIMAGE_FILE_SYSTEM_TYPE := raw`.

4. **`kernel/samsung/universal9611-next/arch/arm64/boot/dts/exynos/exynos9610.dts`**
   - Added `pstore_blk.blkdev=...` family of cmdline args to `bootargs`.

5. **`kernel/samsung/universal9611-next/arch/arm64/configs/exynos9611-a51.config`**
   - Enabled `CONFIG_PSTORE_BLK=y`.

## Maintenance — re-applying the soong patches on rebase

`build/soong/filesystem/super_image.go` and
`build/soong/fsgen/filesystem_creator.go` are upstream AOSP files. When
rebasing onto a newer AOSP, the local patches must be re-applied.
Mechanical conflicts only — the additions are isolated lines in well-defined
locations. Search for `pstore_blk` to locate them.

If the upstream allowlist changes shape (e.g. moves to a slice of
`partitionName` consts, or adopts reflection), the equivalent change needs
adapting. Reference: this directory's `pstore_blk_partition.md` (this file).

## Why not just hijack `odm_dlkm`?

It would build without any soong patch — A51 doesn't ship `odm_dlkm`
content. But it's semantically wrong (an "ODM dynamic kernel modules"
partition holding kmsg dumps), would confuse anyone debugging the
device, and could conflict if odm_dlkm is later actually used.

## Why not a separate top-level GPT partition?

Samsung BL uses a PIT (Partition Information Table) file flashed via
Odin. Modifying it is high-risk (brick if wrong). A dynamic sub-partition
inside `super` only changes the super-internal layout, which `update-super`
fastboot/sideload handles cleanly on every install.

## Flashing

Boot.img-only reflash is NOT sufficient when this partition is being
*added or resized* — super metadata changes. Full LineageOS install
(via `mka bacon` → OTA zip → sideload-auto-reboot, OR fastboot `flashall`)
is required at least once.

Subsequent boot.img changes that don't touch the partition layout can
still go via plain `dd` to `/dev/block/by-name/boot` in recovery.

## Factory reset

`pstore_blk` is a dynamic sub-partition of `super`. The factory-reset
path wipes `/cache`, `/userdata`, `/metadata` only — **not super
sub-partitions**. So pstore content persists across factory reset, until
the next OS flash overwrites it.
