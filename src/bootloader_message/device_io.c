/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#include "device_io.h"
#include "log.h"

#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <stdlib.h>

int open_device(const char *device_path, int mode)
{
	int fd = open(device_path, mode);
	if (fd < 0)
		log_error("Could not open device %s: %s",
		            device_path, strerror(errno));

	return fd;
}

void close_device(int fd)
{
	if (fd >= 0 && close(fd) < 0)
		log_error("Could not close device: %s",
		                  strerror(errno));
}

ssize_t read_at_offset(int fd, loff_t offset, size_t size, void *buffer)
{
	ssize_t read = pread(fd, buffer, size, offset);
	if (read < 0)
		log_error("Unable to read from offset 0x%llx: %s",
		            offset, strerror(errno));

	return read;
}

ssize_t write_at_offset(int fd, loff_t offset, size_t size, const void *buffer)
{
	ssize_t written = pwrite(fd, buffer, size, offset);
	if (written < 0)
		log_error("Unable to write to offset 0x%llx: %s",
		            offset, strerror(errno));

	return written;
}

int erase_at_offset(int fd, off_t offset, uint32_t erasesize)
{
	struct erase_info_user erase_info;
	erase_info.start = offset;
	erase_info.length = erasesize;

	if (ioctl(fd, MEMERASE, &erase_info) < 0) {
		log_error("Could not erase block at offset 0x%llx (size %u): %s",
		                  offset, erasesize, strerror(errno));
		return -errno;
	}

	log_debug("Block at offset 0x%llx (size %u) erased", offset, erasesize);
	return 0;
}

int get_blk_dev_info(int fd, uint64_t *devsz, uint32_t *blksz)
{
	if (devsz && ioctl(fd, BLKGETSIZE64, devsz) == -1) {
		log_error("Could not get device size: %s",
		              strerror(errno));
		return -errno;
	}
	if (blksz && ioctl(fd, BLKSSZGET, blksz) == -1) {
		log_error("Could not get block size: %s",
		              strerror(errno));
		return -errno;
	}
	return 0;
}

int mtd_block_isbad(int fd, loff_t offset)
{
	int ret = ioctl(fd, MEMGETBADBLOCK, &offset);
	if (ret < 0) {
		log_error("Can not find bad block at offset 0x%llx: %s",
		              offset, strerror(errno));
		return -errno;
	}
	return ret;
}

int get_mtd_dev_info(int fd, struct mtd_info_user *mtd_info)
{
	if (ioctl(fd, MEMGETINFO, mtd_info) == 0) {
		log_debug("MTD info: type %u, flags %u, size %u, erasesize %u, "
		            "writesize %u, oobsize %u",
		            mtd_info->type, mtd_info->flags, mtd_info->size,
		            mtd_info->erasesize, mtd_info->writesize, mtd_info->oobsize);
		return 0;
	}
	return -errno;
}

bool is_nand(const struct mtd_info_user *mtd_info)
{
	return mtd_type_is_nand_user(mtd_info);
}

static int skip_bad_blocks(int fd, struct mtd_info_user *mtd,
                            loff_t offset, size_t length,
                            loff_t from, loff_t *new_start)
{
	loff_t bbs_offset = offset;
	loff_t start, end;

	while (bbs_offset < from) {
		if (mtd_block_isbad(fd, bbs_offset)) {
			log_warn("skip_bad_blocks: bad block at 0x%llx\n",
			            ALIGN_DOWN(bbs_offset, mtd->erasesize));
			from += mtd->erasesize;
		}
		bbs_offset += mtd->erasesize;
	}

	end = offset + length;
	for (start = from; start < end; start += mtd->writesize) {
		if (mtd_block_isbad(fd, start)) {
			log_warn("skip_bad_blocks: skipping bad block at 0x%llx\n",
			         ALIGN_DOWN(start, mtd->erasesize));
			start += mtd->erasesize - mtd->writesize;
			continue;
		}
		break;
	}

	if (start >= end) {
		log_error("skip_bad_blocks: no valid blocks found\n");
		return -EIO;
	}

	*new_start = start;
	return 0;
}

static int virt_to_phys(int fd, struct mtd_info_user *mtd,
                         loff_t from, loff_t *new_start)
{
	int ret;

	if (!is_nand(mtd)) {
		*new_start = from;
		log_debug("orignal from: 0x%llx new from: 0x%llx\n", from, *new_start);
		return 0;
	}

	ret = skip_bad_blocks(fd, mtd, 0, mtd->size, from, new_start);
	if (ret < 0) {
		log_error("Unable to skip bad blocks: %s", strerror(-ret));
		return ret;
	}

	log_debug("%s: original from: 0x%llx new from: 0x%llx\n",
	             __func__, from, *new_start);
	return 0;
}

static ssize_t mtd_read(int fd, loff_t offset, size_t size, void *buffer)
{
	ssize_t bytes_read = read_at_offset(fd, offset, size, buffer);
	if (bytes_read < 0) {
		log_error("Could not read from MTD device at offset 0x%llx: %s",
		               offset, strerror(errno));
		return bytes_read;
	}

	if ((size_t)bytes_read != size) {
		log_warn("%s: Wrong read length at 0x%llx (expected %llu, got %zu)\n",
		             __func__, offset, size, bytes_read);
		return -EIO;
	}

	return bytes_read;
}

