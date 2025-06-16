# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
CFLAGS := -Wall -Wextra -g
INCLUDES := -I.

# Source and object files
SRCS_COMMON := log.c device_io.c crc32.c
OBJS_COMMON := $(SRCS_COMMON:.c=.o)

ABC_SRCS := abc_tool.c
BCB_SRCS := bcb_tool.c

ABC_OBJS := $(ABC_SRCS:.c=.o) $(OBJS_COMMON)
BCB_OBJS := $(BCB_SRCS:.c=.o) $(OBJS_COMMON)

TARGET_ABC := abc
TARGET_BCB := bcb

.PHONY: all clean

all: $(TARGET_ABC) $(TARGET_BCB)

$(TARGET_ABC): $(ABC_OBJS)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@ $(LDFLAGS)

$(TARGET_BCB): $(BCB_OBJS)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

clean:
	rm -f $(TARGET_ABC) $(TARGET_BCB) *.o
