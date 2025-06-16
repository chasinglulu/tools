/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Manage A/B metadata tool
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <linux/fs.h>
#include <sys/stat.h>
#include <mtd/mtd-user.h>

#include "bootloader_message.h"
#include "log.h"
#include "abc.h"
#include "crc32.h"
#include "device_io.h"

#define SLOT_NAME(slot)          ('A' + (slot))
#define AB_MAX_PRIORITY          15
#define AB_MAX_TRIES_REMAINING   7

static unsigned long options_specified = 0;
static action_list_t action_list = { 0 };
static struct bootloader_control abc_metadata = { 0 };
static bool metadata_loaded = false;
static bool metadata_changed = false;
static int abc_fd = -1;
static uint32_t initial_checksum;

/**
 * @brief Store A/B metadata to the device.
 *
 * @param device The device path.
 * @param abc Pointer to the bootloader control structure.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_store(const char *device, struct bootloader_control *abc)
{
	off_t abc_offset = offsetof(struct bootloader_message_ab, slot_suffix);
	ssize_t bytes_written;

	bytes_written = dev_write(abc_fd, abc_offset, sizeof(*abc), abc);
	if (bytes_written != sizeof(*abc)) {
		log_error("Could not write A/B metadata to '%s' (wrote %zd bytes)",
		                device, bytes_written);
		return (bytes_written < 0) ? (int)bytes_written : -EIO;
	}

	log_info("A/B metadata stored to '%s' successfully.", device);
	return 0;
}

/**
 * @brief Validate A/B metadata.
 *
 * @param abc Pointer to the bootloader control structure.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_validate(struct bootloader_control *abc)
{
	size_t len;
	uint32_t crc32_le;

	len = offsetof(struct bootloader_control, crc32_le);
	crc32_le = crc32((uint8_t *)abc, len);
	if (crc32_le != abc->crc32_le) {
		log_error("Invalid CRC32 (expected %.8x, found %.8x)",
		              crc32_le, abc->crc32_le);
		return -EIO;
	}

	if (abc->magic != BOOTLOADER_CONTROL_MAGIC) {
		log_error("Invalid A/B metadata magic");
		return -EINVAL;
	}

	if (abc->version != BOOTLOADER_CONTROL_VERSION) {
		log_error("Unsupported A/B metadata version");
		return -EINVAL;
	}

	return 0;
}

/**
 * @brief Load A/B metadata from the device.
 *
 * @param device The device path.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_load(const char *device)
{
	ulong abc_offset = offsetof(struct bootloader_message_ab, slot_suffix);
	struct stat device_stat;
	int bytes_read;
	int ret = 0;

	if (fstat(abc_fd, &device_stat) < 0) {
		log_error("Could not stat device %s: %s", device, strerror(errno));
		return -errno;
	}

	// Read A/B metadata
	bytes_read = dev_read(abc_fd, abc_offset, sizeof(abc_metadata), &abc_metadata);
	if (bytes_read != sizeof(abc_metadata)) {
		log_error("Could not read A/B metadata from '%s'", device);
		return -EIO;
	}

	ret = abc_validate(&abc_metadata);
	if (ret < 0) {
		log_error("Invaild A/B metadata within '%s' device", device);
		return ret;
	}

	metadata_loaded = true;
	initial_checksum = abc_metadata.crc32_le;

	return 0;
}

/**
 * @brief Generate default A/B metadata.
 *
 * @param abc Pointer to the bootloader control structure.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_default(struct bootloader_control *abc)
{
	int i;
	const struct slot_metadata metadata = {
		.priority = AB_MAX_PRIORITY,
		.tries_remaining = AB_MAX_TRIES_REMAINING,
		.successful_boot = 0,
		.verity_corrupted = 0,
		.reserved = 0
	};

	memcpy(abc->slot_suffix, "a\0\0\0", 4);
	abc->magic = BOOTLOADER_CONTROL_MAGIC;
	abc->version = BOOTLOADER_CONTROL_VERSION;
	abc->nb_slot = NUM_SLOT;
	memset(abc->reserved0, 0, sizeof(abc->reserved0));

	for (i = 0; i < abc->nb_slot; i++)
		memcpy(&abc->slot_info[i], &metadata, sizeof(metadata));
	memset(abc->reserved1, 0, sizeof(abc->reserved1));
	metadata_changed = true;

	log_info("Generated default A/B metadata");
	return 0;
}

/**
 * @brief Get the active slot.
 *
 * Returns the active slot number on success, a negative error code on failure.
 */
