/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Manage BCB (Bootloader Control Block) fields tool
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
#include <sys/stat.h>
#include <ctype.h>

#include "bootloader_message.h"
#include "crc32.h"
#include "log.h"
#include "device_io.h"
#include "bcb.h"

typedef struct {
	action_t action;
	const char *field;
	const char *op;
	const char *value;
} bcb_params_t;

static unsigned long options_specified = 0;
static action_list_t action_list = {0};

static struct bootloader_message bcb = { 0 };
uint32_t expected_crc32 = 0;
static bool bcb_loaded = false;
static bool bcb_changed = false;
static int bcb_fd = -1;
static bool allow_direct = false;

static void print_usage(const char *prog_name) {
	printf("%s [-h] [options]\n\n", prog_name);
	printf("Manage BCB metadata tool\n\n");
	printf("Options:\n");
	printf("  -d <device>           Specify the BCB device path (e.g., /dev/misc)\n");
	printf("  -s <field> <val>      Set   BCB <field> to <val>\n");
	printf("  -c [<field>]          Clear BCB <field> or all fields\n");
	printf("  -C                    Clear all BCB fields\n");
	printf("  -t <field> <op> <val> Test  BCB <field> against <val>\n");
	printf("  -p <field>            Dump  BCB <field>\n");
	printf("  -P                    Dump all BCB fields\n");
	printf("  -A                    Allow direct write, bypassing redundant checks\n");
	printf("  -V                    Set log level to verbose\n");
	printf("  -h                    Show this help message\n");
	printf("\nLegend:\n");
	printf("  <field> - one of {command,status,recovery,stage,reserved}\n");
	printf("  <op>    - the binary operator used in 'bcb test':\n");
	printf("            '=' returns true if <val> matches the string stored in <field>\n");
	printf("            '~' returns true if <val> matches a subset of <field>'s string\n");
	printf("  <val>   - string/text provided as input to bcb {set,test}\n");
	printf("            NOTE: any ':' character in <val> will be replaced by line feed\n");
	printf("            during 'bcb set' and used as separator by upper layers\n");
	printf("\nExamples:\n");
	printf("  %s -d /dev/misc -s command boot-recovery\n", prog_name);
	printf("  %s -d /dev/misc -c command\n", prog_name);
	printf("  %s -d /dev/misc -C\n", prog_name);
	printf("  %s -d /dev/misc -t command = boot-recovery\n", prog_name);
	printf("  %s -d /dev/misc -p command\n", prog_name);
	printf("  %s -d /dev/misc -P\n", prog_name);
	printf("\n");
}

static void print_field_if_printable(const char *name, const char *field, int size)
{
	bool has_printable = false;
	for (int i = 0; i < size; i++) {
		if (field[i] == '\0')
			break;
		if (isprint((unsigned char)field[i])) {
			has_printable = true;
			break;
		}
	}

	if (has_printable) {
		printf("  %-9s '%.*s'\n", name, size, field);
	} else {
		printf("  %-9s ''\n", name);
	}
}

static void view_bcb(const struct bootloader_message *bcb) {
	printf("BCB Content:\n");
	print_field_if_printable("Command:", bcb->command, sizeof(bcb->command));
	print_field_if_printable("Status:", bcb->status, sizeof(bcb->status));
	print_field_if_printable("Recovery:", bcb->recovery, sizeof(bcb->recovery));
	print_field_if_printable("Stage:", bcb->stage, sizeof(bcb->stage));
}

static const char *get_action_name(action_t action)
{
	static const char *action_names[] = {
		"CLEAR",
		"SET",
		"TEST",
		"DUMP",
	};

	if (action >= BCB_CLEAR && action < BCB_COUNT) {
		return action_names[action];
	} else {
		return "UNKNOWN";
	}
}

/**
 * @brief Load BCB metadata from the device.
 *
 * @param device The device path.
 * Return 0 on success, negative error code on failure.
 */
static int bcb_load(const char *device)
{
	ulong bcb_offset = offsetof(struct bootloader_message_ab, message);
	struct stat device_stat;
	int bytes_read;

	if (fstat(bcb_fd, &device_stat) < 0) {
		log_error("Could not stat device %s: %s", device, strerror(errno));
		return -errno;
	}

	// Read BCB metadata
	bytes_read = dev_read(bcb_fd, bcb_offset, sizeof(bcb), &bcb);
	if (bytes_read != sizeof(bcb)) {
		log_error("Could not read bcb metadata from '%s'", device);
		return -EIO;
	}

	expected_crc32 = crc32((void *)&bcb, sizeof(bcb));
	bcb_loaded = true;

	return 0;
}

