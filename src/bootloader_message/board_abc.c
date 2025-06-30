/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Board specific A/B control
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>

#include "abc.h"
#include "log.h"

#ifndef __may_unused
#define __may_unused   __attribute__((__unused__))
#endif

/*
 * Safety ABC register layout:
 * Bit 31-3  Reserved
 * Bit 3-2   Safety booting times, 0/1 normal booting, 2/3 enter download mode
 * Bit 1     Safety booting status, 0 for normal, 1 for safety abort
 * Bit 0     Safety AB slot, 0 for slot A, 1 for slot B
 *
 */

#define ABC_SLOT_SHIFT          0
#define ABC_SLOT_MASK           (0x1 << ABC_SLOT_SHIFT)

#define ABC_STATUS_SHIFT        1
#define ABC_STATUS_MASK         (0x1 << ABC_STATUS_SHIFT)

#define ABC_TIMES_SHIFT         2
#define ABC_TIMES_MASK          (0x3 << ABC_TIMES_SHIFT)

// Path to the driver in sysfs
#define DRIVER_PATH "/sys/bus/platform/drivers/abc-syscon/"

static int get_abc_syscon_value_path(char *path_buf, size_t buf_size)
{
	DIR *dir;
	struct dirent *entry;
	char value_path[PATH_MAX] = {0};

	dir = opendir(DRIVER_PATH);
	if (!dir) {
		log_debug("opendir %s: %s", DRIVER_PATH, strerror(errno));
		return -errno;
	}

	// Find the first device with a 'value' file.
	while ((entry = readdir(dir)) != NULL) {
		if (entry->d_type == DT_LNK) {
			snprintf(value_path, sizeof(value_path), "%s%s/value",
						DRIVER_PATH, entry->d_name);

			if (access(value_path, F_OK) == 0) {
				break;
			}
			value_path[0] = '\0';
		}
	}

	closedir(dir);

	if (value_path[0] == '\0') {
		log_debug("'value' file not found in %s", DRIVER_PATH);
		return -ENOENT;
	}

	if (strlen(value_path) >= buf_size) {
		log_error("abc-syscon: path buffer too small");
		return -ERANGE;
	}
	strcpy(path_buf, value_path);

	return 0;
}

/**
 * abc_syscon_value_exists - Check if the syscon value file exists.
 *
 * Returns 1 if it exists, 0 if not, or a negative error code on other errors.
 */
static int abc_syscon_value_exists(void)
{
	DIR *dir;
	struct dirent *entry;
	char value_path[PATH_MAX];
	int found = 0;

	dir = opendir(DRIVER_PATH);
	if (!dir) {
		log_debug("opendir %s: %s", DRIVER_PATH, strerror(errno));
		return -errno;
	}

	while ((entry = readdir(dir)) != NULL) {
		if (entry->d_type == DT_LNK) {
			snprintf(value_path, sizeof(value_path), "%s%s/value",
						DRIVER_PATH, entry->d_name);
			if (access(value_path, F_OK) == 0) {
				found = 1;
				break;
			}
		}
	}

	closedir(dir);
	return found;
}