static int abc_get_active_slot(void)
{
	int slot, i;

	if (!metadata_loaded) {
		log_error("A/B metadata not loaded");
		return -ENODATA;
	}

	for (i = 0; i < MAX_SLOTS; i++)
		if (abc_metadata.slot_suffix[i])
			break;

	if (i == MAX_SLOTS)
		return -EINVAL;

	slot = toupper(abc_metadata.slot_suffix[i]) - 'A';

	return slot;
}

/**
 * @brief Prepare the slot number.
 *
 * @param optarg The slot argument.
 *
 * Returns the prepared slot number on success, a negative error code on failure.
 */
static int abc_prepare_slot(const char *optarg)
{
	char token;
	int slot;

	if (optarg) {
		token = toupper(optarg[0]);
		if (!isalnum(token) || (token != '0' && token != '1' &&
		    token != 'A' && token != 'B') ) {
			log_error("Invalid SLOT");
			return -EINVAL;
		}
		slot = isdigit(token) ? token - '0' : token - 'A';
	} else {
		slot = abc_get_active_slot();
		if (slot < 0)
			return slot;
	}

	return slot;
}

/**
 * @brief Mark a slot as successful.
 *
 * @param slot The slot number.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_mark_successful(int slot)
{
	struct slot_metadata *slotp = &abc_metadata.slot_info[slot];

	slotp->successful_boot = 1;
	slotp->tries_remaining = AB_MAX_TRIES_REMAINING;
	metadata_changed = true;

	log_info("Slot %c marked as successful", SLOT_NAME(slot));
	return 0;
}

/**
 * @brief Set the active boot slot.
 *
 * @param slot The slot number.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_set_active_boot(int slot)
{
	struct slot_metadata *slotp;
	int slot1;

	if (slot > 2) {
		log_error("Wrong slot value");
		return -EINVAL;
	}

	slotp = &abc_metadata.slot_info[slot];
	slotp->priority = AB_MAX_PRIORITY;
	slotp->tries_remaining = AB_MAX_TRIES_REMAINING;
	slotp->successful_boot = 0;

	slot1 = slot ? 0 : 1;
	slotp = &abc_metadata.slot_info[slot1];
	if (slotp->priority == AB_MAX_PRIORITY)
		slotp->priority = AB_MAX_PRIORITY - 1;
	metadata_changed = true;

	log_info("Slot %c marked as next active ", SLOT_NAME(slot));
	return 0;
}

/**
 * @brief Set a slot as unbootable.
 *
 * @param slot The slot number.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_set_unbootable(int slot)
{
	struct slot_metadata *slotp = &abc_metadata.slot_info[slot];

	slotp->successful_boot = 0;
	slotp->priority = 0;
	slotp->tries_remaining = 0;

	metadata_changed = true;

	log_info("Slot %c marked as unbootable", SLOT_NAME(slot));
	return 0;
}

/**
 * @brief Check if a slot is bootable.
 *
 * @param slot The slot number.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_check_bootable(int slot)
{
	struct slot_metadata *slotp = &abc_metadata.slot_info[slot];

	log_info("Slot %c marked as %s", SLOT_NAME(slot),
				slotp->priority != 0 ? "bootable" : "unbootable");
	return 0;
}

/**
 * @brief Check the boot-up status of a slot.
 *.
 * @param slot The slot number.
 *
 */
static int abc_check_bootup_status(int slot)
{
	struct slot_metadata *slotp = &abc_metadata.slot_info[slot];

	log_info("Slot %c marked as %s", SLOT_NAME(slot),
				slotp->successful_boot ? "successful" : "unsuccessful");
	return 0;
}

/**
 * @brief Get the suffix of a slot.
 *
 * @param slot The slot number.
 *
 * Returns 0 on success, a negative error code on failure.
 */
static int abc_get_suffix(int slot)
{
	static const char* suffix[2] = {"_a", "_b"};

	if (slot > 2) {
		log_error("Wrong SLOT");
		return -EINVAL;
	}

	log_info("%s", suffix[slot]);
	return 0;
}

void print_usage(const char *prog_name)
{
	printf("%s [-V] [-h] [options]\n\n", prog_name);
	printf("Manage A/B metadata tool\n\n");
	printf("Options:\n");
	printf("  -d <device>   Specify the device\n");
	printf("  -p            Dump slot info\n");
	printf("  -g            Generate default metadata\n");
	printf("  -n            Get number of slots\n");
	printf("  -c            Get current slot\n");
	printf("  -m [SLOT]     Mark boot successful\n");
	printf("  -a [SLOT]     Set active boot slot\n");
	printf("  -u [SLOT]     Set slot as unbootable\n");
	printf("  -b [SLOT]     Check if slot is bootable\n");
	printf("  -s [SLOT]     Check if slot is marked successful\n");
	printf("  -x [SLOT]     Get suffix\n");
	printf("  -V            Set log level to verbose\n");
	printf("  -h            Show help\n");
	printf("  -v            Show version\n");
}

