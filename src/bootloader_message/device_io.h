/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#ifndef DEVICE_IO_H
#define DEVICE_IO_H

#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <linux/fs.h>
#include <mtd/mtd-user.h>
#include "bootloader_message.h"

#define min_t(type, x, y) ({              \
	type __min1 = (x);                    \
	type __min2 = (y);                    \
	__min1 < __min2 ? __min1: __min2; })

#define ALIGN(x,a)		__ALIGN_MASK((x),(typeof(x))(a)-1)
#define ALIGN_DOWN(x, a)	ALIGN((x) - ((a) - 1), (a))
#define __ALIGN_MASK(x,mask)	(((x)+(mask))&~(mask))

int open_device(const char *device_path, int mode);
void close_device(int fd);

ssize_t read_at_offset(int fd, loff_t offset, size_t size, void *buffer);
ssize_t write_at_offset(int fd, loff_t offset, size_t size, const void *buffer);
int erase_at_offset(int fd, off_t offset, uint32_t erasesize);

bool is_nand(const struct mtd_info_user *mtd_info);
int mtd_block_isbad(int fd, loff_t offset);
int get_mtd_dev_info(int fd, struct mtd_info_user *mtd_info);
int get_blk_dev_info(int fd, uint64_t *devsz, uint32_t *blksz);

ssize_t dev_read(int fd, loff_t offset, size_t len, void *dst);
ssize_t dev_write(int fd, loff_t offset, size_t len, const void *src);

int bootloader_message_ab_load(int fd1, int fd2, loff_t offset, struct bootloader_message_ab *buffer);
int bootloader_message_ab_store(int fd1, int fd2, loff_t offset,
                                struct bootloader_message_ab *buffer, bool sync);

#endif // DEVICE_IO_H
