/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */
#ifndef CRC32_H
#define CRC32_H

#include <stdint.h>
#include <stddef.h>

uint32_t crc32(const uint8_t *buf, size_t size);

#endif