static int bcb_load_redund(const char *device1, const char *device2)
{
	struct bootloader_message_ab *buffer;
	int ret;
	int fd1, fd2;

	if (!device1 || !device2) {
		log_error("Invalid device paths");
		return -EINVAL;
	}

	buffer = malloc(sizeof(struct bootloader_message_ab));
	if (!buffer) {
		log_error("Out of memory for buffer");
		return -ENOMEM;
	}

	fd1 = open(device1, O_RDWR);
	if (fd1 < 0) {
		log_error("Could not open device %s: %s", device1, strerror(errno));
		free(buffer);
		return -errno;
	}

	fd2 = open(device2, O_RDWR);
	if (fd2 < 0) {
		log_error("Could not open device %s: %s", device2, strerror(errno));
		close(fd1);
		free(buffer);
		return -errno;
	}

	ret = bootloader_message_ab_load(fd1, fd2, 0, buffer);
	if (ret < 0) {
		log_error("Failed to load AB-specific bootloader message: %s", strerror(-ret));
		free(buffer);
		close(fd1);
		close(fd2);
		return ret;
	}

	memcpy(&bcb, &buffer->message, sizeof(bcb));
	expected_crc32 = crc32((void *)&bcb, sizeof(bcb));
	bcb_loaded = true;

	free(buffer);
	close(fd1);
	close(fd2);

	return 0;
}

/**
 * @brief Store BCB metadata to the device.
 *
 * @param device The device path.
 * @param bcb Pointer to the bootloader_message structure.
 * Return 0 on success, negative error code on failure.
 */
static int bcb_store(const char *device, struct bootloader_message *bcb)
{
	off_t bcb_offset = offsetof(struct bootloader_message_ab, message);
	ssize_t bytes_written;

	bytes_written = dev_write(bcb_fd, bcb_offset, sizeof(*bcb), bcb);
	if (bytes_written != sizeof(*bcb)) {
		log_error("Could not write BCB metadata to '%s' (wrote %zd bytes)",
		                device, bytes_written);
		return (bytes_written < 0) ? (int)bytes_written : -EIO;
	}

	log_info("BCB metadata stored to '%s' successfully.", device);
	return 0;
}

static int bcb_store_redund(const char *device1, const char *device2,
			    struct bootloader_message *bcb)
{
	struct bootloader_message_ab bl_msg_ab;
	int ret;
	int fd1, fd2;

	if (!device1 || !device2) {
		log_error("Invalid device paths");
		return -EINVAL;
	}

	fd1 = open(device1, O_RDWR);
	if (fd1 < 0) {
		log_error("Could not open device %s: %s", device1, strerror(errno));
		return -errno;
	}

	fd2 = open(device2, O_RDWR);
	if (fd2 < 0) {
		log_error("Could not open device %s: %s", device2, strerror(errno));
		close(fd1);
		return -errno;
	}

	/* Load the whole message to preserve BCB metadata */
	ret = bootloader_message_ab_load(fd1, fd2, 0, &bl_msg_ab);
	if (ret < 0) {
		log_warn("Could not load bootloader message, using empty one: %s",
			 strerror(-ret));
		memset(&bl_msg_ab, 0, sizeof(bl_msg_ab));
	}

	memcpy(&bl_msg_ab.message, bcb, sizeof(*bcb));

	ret = bootloader_message_ab_store(fd1, fd2, 0, &bl_msg_ab, false);
	if (ret < 0) {
		log_error("Failed to store AB-specific bootloader message: %s", strerror(-ret));
		close(fd1);
		close(fd2);
		return ret;
	}

	close(fd1);
	close(fd2);

	return 0;
}

/**
 * @brief Get a pointer and size for a named BCB field.
 *
 * @param name Field name.
 * @param fieldp Output pointer to the field.
 * @param sizep Output size of the field.
 * Return 0 on success, negative error code on failure.
 */