/**
 * @brief Override an action in the action list.
 *
 * @param action The action to override.
 * @param optarg The argument for the action.
 */
static void override_action(action_t action, const char *optarg)
{
	for (int j = 0; j < action_list.action_count; j++) {
		if (action_list.actions[j].action == action) {
			action_list.actions[j].slot = abc_prepare_slot(optarg);
			break;
		}
	}
}

/**
 * @brief Process an action and add it to the action list.
 *
 * @param option_bit The option bit for the action.
 * @param action The action to process.
 * @param optarg The argument for the action.
 */
static void process_action(unsigned long option_bit, action_t action, const char *optarg)
{
	if (!(options_specified & option_bit)) {
		action_list.actions[action_list.action_count].action = action;
		if (optarg) {
			action_list.actions[action_list.action_count].slot = abc_prepare_slot(optarg);
		}
		action_list.action_count++;
		options_specified |= option_bit;
	} else {
		// Override previous action
		override_action(action, optarg);
	}
}

static const char *get_action_name(action_t action)
{
	static const char *action_names[] = {
		"GET_NUMBER_SLOTS",
		"GET_CURRENT_SLOT",
		"MARK_BOOT_SUCCESSFUL",
		"SET_ACTIVE_BOOT_SLOT",
		"SET_SLOT_AS_UNBOOTABLE",
		"IS_SLOT_BOOTABLE",
		"IS_SLOT_MARKED_SUCCESSFUL",
		"GET_SUFFIX",
		"DUMP_SLOT_INFO",
		"GENERATE_DEFAULT_METADATA",
	};

	if (action >= GET_NUMBER_SLOTS && action < ABC_COUNT) {
		return action_names[action];
	} else {
		return "UNKNOWN";
	}
}

static int abc_dump_slot_info(void)
{
	int i;

	printf("Slot Info:\n");
	for (i = 0; i < abc_metadata.nb_slot; i++) {
		struct slot_metadata *slotp = &abc_metadata.slot_info[i];
		printf("  Slot %c:\n", SLOT_NAME(i));
		printf("    Priority: %d\n", slotp->priority);
		printf("    Tries Remaining: %d\n", slotp->tries_remaining);
		printf("    Successful Boot: %d\n", slotp->successful_boot);
	}

	return 0;
}