/**
 * abc_syscon_read_value - Read from the syscon value file.
 * @buf:  Buffer to store the value.
 * @size: Size of the buffer.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static int abc_syscon_read_value(char *buf, size_t size)
{
	char path[PATH_MAX];
	int ret;
	FILE *fp;

	ret = get_abc_syscon_value_path(path, sizeof(path));
	if (ret < 0)
		return ret;

	fp = fopen(path, "r");
	if (!fp) {
		log_error("fopen for read %s: %s", path, strerror(errno));
		return -errno;
	}

	if (!fgets(buf, size, fp)) {
		if (ferror(fp)) {
			log_error("fgets from %s: %s", path, strerror(errno));
			fclose(fp);
			return -EIO;
		}
	}

	fclose(fp);

	// Remove trailing newline if present
	size_t len = strlen(buf);
	if (len > 0 && buf[len - 1] == '\n')
		buf[len - 1] = '\0';

	return 0;
}

/**
 * abc_syscon_write_value - Write to the syscon value file.
 * @value: The string value to write.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static int abc_syscon_write_value(const char *value)
{
	char path[PATH_MAX];
	int ret;
	FILE *fp;

	ret = get_abc_syscon_value_path(path, sizeof(path));
	if (ret < 0)
		return ret;

	fp = fopen(path, "w");
	if (!fp) {
		log_error("fopen for write %s: %s", path, strerror(errno));
		return -errno;
	}

	if (fputs(value, fp) == EOF) {
		log_error("fputs to %s: %s", path, strerror(errno));
		fclose(fp);
		return -EIO;
	}

	fclose(fp);
	return 0;
}

/**
 * abc_syscon_read_u32 - Read the syscon value as a u32 integer.
 * @value: Pointer to store the resulting u32 value.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static int abc_syscon_read_u32(uint32_t *value)
{
	char buf[32];
	int ret;
	char *endptr;
	unsigned long val;

	ret = abc_syscon_read_value(buf, sizeof(buf));
	if (ret < 0)
		return ret;

	if (buf[0] == '\0') {
		log_error("abc-syscon: value is empty");
		return -EINVAL;
	}

	errno = 0;
	val = strtoul(buf, &endptr, 0);
	if (errno != 0 || *endptr != '\0') {
		log_error("abc-syscon: invalid integer value '%s'", buf);
		return -EINVAL;
	}

	*value = (uint32_t)val;
	return 0;
}

/**
 * abc_syscon_write_u32 - Write a u32 integer to the syscon value file.
 * @value: The u32 value to write.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static int abc_syscon_write_u32(uint32_t value)
{
	char buf[16];

	snprintf(buf, sizeof(buf), "%u", value);
	return abc_syscon_write_value(buf);
}

/**
 * abc_get_slot - Get the current A/B slot.
 * @slot: Pointer to store the slot (0 for A, 1 for B).
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused int abc_get_slot(int *slot)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	*slot = (reg_val & ABC_SLOT_MASK) >> ABC_SLOT_SHIFT;
	return 0;
}

/**
 * abc_set_slot - Set the A/B slot.
 * @slot: The slot to set (0 for A, 1 for B).
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused int abc_set_slot(int slot)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	reg_val &= ~ABC_SLOT_MASK;
	reg_val |= ((uint32_t)slot << ABC_SLOT_SHIFT) & ABC_SLOT_MASK;

	return abc_syscon_write_u32(reg_val);
}

/**
 * abc_get_booting_status - Get the safety booting status.
 * @status: Pointer to store the status (0 for normal, 1 for abort).
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused
int abc_get_booting_status(int *status)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	*status = (reg_val & ABC_STATUS_MASK) >> ABC_STATUS_SHIFT;
	return 0;
}

/**
 * abc_set_booting_status - Set the safety booting status.
 * @status: The status to set (0 for normal, 1 for abort).
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused
int abc_set_booting_status(int status)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	reg_val &= ~ABC_STATUS_MASK;
	reg_val |= ((uint32_t)status << ABC_STATUS_SHIFT) & ABC_STATUS_MASK;

	return abc_syscon_write_u32(reg_val);
}

/**
 * abc_get_booting_times - Get the safety booting times.
 * @times: Pointer to store the booting times count.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused
int abc_get_booting_times(int *times)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	*times = (reg_val & ABC_TIMES_MASK) >> ABC_TIMES_SHIFT;
	return 0;
}

/**
 * abc_set_booting_times - Set the safety booting times.
 * @times: The booting times count to set.
 *
 * Returns 0 on success, or a negative error code on failure.
 */
static __may_unused
int abc_set_booting_times(int times)
{
	uint32_t reg_val;
	int ret;

	ret = abc_syscon_read_u32(&reg_val);
	if (ret < 0)
		return ret;

	reg_val &= ~ABC_TIMES_MASK;
	reg_val |= ((uint32_t)times << ABC_TIMES_SHIFT) & ABC_TIMES_MASK;

	return abc_syscon_write_u32(reg_val);
}

static int safety_abc_setup(int mark_type, int slot)
{
	uint32_t val;
	int ret;

	if (slot < 0 || slot >= NUM_SLOT) {
		log_error("Invalid slot: %d", slot);
		return -EINVAL;
	}

	ret = abc_syscon_read_u32(&val);
	if (ret < 0) {
		log_error("Could not read safety abc value");
		return ret;
	}

	switch (mark_type) {
	case AB_MARK_SUCCESSFUL:
		/* Set booting status to normal and reset times */
		val &= ~ABC_STATUS_MASK;
		val &= ~ABC_TIMES_MASK;
		break;
	case AB_MARK_UNBOOTABLE:
		/* Set booting status to abort for the given slot */
		val &= ~ABC_SLOT_MASK;
		val |= ((uint32_t)slot << ABC_SLOT_SHIFT) & ABC_SLOT_MASK;
		val |= ABC_STATUS_MASK;
		break;
	case AB_MARK_ACTIVE:
		/* Set the given slot to be active */
		val &= ~ABC_SLOT_MASK;
		val |= ((uint32_t)slot << ABC_SLOT_SHIFT) & ABC_SLOT_MASK;
		val &= ~ABC_STATUS_MASK;
		val &= ~ABC_TIMES_MASK;
		break;
	default:
		log_error("Unknown mark type: %d", mark_type);
		return -EINVAL;
	}

	return abc_syscon_write_u32(val);
}

int abc_board_setup(enum ab_slot_mark type, int slot)
{
	int ret;

	if (slot < 0 || slot > 1) {
		log_error("Wrong slot (slot = %d)", slot);
		return -EINVAL;
	}

	ret = safety_abc_setup(type, slot);
	if (ret < 0) {
		log_error("Unable to setup safety abc");
		return ret;
	}

	return 0;
}

bool abc_board_exists(void)
{
	int ret;

	ret = abc_syscon_value_exists();
	if (ret < 0) {
		log_debug("syscon 'value' file does not exist in %s", DRIVER_PATH);
		return false;
	}

	return ret > 0;
}