static int bcb_field_get(char *name, char **fieldp, int *sizep)
{
	if (!strcmp(name, "command")) {
		*fieldp = bcb.command;
		*sizep = sizeof(bcb.command);
	} else if (!strcmp(name, "status")) {
		*fieldp = bcb.status;
		*sizep = sizeof(bcb.status);
	} else if (!strcmp(name, "recovery")) {
		*fieldp = bcb.recovery;
		*sizep = sizeof(bcb.recovery);
	} else if (!strcmp(name, "stage")) {
		*fieldp = bcb.stage;
		*sizep = sizeof(bcb.stage);
	} else if (!strcmp(name, "reserved")) {
		*fieldp = bcb.reserved;
		*sizep = sizeof(bcb.reserved);
	} else {
		log_debug("Unknown bcb field '%s'\n", name);
		return -EINVAL;
	}

	return 0;
}

/**
 * @brief Set a BCB field to a value.
 *
 * @param action Pointer to action_params_t.
 * Return 0 on success, negative error code on failure.
 */
static int do_bcb_set(action_params_t *action)
{
	const char *name;
	char *field;
	int size;

	if (bcb_field_get(action->field, &field, &size) < 0) {
		name = get_action_name(action->action);
		log_error("%s: Invalid field '%s' for '%s' action",
		                  __func__, action->field, name);
		return -EINVAL;
	}
	memset(field, 0, size);
	strncpy(field, action->value, size - 1);

	log_debug("BCB '%s' field set to '%s'", action->field, action->value);

	bcb_changed = true;

	return 0;
}

/**
 * @brief Clear a BCB field or all fields.
 *
 * @param action Pointer to action_params_t.
 * Return 0 on success, negative error code on failure.
 */
static int do_bcb_clear(action_params_t *action)
{
	const char *name;
	char *field;
	int size;
	bool is_zero;

	is_zero = (strlen(action->field) == 0);

	if (!is_zero &&
	     bcb_field_get(action->field, &field, &size) < 0) {
		name = get_action_name(action->action);
		log_error("%s: Invalid field '%s' for '%s' action.",
		                  __func__, action->field, name);
		return -EINVAL;
	}

	if (is_zero)
		memset(&bcb, 0, sizeof(bcb));
	else
		memset(field, 0, size);

	log_debug("BCB '%s' field cleared", is_zero ? "all" : action->field);

	bcb_changed = true;

	return 0;
}

/**
 * @brief Test a BCB field against a value with an operator.
 *
 * @param action Pointer to action_params_t.
 * Return 0 if test passes, negative error code otherwise.
 */
static int do_bcb_test(action_params_t *action)
{
	const char *name = NULL;
	char *field;
	int size;
	bool result = false;

	name = get_action_name(action->action);
	if (bcb_field_get(action->field, &field, &size) < 0) {
		log_error("%s: Invalid field '%s' for '%s' action.",
		                  __func__, action->field, name);
		return -EINVAL;
	}

	if (!strcmp(action->op, "=")) {
		result = !strcmp(field, action->value);
	} else if (!strcmp(action->op, "~")) {
		result = strstr(field, action->value) != NULL;
	} else {
		log_error("Unknown operator '%s' for '%s' action.",
		                  action->op, name);
		return -EINVAL;
	}

	log_info("Test result for field '%s': %s",
	              action->field, result ? "true" : "false");
	return result ? 0 : -ENOENT;
}

/**
 * @brief Dump a BCB field or all fields.
 *
 * @param action Pointer to action_params_t.
 * Return 0 on success, negative error code on failure.
 */
static int do_bcb_dump(action_params_t *action)
{
	const char *name;
	char *field;
	int size;
	bool is_zero;

	is_zero = (strlen(action->field) == 0);
	if (!is_zero &&
	     bcb_field_get(action->field, &field, &size) <0) {
		name = get_action_name(action->action);
		log_error("%s: Invalid field '%s' for '%s' action.",
		                  __func__, action->field, name);
		return -EINVAL;
	}

	if (is_zero) {
		view_bcb(&bcb);
	} else {
		bool has_printable = false;
		for (int i = 0; i < size; i++) {
			if (field[i] == '\0')
				break;
			if (isprint((unsigned char)field[i])) {
				has_printable = true;
				break;
			}
		}
		if (has_printable)
			printf("%s: \"%.*s\"\n", action->field, size, field);
		else
			printf("%s: \"\"\n", action->field);
	}

	return 0;
}

/**
 * @brief Check if the action parameters are valid/misused.
 *
 * @param param Pointer to bcb_params_t.
 * Return 0 if valid, negative error code otherwise.
 */
