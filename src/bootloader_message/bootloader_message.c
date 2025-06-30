/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Redundant AB-specific Bootloader Message Management
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#include "abc.h"
#include "log.h"
#include "crc32.h"
#include "device_io.h"
#include "bootloader_message.h"

#define MAX_ERRNO 4095
#define IS_ERR_VALUE(x) ((unsigned long)(x) >= (unsigned long)-MAX_ERRNO)
#define IS_ERR(ptr) IS_ERR_VALUE((unsigned long)(ptr))
#define PTR_ERR(ptr) ((long)(ptr))
#define ERR_PTR(err) ((void *)((long)(err)))

/* Value for AB-specific bootloader message validity */
enum bootloader_message_ab_valid {
	BOOTLOADER_MESSAGE_AB_INVALID,	/* No valid AB-specific bootloader message */
	BOOTLOADER_MESSAGE_AB_VALID,	/* First or only AB-specific bootloader message is valid */
	BOOTLOADER_MESSAGE_AB_REDUND,	/* Redundant AB-specific bootloader message is valid */
};

typedef struct bootloader_message_ab bl_msg_ab_t;
static unsigned long bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_INVALID;
static uint8_t bootloader_message_ab_flags = 0;

static int check_redund(const char *buf1, int buf1_read_fail,
		     const char *buf2, int buf2_read_fail)
{
	int crc1_ok = 0, crc2_ok = 0;
	uint32_t crc1, crc2;
	bl_msg_ab_t *tmp1, *tmp2;

	tmp1 = (bl_msg_ab_t *)buf1;
	tmp2 = (bl_msg_ab_t *)buf2;

	if (buf1_read_fail && buf2_read_fail) {
		puts("*** Error - No Valid AB-specific Bootloader Message Area found\n");
		return -EIO;
	} else if (buf1_read_fail || buf2_read_fail) {
		puts("*** Warning - some problems detected ");
		puts("reading AB-specific bootloader message; recovered successfully\n");
	}

	if (!buf1_read_fail) {
		crc1 = tmp1->crc32_le;
		log_debug("%s: CRC1 = 0x%08x\n", __func__, crc1);

		tmp1->crc32_le = 0; /* clear CRC for calculation */
		crc1_ok = crc32((void *)tmp1,
		            offsetof(bl_msg_ab_t, crc32_le)) == crc1;
	}

	if (!buf2_read_fail) {
		crc2 = tmp2->crc32_le;
		log_debug("%s: CRC2 = 0x%08x\n", __func__, crc2);

		tmp2->crc32_le = 0; /* clear CRC for calculation */
		crc2_ok = crc32((void *)tmp2,
		            offsetof(bl_msg_ab_t, crc32_le)) == crc2;
	}

	if (crc1_ok && !crc2_ok) {
		bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_VALID;
	} else if (!crc1_ok && crc2_ok) {
		bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_REDUND;
	} else {
		/* both ok or not okay - check serial */
		log_debug("%s: flags1 = %d, flags2 = %d\n",
		                    __func__, tmp1->flags, tmp2->flags);
		if (tmp1->flags == 255 && tmp2->flags == 0)
			bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_REDUND;
		else if (tmp2->flags == 255 && tmp1->flags == 0)
			bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_VALID;
		else if (tmp1->flags > tmp2->flags)
			bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_VALID;
		else if (tmp2->flags > tmp1->flags)
			bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_REDUND;
		else /* flags are equal - almost impossible */
			bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_VALID;
	}

	return 0;
}

static bl_msg_ab_t *load_redund(const char *buf1, int buf1_read_fail,
                         const char *buf2, int buf2_read_fail)
{
	bl_msg_ab_t *ep;
	int ret;

	ret = check_redund(buf1, buf1_read_fail, buf2, buf2_read_fail);
	if (ret == -EIO) {
		return ERR_PTR(-EIO);
	} else if (ret == -ENOMSG) {
		return ERR_PTR(-ENOMSG);
	}

	if (bootloader_message_ab_valid == BOOTLOADER_MESSAGE_AB_VALID)
		ep = (bl_msg_ab_t *)buf1;
	else
		ep = (bl_msg_ab_t *)buf2;

	bootloader_message_ab_flags = ep->flags;

	return ep;
}

int bootloader_message_ab_load(int fd1, int fd2, loff_t offset, struct bootloader_message_ab *buffer)
{
	char *buf1, *buf2;
	int buf1_read_fail = 0, buf2_read_fail = 0;
	bl_msg_ab_t *ep;

	if (fd1 < 0 || fd2 < 0 || !buffer) {
		log_error("Invalid arguments to bootloader_message_ab_load");
		return -EINVAL;
	}

	buf1 = malloc(sizeof(*buffer));
	if (!buf1) {
		log_error("Out of memory for buffer 1");
		return -ENOMEM;
	}

	buf2 = malloc(sizeof(*buffer));
	if (!buf2) {
		free(buf1);
		log_error("Out of memory for buffer 2");
		return -ENOMEM;
	}

	if (dev_read(fd1, offset, sizeof(*buffer), buf1) != sizeof(*buffer)) {
		log_error("Failed to read from fd1");
		buf1_read_fail = 1;
	}

	if (dev_read(fd2, offset, sizeof(*buffer), buf2) != sizeof(*buffer)) {
		log_error("Failed to read from fd2");
		buf2_read_fail = 1;
	}

	ep = load_redund(buf1, buf1_read_fail, buf2, buf2_read_fail);
	if (IS_ERR(ep)) {
		free(buf1);
		free(buf2);
		return PTR_ERR(ep);
	}

	memcpy(buffer, ep, sizeof(*buffer));
	free(buf1);
	free(buf2);
	return 0;
}

int bootloader_message_ab_store(int fd1, int fd2, loff_t offset,
                    struct bootloader_message_ab *buffer, bool sync)
{
	bl_msg_ab_t *ab_msg_new = NULL;
	int fd, copy = 0;

	if (fd1 < 0 || fd2 < 0 || !buffer) {
		log_error("Invalid arguments to bootloader_message_ab_store");
		return -EINVAL;
	}

	ab_msg_new = buffer;
	ab_msg_new->crc32_le = 0;
	ab_msg_new->crc32_le = crc32((void *)ab_msg_new, sizeof(bl_msg_ab_t));
	ab_msg_new->flags = ++bootloader_message_ab_flags; /* increase the serial */
	if (bootloader_message_ab_valid == BOOTLOADER_MESSAGE_AB_VALID)
		copy = 1;

	fd = (copy ? fd2 : fd1);
	if (dev_write(fd, offset, sizeof(bl_msg_ab_t), ab_msg_new) != sizeof(bl_msg_ab_t)) {
		log_error("Failed to write to fd '%d'", fd);
		return -EIO;
	}

	if (bootloader_message_ab_valid == BOOTLOADER_MESSAGE_AB_REDUND)
		bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_VALID;
	else
		bootloader_message_ab_valid = BOOTLOADER_MESSAGE_AB_REDUND;

	if (sync) {
		fd = (copy ? fd1 : fd2);
		if (dev_write(fd, offset, sizeof(bl_msg_ab_t), ab_msg_new) != sizeof(bl_msg_ab_t)) {
			log_error("Failed to write to fd '%d'", fd);
			return -EIO;
		}
	}

	return 0;
}