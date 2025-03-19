# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#

CROSS_COMPILE ?=
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -g
TARGET = abc_tool
SOURCES = abc_tool.c log.c crc32.c
OBJECTS = $(SOURCES:.c=.o)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJECTS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJECTS)