static int bcb_is_misused(bcb_params_t *param)
{
	const char *name;

	name = get_action_name(param->action);
	switch(param->action) {
		case BCB_SET:
			if (!param->field || !param->value) {
				log_error("Lack of field and value for '%s' action.", name);
				return -EINVAL;
			}
			break;
		case BCB_CLEAR:
			break;
		case BCB_TEST:
			if (!param->field || !param->op || !param->value) {
				log_error("Lack of field, operator, and value for '%s' action.", name);
				return -EINVAL;
			}
			break;
		case BCB_DUMP:
			if (!param->field) {
				log_error("Lack of field and value for '%s' action.", name);
				return -EINVAL;
			}
			break;
		default:
			log_error("'%s' action", name);
			return -EINVAL;
	}
	return 0;
}

static void to_action(bcb_params_t *param, action_params_t *action)
{
	memset(action, 0, sizeof(action_params_t));
	action->action = param->action;
	if (param->field)
		strncpy(action->field, param->field, sizeof(action->field) - 1);
	if (param->op)
		strncpy(action->op, param->op, sizeof(action->op) - 1);
	if (param->value)
		strncpy(action->value, param->value, sizeof(action->value) - 1);
}

static void override_action(bcb_params_t *param)
{
	action_params_t action;

	to_action(param, &action);
	for (int i = 0; i < action_list.action_count; i++) {
		if (!memcmp(&action_list.actions[i], &action, sizeof(action_params_t))) {
			log_info("Overriding action %d with new parameters", param->action);
			return;
		}
	}

	/*
	 * If we reach here, it means the same action was not found in the list,
	 * so we add it as a new action.
	 */
	action_list.actions[action_list.action_count] = action;
	action_list.action_count++;
	log_debug("Added new action %d with parameters", param->action);
}

static void process_action(unsigned long option_bit, bcb_params_t *param)
{
	if (!(options_specified & option_bit)) {
		to_action(param, &action_list.actions[action_list.action_count]);
		action_list.action_count++;
		options_specified |= option_bit;
	} else {
		override_action(param);
	}
}

