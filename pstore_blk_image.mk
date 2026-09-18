# 2026-05-29 diagnostic: build an empty 8 MB raw image for the
# pstore_blk dynamic sub-partition.  The AOSP build system normally
# doesn't generate images for raw partitions — it only allocates space
# in super and expects a per-partition image to be flashed.  For an
# empty partition we just emit a zero-filled file of the configured
# size so lpmake reserves the right amount and check_partition_sizes
# can read it cleanly.
#
# See device/samsung/universal9611-common/docs/pstore_blk_partition.md
# for the wider context.

PSTORE_BLK_IMAGE_TARGET := $(PRODUCT_OUT)/pstore_blk.img
INSTALLED_PSTORE_BLKIMAGE_TARGET := $(PSTORE_BLK_IMAGE_TARGET)

$(PSTORE_BLK_IMAGE_TARGET):
	@echo "Target pstore_blk image: $@ ($(BOARD_PSTORE_BLKIMAGE_PARTITION_SIZE) bytes)"
	@mkdir -p $(dir $@)
	@dd if=/dev/zero of=$@ bs=1 count=0 seek=$(BOARD_PSTORE_BLKIMAGE_PARTITION_SIZE) 2>/dev/null

ALL_DEFAULT_INSTALLED_MODULES += $(PSTORE_BLK_IMAGE_TARGET)
droidcore: $(PSTORE_BLK_IMAGE_TARGET)