int main(int argc, char *argv[])
{
	int opt;
	const char *devices[MAX_DEVICES] = {NULL};
	int device_count = 0;
	bool device_loaded = false;
	int dev_idx = -1;
	int ret = EXIT_FAILURE;

	log_set_level(LOG_INFO);

	if (argc < 2) {
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	memset(action_list.actions, 0, sizeof(action_list.actions));

	while ((opt = getopt(argc, argv, "hd:ncm:a:u:b:s:x:pgVv")) != -1) {
		if (action_list.action_count >= MAX_ACTIONS) {
			log_warn("Too many actions specified, ignoring option %c", opt);
			continue;
		}

		action_list.actions[action_list.action_count].slot = -1;

		switch (opt) {
			case 'h':
				print_usage(argv[0]);
				return EXIT_SUCCESS;
			case 'd':
				if (device_count < MAX_DEVICES) {
					devices[device_count++] = optarg;
				} else {
					log_warn("Too many devices specified, ignoring %s", optarg);
				}
				break;
			case 'n':
				process_action(OPT_N, GET_NUMBER_SLOTS, NULL);
				break;
			case 'c':
				process_action(OPT_C, GET_CURRENT_SLOT, NULL);
				break;
			case 'm':
				process_action(OPT_M, MARK_BOOT_SUCCESSFUL, optarg);
				break;
			case 'a':
				process_action(OPT_A, SET_ACTIVE_BOOT_SLOT, optarg);
				break;
			case 'u':
				process_action(OPT_U, SET_SLOT_AS_UNBOOTABLE, optarg);
				break;
			case 'b':
				process_action(OPT_B, IS_SLOT_BOOTABLE, optarg);
				break;
			case 's':
				process_action(OPT_S, IS_SLOT_MARKED_SUCCESSFUL, optarg);
				break;
			case 'x':
				process_action(OPT_X, GET_SUFFIX, optarg);
				break;
			case 'p':
				process_action(OPT_P, DUMP_SLOT_INFO, NULL);
				break;
			case 'g':
				process_action(OPT_G, GEN_DEFAULT, NULL);
				break;
			case 'V':
				log_set_level(LOG_DEBUG);
				break;
			case 'v':
				log_info("Version: %s\n", ABC_TOOL_VERSION);
				return EXIT_SUCCESS;
			default:
				print_usage(argv[0]);
				return EXIT_FAILURE;
		}
	}

	if (device_count == 0) {
		log_error("Device not specified");
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	if (action_list.action_count == 0) {
		log_error("No action specified");
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	// Validate slot numbers
	for (int i = 0; i < action_list.action_count; i++) {
		bool validate_slot = false;
		action_params_t *action = &action_list.actions[i];
		switch (action->action) {
			case SET_ACTIVE_BOOT_SLOT:
			case SET_SLOT_AS_UNBOOTABLE:
			case IS_SLOT_BOOTABLE:
			case IS_SLOT_MARKED_SUCCESSFUL:
			case GET_SUFFIX:
			case MARK_BOOT_SUCCESSFUL:
				validate_slot = true;
				break;
			default:
				break;
		}

		if (validate_slot && (action->slot < 0 || action->slot > 2)) {
			const char *action_name = get_action_name(action->action);
			log_error("Wrong slot for action %s", action_name);
			return EXIT_FAILURE;
		}
	}

	// Initialize and open the device, then read A/B metadata from the device
	for (int i = 0; i < device_count; i++) {
		abc_fd = open(devices[i], O_RDWR);
		if (abc_fd < 0) {
			log_error("Could not open device %s: %s", devices[i], strerror(errno));
			continue;
		}
		if (abc_load(devices[i]) < 0) {
			log_error("Could not load A/B metadata from '%s'", devices[i]);
			close(abc_fd);
			abc_fd = -1;
		} else {
			device_loaded = true;
			dev_idx = i;
			break;
		}
	}

	if (!device_loaded) {
		log_error("Unable to load A/B metadata");
		return EXIT_FAILURE;
	}

	for (int i = 0; i < action_list.action_count; i++) {
		action_params_t *action = &action_list.actions[i];
		action_t action_type = action->action;
		int slot = action->slot;
		switch (action_type) {
		case GET_NUMBER_SLOTS:
			log_info("Number of slots: %d", abc_metadata.nb_slot);
			break;
		case GET_CURRENT_SLOT:
			slot = abc_get_active_slot();
			if (slot < 0) {
				log_error("Invaild current active slot");
				return EXIT_FAILURE;
			}
			log_info("Current active slot: %c", SLOT_NAME(slot));
			break;
		case MARK_BOOT_SUCCESSFUL:
			if (abc_mark_successful(slot) < 0)
				goto out;
			break;
		case SET_ACTIVE_BOOT_SLOT:
			if (abc_set_active_boot(slot) < 0)
				goto out;
			break;
		case SET_SLOT_AS_UNBOOTABLE:
			if (abc_set_unbootable(slot) < 0)
				goto out;
			break;
		case IS_SLOT_BOOTABLE:
			if (abc_check_bootable(slot) < 0)
				return EXIT_FAILURE;
			break;
		case IS_SLOT_MARKED_SUCCESSFUL:
			if (abc_check_bootup_status(slot) < 0)
				return EXIT_FAILURE;
			break;
		case GET_SUFFIX:
			if (abc_get_suffix(slot) < 0)
				return EXIT_FAILURE;
			break;
		case DUMP_SLOT_INFO:
			if (abc_dump_slot_info() < 0)
				goto out;
			break;
		case GEN_DEFAULT:
				if (abc_default(&abc_metadata) < 0)
				goto out;
			break;
		default:
			log_error("Unknown action %d", action_type);
			return EXIT_FAILURE;
		}
	}

	ret = EXIT_SUCCESS;

out:
	if (metadata_changed) {
		uint32_t current_checksum = crc32((uint8_t *)&abc_metadata,
		                offsetof(struct bootloader_control, crc32_le));
		log_debug("Initial checksum: %.8x, current checksum: %.8x",
		                initial_checksum, current_checksum);
		if (current_checksum != initial_checksum) {
			abc_metadata.crc32_le = current_checksum;
			if (abc_store(devices[dev_idx], &abc_metadata) < 0) {
				log_error("Unable to store A/B metadata");
				ret = EXIT_FAILURE;
			}
		} else {
			log_info("A/B metadata not changed, skip store");
		}
	}

	if (abc_fd >= 0)
		close_device(abc_fd);
	return ret;
}