int main(int argc, char *argv[])
{
	const char *devices[MAX_DEVICES] = {NULL};
	int device_count = 0;
	int opt;
	int ret = EXIT_FAILURE;
	bool device_loaded = false;
	bcb_params_t param = { 0 };

	log_set_level(LOG_INFO);

	if (argc == 1) {
		print_usage(argv[0]);
		return EXIT_SUCCESS;
	}

	memset(action_list.actions, 0, sizeof(action_list.actions));

	while ((opt = getopt(argc, argv, "d:s:c:Ct:p:PhAV")) != -1) {
		if (action_list.action_count >= MAX_ACTIONS) {
			log_warn("Too many actions specified, ignoring option %c", opt);
			continue;
		}

		memset(&param, 0, sizeof(param));
		switch (opt) {
			case 'd':
				if (device_count < MAX_DEVICES) {
					devices[device_count++] = optarg;
				} else {
					log_warn("Too many devices specified, ignoring %s", optarg);
				}
				break;
			case 'A':
				allow_direct = true;
				break;
			case 'V':
				log_set_level(LOG_DEBUG);
				break;
			case 's':
				log_debug("Set BCB field '%s' to '%s'\n", optarg, argv[optind]);
				param.action = BCB_SET;
				param.field = optarg;
				param.value = argv[optind];
				if (bcb_is_misused(&param) < 0) {
					log_error("Invalid parameters for action %d", param.action);
					return EXIT_FAILURE;
				}
				process_action(OPT_SET, &param);
				break;
			case 'c':
				log_debug("Clear BCB field '%s'\n", optarg);
				param.action = BCB_CLEAR;
				param.field = optarg;
				process_action(OPT_CLEAR, &param);
				break;
			case 'C':
				log_debug("Clear all BCB fields\n");
				param.action = BCB_CLEAR;
				param.field = NULL;
				process_action(OPT_CLEAR, &param);
				break;
			case 't':
				log_debug("Test BCB field '%s' with operator '%s' and value '%s'\n",
				                   optarg, argv[optind], argv[optind + 1]);
				param.action = BCB_TEST;
				param.field = optarg;
				param.op = argv[optind];
				param.value = argv[optind + 1];
				if (bcb_is_misused(&param) < 0) {
					log_error("Invalid parameters for action %d", param.action);
					return EXIT_FAILURE;
				}
				process_action(OPT_TEST, &param);
				break;
			case 'p':
				log_debug("Dump BCB field '%s'\n", optarg);
				param.action = BCB_DUMP;
				param.field = optarg;
				if (bcb_is_misused(&param) < 0) {
					log_error("Invalid parameters for action %d", param.action);
					return EXIT_FAILURE;
				}
				process_action(OPT_DUMP, &param);
				break;
			case 'P':
				log_debug("Dump all BCB fields\n");
				param.action = BCB_DUMP;
				param.field = NULL;
				process_action(OPT_DUMP, &param);
				break;
			case 'h':
				print_usage(argv[0]);
				return EXIT_SUCCESS;
			default:
				log_error("Unknown option: -%c\n", (char)opt);
				print_usage(argv[0]);
				return EXIT_FAILURE;
		}
	}

	if (device_count == 0) {
		log_error("Device not specified.");
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	if (action_list.action_count == 0) {
		log_error("No action specified.");
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	// Initialize and open the device, then read BCB metadata from the device
	const char *unique_devices[MAX_DEVICES] = {NULL};
	int unique_device_count = 0;
	for (int i = 0; i < device_count; i++) {
		bool is_duplicate = false;
		for (int j = 0; j < unique_device_count; j++) {
			if (strcmp(devices[i], unique_devices[j]) == 0) {
				is_duplicate = true;
				break;
			}
		}
		if (!is_duplicate) {
			unique_devices[unique_device_count++] = devices[i];
		}
	}

	if (unique_device_count > 2) {
		log_error("More than 2 devices are not supported.");
		return EXIT_FAILURE;
	} else if (unique_device_count == 2) {
		if (bcb_load_redund(unique_devices[0], unique_devices[1]) < 0) {
			log_error("Could not load BCB metadata from redundant devices '%s' and '%s'",
				  unique_devices[0], unique_devices[1]);
		} else {
			device_loaded = true;
		}
	} else if (unique_device_count == 1) {
		bcb_fd = open(unique_devices[0], O_RDWR);
		if (bcb_fd < 0) {
			log_error("Could not open device %s: %s", unique_devices[0], strerror(errno));
		} else {
			if (bcb_load(unique_devices[0]) < 0) {
				log_error("Could not load BCB metadata from '%s'", unique_devices[0]);
				close(bcb_fd);
				bcb_fd = -1;
			} else {
				device_loaded = true;
			}
		}
	}

	if (!device_loaded) {
		log_error("Unable to load BCB metadata");
		return EXIT_FAILURE;
	}

	for (int i = 0; i < action_list.action_count; i++) {
		action_params_t *action = &action_list.actions[i];
		action_t action_type = action->action;

		switch (action_type) {
		case BCB_SET:
			if (do_bcb_set(action) < 0)
				goto out;
			break;
		case BCB_CLEAR:
			if (do_bcb_clear(action) < 0)
				goto out;
			break;
		case BCB_TEST:
			if (do_bcb_test(action) < 0)
				goto out;
			break;
		case BCB_DUMP:
			if (do_bcb_dump(action) < 0)
				goto out;
			break;
		default:
			log_error("Unknown action %d field", action_type);
			break;
		}
	}

	ret = EXIT_SUCCESS;

out:
	if (bcb_changed) {
		uint32_t found_crc32 = crc32((uint8_t *)&bcb, sizeof(bcb));
		if (found_crc32 != expected_crc32) {
			if (unique_device_count == 2) {
				if (bcb_store_redund(unique_devices[0], unique_devices[1], &bcb) < 0) {
					log_error("Unable to store BCB metadata to redundant devices");
					ret = EXIT_FAILURE;
				}
			} else if (unique_device_count == 1) {
				log_warn("*************************** WARNING *****************************");
				log_warn("With a redundant configuration, directly updating bcb metadata");
				log_warn("might break the CRC of the AB-specific bootloader message on");
				log_warn("'%s'. Use with extreme caution.", unique_devices[0]);
				log_warn("*****************************************************************");
				if (allow_direct && bcb_store(unique_devices[0], &bcb) < 0) {
					log_error("Unable to store BCB metadata");
					ret = EXIT_FAILURE;
				}
			}
		} else {
			log_info("BCB metadata not changed, skip store");
		}
	}

	if (bcb_fd >= 0)
		close_device(bcb_fd);
	return ret;
}