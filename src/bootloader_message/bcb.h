/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#ifndef BCB_H
#define BCB_H

#include <stdint.h>
#include <stddef.h>

// Define a maximum number of devices
#define MAX_DEVICES    10
#define MAX_ACTIONS    10

typedef enum {
	BCB_CLEAR,
	BCB_SET,
	BCB_TEST,
	BCB_DUMP,

	BCB_COUNT
} action_t;

typedef struct {
	action_t action;
	char field[32];
	char op[8];
	char value[64];
} action_params_t;

typedef struct {
    action_params_t actions[MAX_ACTIONS];
    int action_count;
} action_list_t;

#define BIT(x) (1UL << (x))

#define OPT_SET     BIT(0)
#define OPT_CLEAR   BIT(1)
#define OPT_TEST    BIT(2)
#define OPT_DUMP    BIT(3)

#endif
