/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#ifndef ABC_H
#define ABC_H

#include <stdint.h>
#include <stddef.h>

#define MAX_SLOTS      4
#define NUM_SLOT       2
// Define a maximum number of devices
#define MAX_DEVICES    10
#define MAX_ACTIONS    10

#define ABC_TOOL_VERSION "1.1.0"

#define BOOTLOADER_CONTROL_MAGIC 0x42414342
#define BOOTLOADER_CONTROL_VERSION 1

typedef enum {
	GET_NUMBER_SLOTS,
	GET_CURRENT_SLOT,
	MARK_BOOT_SUCCESSFUL,
	SET_ACTIVE_BOOT_SLOT,
	SET_SLOT_AS_UNBOOTABLE,
	IS_SLOT_BOOTABLE,
	IS_SLOT_MARKED_SUCCESSFUL,
	GET_SUFFIX,
	DUMP_SLOT_INFO,
	GEN_DEFAULT,

	ABC_COUNT
} action_t;

typedef struct {
	action_t action;
	int slot;
} action_params_t;

typedef struct {
	action_params_t actions[MAX_ACTIONS];
	int action_count;
} action_list_t;

#define BIT(x) (1UL << (x))

#define OPT_N BIT(0)
#define OPT_C BIT(1)
#define OPT_M BIT(2)
#define OPT_A BIT(3)
#define OPT_U BIT(4)
#define OPT_B BIT(5)
#define OPT_S BIT(6)
#define OPT_X BIT(7)
#define OPT_P BIT(8)
#define OPT_G BIT(9)

#endif