static ssize_t mtd_write(int fd, loff_t offset, size_t length, const void *buffer)
{
	ssize_t bytes_written = write_at_offset(fd, offset, length, buffer);
	if (bytes_written < 0) {
		log_error("Could not write to MTD device at offset 0x%llx: %s",
		              offset, strerror(errno));
		return bytes_written;
	}

	if ((size_t)bytes_written != length) {
		log_warn("%s: Wrong write length at 0x%llx (expected %llu, written %zu)\n",
		          __func__, offset, length, bytes_written);
		return -EIO;
	}

	return bytes_written;
}

static int mtd_erase(int fd, loff_t start, size_t length)
{
	int ret;

	ret = erase_at_offset(fd, start, length);
	if (ret < 0)
		return ret;

	return 0;
}

static int mtd_erase_write(int fd, struct mtd_info_user *mtd, loff_t start, const void *src)
{
	int ret;

	ret = mtd_erase(fd, start, mtd->erasesize);
	if (ret < 0) {
		log_error("Unable to erase block at offset 0x%llx: %s",
		               start, strerror(-ret));
		return ret;
	}

	ssize_t written = mtd_write(fd, start, mtd->erasesize, src);
	if (written != mtd->erasesize) {
		log_error("%s: Wrong mtd write length at 0x%llx (expected %llu, written %zu)\n",
		             __func__, start, mtd->erasesize, written);
		return -EIO;
	}

	return written;
}

static ssize_t mtd_read_bbs(int fd, struct mtd_info_user *mtd,
                            loff_t offset, size_t size,
                            void *dst)
{
	ssize_t sect_size = mtd->writesize;
	loff_t cur = offset;
	size_t bytes_read = 0;

	while (bytes_read < size) {
		loff_t phys_offset;
		int ret = virt_to_phys(fd, mtd, cur, &phys_offset);
		if (ret < 0) {
			log_error("%s: virt_to_phys failed: %s",
			            __func__, strerror(-ret));
			return ret;
		}

		size_t cur_size = min_t(size_t, size - bytes_read, sect_size);
		size_t read_len = mtd_read(fd, phys_offset, cur_size, dst);

		if (read_len != cur_size) {
			log_error("%s: Wrong read length at 0x%llx (expected %llu, got %zu)\n",
			             __func__, phys_offset, cur_size, read_len);
			return -EIO;
		}

		cur += cur_size;
		dst += cur_size;
		bytes_read += cur_size;
	}

	log_debug("Reading %zu bytes from offset 0x%llx",
	                      bytes_read, offset);
	return bytes_read;
}

static ssize_t mtd_write_bbs(int fd, struct mtd_info_user *mtd,
                             loff_t offset, size_t size,
                             const void *src)
{
	loff_t cur = offset, todo = size;
	size_t bytes_written = 0;
	char *buf = NULL;
	int ret = 0;

	buf = malloc(mtd->erasesize);
	if (!buf) {
		log_error("Out of memory");
		return -ENOMEM;
	}

	while (todo > 0) {
		loff_t phys_offset, erase_start;
		loff_t offset;
		size_t cur_size;
		size_t written;

		ret = virt_to_phys(fd, mtd, cur, &phys_offset);
		if (ret < 0) {
			log_error("%s: virt_to_phys failed: %s",
			                __func__, strerror(-ret));
			goto out;
		}

		erase_start = ALIGN_DOWN(phys_offset, mtd->erasesize);
		offset = phys_offset - erase_start;
		cur_size = min_t(size_t, mtd->erasesize - offset, todo);
		ssize_t read_len = mtd_read(fd, erase_start, mtd->erasesize, buf);

		if (read_len != mtd->erasesize) {
			log_error("%s: Wrong mtd read length at 0x%llx (expected %llu, got %zu)\n",
			           __func__, cur, mtd->erasesize, read_len);
			ret = -EIO;
			goto out;
		}

		memcpy(buf + offset, src, cur_size);

		written = mtd_erase_write(fd, mtd, erase_start, buf);

		if (written != mtd->erasesize) {
			log_error("%s: Wrong mtd write length at 0x%llx (expected %llu, written %zu)\n",
			           __func__, cur, mtd->erasesize, written);
			ret = -EIO;
			goto out;
		}

		todo -= cur_size;
		cur += cur_size;
		src += cur_size;
		bytes_written += cur_size;
	}

out:
	free(buf);

	if (ret)
		return ret;

	return bytes_written;
}

ssize_t dev_read(int fd, loff_t offset, size_t len, void *dst)
{
	struct mtd_info_user mtd_info;
	bool is_mtd = false;

	if (get_mtd_dev_info(fd, &mtd_info) == 0)
		is_mtd = true;

	if (is_mtd)
		return mtd_read_bbs(fd, &mtd_info, offset, len, dst);
	else
		return read_at_offset(fd, offset, len, dst);

	return -ENOTSUP;
}

ssize_t dev_write(int fd, loff_t offset, size_t len, const void *src)
{
	struct mtd_info_user mtd_info;
	bool is_mtd = false;

	if (get_mtd_dev_info(fd, &mtd_info) == 0)
		is_mtd = true;

	if (is_mtd)
		return mtd_write_bbs(fd, &mtd_info, offset, len, src);
	else
		return write_at_offset(fd, offset, len, src);

	return -ENOTSUP;
}
