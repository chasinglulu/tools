// SPDX-License-Identifier: GPL-2.0+
/*
 * a versatile UART utility for forwarding, receiving, sending data, and loopback testing.
 *
 * Copyright (C) 2025 Charleye <wangkart@aliyun.com>
 *
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <termios.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>

#define BUFFER_SIZE 256

typedef enum {
    MODE_UNSET,
    MODE_FORWARD,
    MODE_RECEIVE,
    MODE_SEND,
    MODE_LOOPBACK
} op_mode_t;

typedef enum {
    LL_ERR = 0,
    LL_WARN,
    LL_INFO,
    LL_DEBUG
} log_level_t;

static log_level_t current_log_level = LL_INFO;

void app_log(log_level_t level, const char *format, ...) {
    if (level > current_log_level) {
        return;
    }

    FILE *out_stream = stdout;
    const char *level_str = "";

    switch (level) {
        case LL_ERR:
            level_str = "ERROR: ";
            out_stream = stderr;
            break;
        case LL_WARN:
            level_str = "WARN:  ";
            out_stream = stderr;
            break;
        case LL_INFO:
            level_str = "INFO:  ";
            break;
        case LL_DEBUG:
            level_str = "DEBUG: ";
            break;
    }

    fprintf(out_stream, "%s", level_str);

    va_list args;
    va_start(args, format);
    vfprintf(out_stream, format, args);
    va_end(args);
    fprintf(out_stream, "\n");
}


/*
 * @brief Configures a serial port.
 * @param fd File descriptor of the serial port.
 * @param speed Baud rate.
 * @param databits Data bits (5, 6, 7, or 8).
 * @param stopbits Stop bits (1 or 2).
 * @param parity Parity ('N', 'E', 'O').
 * @return 0 on success, -1 on failure.
 */
int uart_config(int fd, int speed, int databits, int stopbits, int parity)
{
    struct termios options;
    if (tcgetattr(fd, &options) !=	0) {
        app_log(LL_ERR, "tcgetattr failed: %s", strerror(errno));
        return(-1);
    }

    /* Set serial communication speed */
    speed_t baud_const;
    switch (speed) {
        case 1200:    baud_const = B1200;    break;
        case 2400:    baud_const = B2400;    break;
        case 4800:    baud_const = B4800;    break;
        case 9600:    baud_const = B9600;    break;
        case 19200:   baud_const = B19200;   break;
        case 38400:   baud_const = B38400;   break;
        case 57600:   baud_const = B57600;   break;
        case 115200:  baud_const = B115200;  break;
        case 230400:  baud_const = B230400;  break;
        case 460800:  baud_const = B460800;  break;
        case 500000:  baud_const = B500000;  break;
        case 576000:  baud_const = B576000;  break;
        case 921600:  baud_const = B921600;  break;
        case 1000000: baud_const = B1000000; break;
        case 1152000: baud_const = B1152000; break;
        case 1500000: baud_const = B1500000; break;
        case 2000000: baud_const = B2000000; break;
        case 2500000: baud_const = B2500000; break;
        case 3000000: baud_const = B3000000; break;
        case 3500000: baud_const = B3500000; break;
        case 4000000: baud_const = B4000000; break;
        default:
            app_log(LL_ERR, "Unsupported speed %d", speed);
            return (-1);
    }
    cfsetispeed(&options, baud_const);
    cfsetospeed(&options, baud_const);

    /* Set data bits */
    options.c_cflag &= ~CSIZE;
    switch (databits) {
        case 5: options.c_cflag |= CS5; break;
        case 6: options.c_cflag |= CS6; break;
        case 7: options.c_cflag |= CS7; break;
        case 8: options.c_cflag |= CS8; break;
        default:
            app_log(LL_ERR, "Unsupported databits %d", databits);
            return (-1);
    }

    /* Set parity bit */
    switch (parity) {
        case 'n':
        case 'N':	/* No parity */
            options.c_cflag &= ~PARENB;
            options.c_iflag &= ~INPCK;
            break;
        case 'o':
        case 'O':	/* Odd parity */
            options.c_cflag |= (PARODD | PARENB);
            options.c_iflag |= INPCK;
            break;
        case 'e':
        case 'E':	/* Even parity */
            options.c_cflag |= PARENB;
            options.c_cflag &= ~PARODD;
            options.c_iflag |= INPCK;
            break;
        default:
            app_log(LL_ERR, "Unsupported parity %c", parity);
            return (-1);
    }

    /* Set stop bits */
    switch (stopbits) {
        case 1: options.c_cflag &= ~CSTOPB; break;
        case 2: options.c_cflag |= CSTOPB;  break;
        default:
            app_log(LL_ERR, "Unsupported stopbits %d", stopbits);
            return (-1);
    }

    /* Set local mode and control options */
    options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    options.c_oflag &= ~OPOST;

    options.c_cflag |= (CLOCAL | CREAD);
    options.c_cflag &= ~CRTSCTS;	/* No hardware flow control */
    options.c_iflag &= ~(IXON | IXOFF | IXANY); /* No software flow control */


    options.c_cc[VTIME] = 1; 	/* Set read timeout, unit 100ms */
    options.c_cc[VMIN] = 0; 	/* Set minimum read bytes, 0 means non-blocking */

    /* Clear buffer */
    tcflush(fd,TCIFLUSH);

    if (tcsetattr(fd,TCSANOW,&options) != 0) {
        app_log(LL_ERR, "tcsetattr failed: %s", strerror(errno));
        return (-1);
    }

    return (0);
}

void print_usage(void) {
    printf("Usage: uart_tool -M <mode> [options]\n\n"
            "DESCRIPTION:\n"
            "  A versatile UART utility that can forward data between two serial ports,\n"
            "  receive data from a serial port, send data to a serial port, or test\n"
            "  a loopback connection between two ports.\n\n"
            "REQUIRED ARGUMENTS FOR ALL MODES:\n"
            "  -M <mode>          Operation mode. Must be one of: 'forward', 'recv', 'send', 'loopback'.\n"
            "  -b <baud_rate>     Baud rate for serial communication (e.g., 9600, 115200).\n\n"
            "OPTIONS FOR 'forward' MODE:\n"
            "  -r <recv_device>   Path to the receiving serial device (e.g., /dev/ttyS0).\n"
            "  -s <send_device>   Path to the sending serial device (e.g., /dev/ttyS1).\n\n"
            "OPTIONS FOR 'recv' MODE:\n"
            "  -d <device>        Path to the serial device to receive from.\n\n"
            "OPTIONS FOR 'send' MODE:\n"
            "  -d <device>        Path to the serial device to send to.\n"
            "  -D <data_string>   The string of data to send.\n\n"
            "OPTIONS FOR 'loopback' MODE:\n"
            "  -r <device1_path>  Path to the first UART device (will receive data).\n"
            "  -s <device2_path>  Path to the second UART device (will send data),\n"
            "                     physically looped back to device1.\n"
            "  -i <input_file>    Path to the file whose content will be sent.\n"
            "  -o <output_file>   Path to the file where received data will be written.\n\n"
            "OTHER OPTIONS:\n"
            "  -L <level>         Log level: 0 (error), 1 (warn), 2 (info - default), 3 (debug).\n"
            "                     Can also use names: 'error', 'warn', 'info', 'debug'.\n"
            "  -h                 Display this help message and exit.\n\n"
            "EXAMPLES:\n"
            "  Forward mode:\n"
            "    uart_tool -M forward -r /dev/ttyS0 -s /dev/ttyS1 -b 115200\n"
            "  Receive mode:\n"
            "    uart_tool -M recv -d /dev/ttyUSB0 -b 9600 -L debug\n"
            "  Send mode:\n"
            "    uart_tool -M send -d /dev/ttyACM0 -b 115200 -D \"Hello UART!\"\n"
            "  Loopback mode (fixed string):\n"
            "    uart_tool -M loopback -r /dev/ttyS0 -s /dev/ttyS1 -b 115200\n"
            "  Loopback mode (file based):\n"
            "    uart_tool -M loopback -r /dev/ttyS0 -s /dev/ttyS1 -b 115200 -i send.txt -o recv.txt\n");
}

/*
 * @brief Opens and configures a serial device.
 * @param dev_path Path to the serial device.
 * @param baud Baud rate for communication.
 * @return File descriptor on success, -1 on failure.
 */
static int open_and_configure_device(const char *dev_path, int baud) {
    int fd;

    if (dev_path == NULL) {
        app_log(LL_ERR, "Device name is NULL.");
        return -1;
    }

    fd = open(dev_path, O_RDWR | O_NOCTTY | O_NDELAY);
    if (fd < 0) {
        app_log(LL_ERR, "Opening device %s: %s", dev_path, strerror(errno));
        return -1;
    }
    fcntl(fd, F_SETFL, 0);
    app_log(LL_INFO, "Device %s opened successfully.", dev_path);

    if (uart_config(fd, baud, 8, 1, 'n') == -1) {
        // uart_config already logs its specific error
        app_log(LL_ERR, "Configuring device %s (baud: %d) failed.",
                dev_path, baud);
        close(fd);
        return -1;
    }
    app_log(LL_INFO, "Device %s configured to %d baud, 8N1.",
            dev_path, baud);
    return fd;
}

static int handle_forward_mode(const char *recv_dev_path,
                               const char *send_dev_path,
                               int baud) {
    int fd_recv = -1, fd_send = -1;
    int n_read = 0, n_written = 0;
    char buffer[BUFFER_SIZE];

    if (recv_dev_path == NULL || send_dev_path == NULL) {
        app_log(LL_ERR,
                "'forward' mode: receive and send device names required.");
        return -1;
    }

    app_log(LL_DEBUG,
            "Attempting to open receiving device %s for forward mode...",
            recv_dev_path);
    fd_recv = open_and_configure_device(recv_dev_path, baud);
    if (fd_recv < 0) {
        return -1;
    }

    app_log(LL_DEBUG,
            "Attempting to open sending device %s for forward mode...",
            send_dev_path);
    fd_send = open_and_configure_device(send_dev_path, baud);
    if (fd_send < 0) {
        close(fd_recv);
        return -1;
    }

    app_log(LL_INFO, "Starting data forwarding from %s to %s...",
            recv_dev_path, send_dev_path);
    while(1) {
        memset(buffer, 0, BUFFER_SIZE);
        n_read = read(fd_recv, buffer, BUFFER_SIZE -1);
        if (n_read > 0) {
            app_log(LL_DEBUG, "Read %d bytes from %s: \"%.*s\"",
                    n_read, recv_dev_path, n_read, buffer);
            n_written = write(fd_send, buffer, n_read);
            if (n_written < 0) {
                app_log(LL_ERR, "Writing to send_device %s: %s",
                        send_dev_path, strerror(errno));
                break;
            }
            app_log(LL_DEBUG, "Wrote %d bytes to %s",
                    n_written, send_dev_path);
            if (n_written < n_read) {
                app_log(LL_WARN,
                        "Not all bytes written to send_device %s (%d/%d)",
                        send_dev_path, n_written, n_read);
            }
        } else if (n_read == 0) {
            app_log(LL_DEBUG, "Read 0 bytes from %s, retrying...",
                    recv_dev_path);
            // usleep(10000);
        } else {
            app_log(LL_ERR, "Reading from recv_device %s: %s",
                    recv_dev_path, strerror(errno));
            break;
        }
    }
    app_log(LL_INFO, "Closing forward devices...");
    close(fd_recv);
    close(fd_send);
    return 0;
}

static int handle_receive_mode(const char *dev_path, int baud) {
    int fd_dev = -1;
    int n_read = 0, n_written = 0;
    char buffer[BUFFER_SIZE];

    if (dev_path == NULL) {
        app_log(LL_ERR, "'recv' mode: device name required.");
        return -1;
    }

    app_log(LL_DEBUG,
            "Attempting to open device %s for receive mode...", dev_path);
    fd_dev = open_and_configure_device(dev_path, baud);
    if (fd_dev < 0) {
        return -1;
    }

    app_log(LL_INFO,
            "Starting to receive data from %s (Ctrl+C to stop)...",
            dev_path);
    while(1) {
        memset(buffer, 0, BUFFER_SIZE);
        n_read = read(fd_dev, buffer, BUFFER_SIZE -1);
        if (n_read > 0) {
            app_log(LL_DEBUG, "Read %d bytes from %s: \"%.*s\"",
                    n_read, dev_path, n_read, buffer);
            // Write to standard output directly, not through app_log for raw data
            n_written = write(STDOUT_FILENO, buffer, n_read);
            if (n_written < 0) {
                app_log(LL_ERR, "Writing to stdout: %s", strerror(errno));
                break;
            }
        } else if (n_read == 0) {
            app_log(LL_DEBUG, "Read 0 bytes from %s, retrying...",
                    dev_path);
            // usleep(10000);
        } else {
            app_log(LL_ERR, "Reading from device %s: %s",
                    dev_path, strerror(errno));
            break;
        }
    }
    app_log(LL_INFO, "\nClosing receive device %s...", dev_path);
    close(fd_dev);
    return 0;
}

static int handle_send_mode(const char *dev_path, int baud,
                              const char *data) {
    int fd_dev = -1;
    int n_written = 0;

    if (dev_path == NULL) {
        app_log(LL_ERR, "'send' mode: device name required.");
        return -1;
    }
    if (data == NULL) {
        app_log(LL_ERR,
                "'send' mode: data to send (-D) required.");
        return -1;
    }

    app_log(LL_DEBUG,
            "Attempting to open device %s for send mode...", dev_path);
    fd_dev = open_and_configure_device(dev_path, baud);
    if (fd_dev < 0) {
        return -1;
    }
    
    app_log(LL_INFO, "Sending data to %s: \"%s\"",
            dev_path, data);
    n_written = write(fd_dev, data, strlen(data));
    if (n_written < 0) {
        app_log(LL_ERR, "Writing to device %s: %s",
                dev_path, strerror(errno));
    } else {
        app_log(LL_INFO, "Sent %d bytes to %s.",
                n_written, dev_path);
        if ((size_t)n_written < strlen(data)) {
             app_log(LL_WARN,
                     "Not all data sent to %s (%d/%zu bytes).",
                     dev_path, n_written, strlen(data));
        }
    }
    // usleep(100000);
    app_log(LL_INFO, "Closing send device %s...", dev_path);
    close(fd_dev);
    return 0;
}

/*
 * @brief Arguments for the loopback receiving thread.
 *
 * Members:
 *   fd_recv: Receiving UART file descriptor.
 *   is_file_mode: 1 for file mode, 0 for fixed string mode.
 *
 *   File mode specific:
 *     output_file_fd: Output file descriptor.
 *     file_bytes_written: Pointer to store total bytes written to output file.
 *
 *   Fixed string mode specific:
 *     fixed_buf: Buffer for UART data.
 *     fixed_buf_size: Size of fixed_buf.
 *     expected_data: Expected data string.
 *     expected_len: Length of expected_data.
 *     fixed_bytes_read: Pointer to store actual bytes read from UART.
 *     fixed_match: Pointer to store data comparison result (1 for match, 0 for mismatch/error).
 */
typedef struct {
    int fd_recv;
    int is_file_mode;

    /* For file mode */
    int output_file_fd;
    long *file_bytes_written;

    /* For fixed string mode */
    char *fixed_buf;
    int fixed_buf_size;
    const char *expected_data;
    int expected_len;
    int *fixed_bytes_read;
    int *fixed_match;
} loopback_thread_args_t;

// Thread function for receiving data in loopback mode
static void *loopback_rx_thread(void *arg) {
    loopback_thread_args_t *args = (loopback_thread_args_t *)arg;
    char temp_buffer[BUFFER_SIZE];
    ssize_t uart_bytes_read;

    if (args->is_file_mode) {
        // File mode: read from UART and write to output file
        long current_total_written = 0;
        ssize_t file_bytes_out;
        app_log(LL_DEBUG,
                "Loopback RX thread (File Mode): Started. "
                "Reading from UART fd %d, writing to output file fd %d.",
                args->fd_recv, args->output_file_fd);

        while ((uart_bytes_read = read(args->fd_recv, temp_buffer, BUFFER_SIZE)) > 0) {
            app_log(LL_DEBUG, "Loopback RX thread (File Mode): Read %zd bytes from UART.",
                    uart_bytes_read);
            file_bytes_out = write(args->output_file_fd, temp_buffer, uart_bytes_read);
            if (file_bytes_out < 0) {
                app_log(LL_ERR,
                        "Loopback RX thread (File Mode): Writing to output file fd %d: %s",
                        args->output_file_fd, strerror(errno));
                current_total_written = -1;
                break;
            }
            if (file_bytes_out < uart_bytes_read) {
                app_log(LL_WARN,
                        "Loopback RX thread (File Mode): Partial write to "
                        "output file fd %d (%zd/%zd bytes).",
                        args->output_file_fd, file_bytes_out, uart_bytes_read);
            }
            current_total_written += file_bytes_out;
        }
        if (uart_bytes_read < 0) {
            app_log(LL_ERR,
                    "Loopback RX thread (File Mode): Reading from UART fd %d: %s",
                    args->fd_recv, strerror(errno));
            current_total_written = -1;
        }
        *(args->file_bytes_written) = current_total_written;
        app_log(LL_DEBUG,
                "Loopback RX thread (File Mode): Finished. "
                "Total bytes written to output file: %ld.",
                current_total_written);
    } else {
        // Fixed string mode: read from UART and compare in memory
        app_log(LL_DEBUG,
                "Loopback RX thread (Fixed String Mode): "
                "Attempting to read from fd %d.",
                args->fd_recv);
        memset(args->fixed_buf, 0, args->fixed_buf_size);
        uart_bytes_read = read(args->fd_recv, args->fixed_buf, args->fixed_buf_size - 1);

        if (uart_bytes_read < 0) {
            app_log(LL_ERR,
                    "Loopback RX thread (Fixed String Mode): Reading from fd %d: %s",
                    args->fd_recv, strerror(errno));
            *(args->fixed_bytes_read) = -1;
            *(args->fixed_match) = 0;
            pthread_exit(NULL);
            return NULL;
        }

        *(args->fixed_bytes_read) = uart_bytes_read;
        if (uart_bytes_read > 0) {
            args->fixed_buf[uart_bytes_read] = '\0';
        }
        app_log(LL_DEBUG,
                "Loopback RX thread (Fixed String Mode): Read %zd bytes: \"%.*s\"",
                uart_bytes_read, (int)uart_bytes_read, args->fixed_buf);

        if (uart_bytes_read == args->expected_len &&
            strncmp(args->expected_data, args->fixed_buf, args->expected_len) == 0) {
            *(args->fixed_match) = 1;
        } else {
            *(args->fixed_match) = 0;
        }
        app_log(LL_DEBUG, "Loopback RX thread (Fixed String Mode): Finished.");
    }

    pthread_exit(NULL);
    return NULL;
}

// CRC32 implementation
static uint32_t crc_table[256];
static int crc_table_initialized = 0;

static void generate_crc_table(void) {
    uint32_t polynomial = 0xEDB88320; // Reversed polynomial
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (size_t j = 0; j < 8; j++) {
            if (c & 1) {
                c = polynomial ^ (c >> 1);
            } else {
                c >>= 1;
            }
        }
        crc_table[i] = c;
    }
    crc_table_initialized = 1;
}

/**
 * @brief Calculates the CRC32 checksum of a file.
 * @param filepath Path to the file.
 * @param crc_out  Pointer to store the calculated CRC32 checksum.
 * @return 0 on success, -1 on error (e.g., file not found, read error).
 */
static int calculate_file_crc32(const char *filepath, uint32_t *crc_out) {
    if (!crc_table_initialized) {
        generate_crc_table();
    }

    FILE *fp = NULL;
    unsigned char buffer[BUFFER_SIZE];
    size_t bytes_read;
    uint32_t crc = 0xFFFFFFFF;

    fp = fopen(filepath, "rb");
    if (!fp) {
        app_log(LL_ERR, "Cannot open file %s: %s", filepath, strerror(errno));
        return -1;
    }

    while ((bytes_read = fread(buffer, 1, BUFFER_SIZE, fp)) > 0) {
        for (size_t i = 0; i < bytes_read; i++) {
            crc = crc_table[(crc ^ buffer[i]) & 0xFF] ^ (crc >> 8);
        }
    }

    if (ferror(fp)) {
        app_log(LL_ERR, "Reading file %s: %s", filepath, strerror(errno));
        fclose(fp);
        return -1;
    }

    fclose(fp);
    *crc_out = crc ^ 0xFFFFFFFF;
    return 0;
}

// Compare CRC32 checksums of two files
static int compare_files(const char *file1_path, const char *file2_path) {
    uint32_t crc1, crc2;

    app_log(LL_DEBUG, "Calculating CRC32 for %s...", file1_path);
    if (calculate_file_crc32(file1_path, &crc1) != 0) {
        return -1;
    }
    app_log(LL_DEBUG, "CRC32 for %s: 0x%08x", file1_path, crc1);

    app_log(LL_DEBUG, "Calculating CRC32 for %s...", file2_path);
    if (calculate_file_crc32(file2_path, &crc2) != 0) {
        return -1;
    }
    app_log(LL_DEBUG, "CRC32 for %s: 0x%08x", file2_path, crc2);

    if (crc1 == crc2) {
        app_log(LL_DEBUG, "CRC32 checksums for %s and %s match.", file1_path, file2_path);
        return 0;
    } else {
        app_log(LL_DEBUG, "CRC32 checksums for %s and %s do not match. (0x%08x vs 0x%08x)",
                file1_path, file2_path, crc1, crc2);
        return -1;
    }
}

/*
 * @brief Handles UART loopback testing.
 *
 * Sends data from one UART device (or an input file) to another UART device
 * and verifies the received data against the sent data (or writes to an output file).
 * Supports both fixed string and file-based loopback tests.
 *
 * @return 0 on success (data matches), -1 on failure or error.
 */
static int handle_loopback_mode(const char *dev_r_path, const char *dev_s_path, int baud,
                                const char *input_fpath, const char *output_fpath) {
    int fd_recv = -1, fd_send = -1;
    int input_fd = -1, output_fd = -1;
    char file_tx_buf[BUFFER_SIZE];
    char fixed_rx_buf[BUFFER_SIZE];
    const char *fixed_tx_data = "UART Loopback Test (Fixed String) 12345!@#$%\n";
    int fixed_tx_len = strlen(fixed_tx_data);
    ssize_t bytes_from_file, uart_bytes_out;
    long total_sent_bytes = 0;
    long total_recv_file_bytes = 0;
    pthread_t recv_tid;
    loopback_thread_args_t th_args = {0};
    int final_ret = -1;

    int is_file_mode = (input_fpath && output_fpath);

    app_log(LL_INFO, "Starting loopback test: send on %s, receive on %s at %d baud.",
            dev_s_path, dev_r_path, baud);
    if (is_file_mode) {
        app_log(LL_INFO, "File mode: input '%s', output '%s'.", input_fpath, output_fpath);
    } else {
        app_log(LL_INFO, "Fixed string mode.");
    }

    app_log(LL_DEBUG, "Opening receiving device (from -r): %s", dev_r_path);
    fd_recv = open_and_configure_device(dev_r_path, baud);
    if (fd_recv < 0) goto cleanup;

    /*
     * Configure fd_recv for loopback mode with a specific timeout.
     * uart_config sets VMIN=0, VTIME=1 (0.1s). This might be too short,
     * causing the receiver to exit prematurely or, if VMIN=1 was used, to hang.
     * Setting VMIN=0 and a moderate VTIME (e.g., 0.5s-1s) allows the read loop
     * to terminate if no data arrives after the sender is done.
     */
    struct termios options_recv_loopback;
    if (tcgetattr(fd_recv, &options_recv_loopback) == 0) {
        options_recv_loopback.c_cc[VMIN] = 0;
        options_recv_loopback.c_cc[VTIME] = 5;
        if (tcsetattr(fd_recv, TCSANOW, &options_recv_loopback) != 0) {
            app_log(LL_WARN, "Could not set VMIN=0, VTIME=5 for fd_recv %s: %s. Loopback test may be unreliable.",
                    dev_r_path, strerror(errno));
        } else {
            app_log(LL_DEBUG, "Set VMIN=0, VTIME=5 for fd_recv %s for timed read in loopback.", dev_r_path);
        }
    } else {
        app_log(LL_WARN, "Could not tcgetattr for fd_recv %s to set VTIME: %s. Loopback test may be unreliable.",
                dev_r_path, strerror(errno));
    }

    app_log(LL_DEBUG, "Opening sending device (from -s): %s", dev_s_path);
    fd_send = open_and_configure_device(dev_s_path, baud);
    if (fd_send < 0) goto cleanup;

    th_args.fd_recv = fd_recv;
    th_args.is_file_mode = is_file_mode;

    if (is_file_mode) {
        input_fd = open(input_fpath, O_RDONLY);
        if (input_fd < 0) {
            app_log(LL_ERR, "Cannot open input file %s: %s", input_fpath, strerror(errno));
            goto cleanup;
        }
        output_fd = open(output_fpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (output_fd < 0) {
            app_log(LL_ERR, "Cannot open/create output file %s: %s", output_fpath, strerror(errno));
            goto cleanup;
        }
        th_args.output_file_fd = output_fd;
        th_args.file_bytes_written = &total_recv_file_bytes;
    } else {
        th_args.fixed_buf = fixed_rx_buf;
        th_args.fixed_buf_size = BUFFER_SIZE;
        th_args.expected_data = fixed_tx_data;
        th_args.expected_len = fixed_tx_len;
        
        static int actual_fixed_read;
        static int match_fixed_res;
        th_args.fixed_bytes_read = &actual_fixed_read;
        th_args.fixed_match = &match_fixed_res;
    }

    app_log(LL_DEBUG, "Creating loopback receiving thread...");
    if (pthread_create(&recv_tid, NULL, loopback_rx_thread, &th_args) != 0) {
        app_log(LL_ERR, "Failed to create loopback receiving thread: %s", strerror(errno));
        goto cleanup;
    }

    usleep(100000);

    if (is_file_mode) {
        app_log(LL_INFO, "Sending content of %s to %s...", input_fpath, dev_s_path);
        total_sent_bytes = 0;
        while ((bytes_from_file = read(input_fd, file_tx_buf, BUFFER_SIZE)) > 0) {
            uart_bytes_out = write(fd_send, file_tx_buf, bytes_from_file);
            if (uart_bytes_out < 0) {
                app_log(LL_ERR, "Writing to UART %s: %s", dev_s_path, strerror(errno));
                pthread_cancel(recv_tid);
                pthread_join(recv_tid, NULL);
                goto cleanup;
            }
            app_log(LL_DEBUG, "Loopback TX (File Mode): Wrote %zd bytes to UART.", uart_bytes_out);
            if (uart_bytes_out < bytes_from_file) {
                app_log(LL_WARN, "Partial write to UART %s (%zd/%zd bytes).", dev_s_path, uart_bytes_out, bytes_from_file);
            }
            total_sent_bytes += uart_bytes_out;
        }
        if (bytes_from_file < 0) {
            app_log(LL_ERR, "Reading from input file %s: %s", input_fpath, strerror(errno));
            pthread_cancel(recv_tid);
            pthread_join(recv_tid, NULL);
            goto cleanup;
        }
        app_log(LL_INFO, "Finished sending %ld bytes from %s.", total_sent_bytes, input_fpath);
    } else {
        app_log(LL_INFO, "Write %d bytes to %s: \"%s\"", fixed_tx_len, dev_s_path, fixed_tx_data);
        uart_bytes_out = write(fd_send, fixed_tx_data, fixed_tx_len);
        if (uart_bytes_out < 0) {
            app_log(LL_ERR, "Writing fixed string to %s: %s", dev_s_path, strerror(errno));
            pthread_cancel(recv_tid);
            pthread_join(recv_tid, NULL);
            goto cleanup;
        }
        if (uart_bytes_out < fixed_tx_len) {
            app_log(LL_WARN, "Partial write of fixed string to %s (%zd/%d bytes).", dev_s_path, uart_bytes_out, fixed_tx_len);
        }
        app_log(LL_DEBUG, "Wrote %zd bytes of fixed string to %s.", uart_bytes_out, dev_s_path);
        total_sent_bytes = uart_bytes_out;
    }

    if (fd_send >= 0) {
        app_log(LL_DEBUG, "Draining sending UART fd %d to ensure all data is transmitted.", fd_send);
        if (tcdrain(fd_send) != 0) {
            app_log(LL_WARN, "tcdrain failed for sending UART fd %d (%s): %s. Data might be lost.",
                    fd_send, dev_s_path, strerror(errno));
        }
        app_log(LL_DEBUG, "Closing sending UART fd %d to signal EOF.", fd_send);
        close(fd_send);
        fd_send = -1;
    }

    app_log(LL_DEBUG, "Waiting for loopback receiving thread to complete...");
    if (pthread_join(recv_tid, NULL) != 0) {
        app_log(LL_ERR, "Failed to join loopback receiving thread: %s", strerror(errno));
        goto cleanup;
    }

    if (is_file_mode) {
        long recv_file_bytes = *th_args.file_bytes_written;
        app_log(LL_INFO, "Receive thread wrote %ld bytes to %s.", recv_file_bytes, output_fpath);
        if (total_sent_bytes != recv_file_bytes) {
            app_log(LL_WARN, "Mismatch in sent (%ld) and received/written to file (%ld) byte counts.",
                    total_sent_bytes, recv_file_bytes);
        }
        if (output_fd >= 0) {
            close(output_fd);
            output_fd = -1;
        }
        if (recv_file_bytes < 0) {
             app_log(LL_ERR, "Loopback file test (%s -> %s) FAILED due to error in receive thread.", input_fpath, output_fpath);
        } else if (compare_files(input_fpath, output_fpath) == 0) {
            app_log(LL_INFO, "Loopback file test (%s -> %s) PASSED.", input_fpath, output_fpath);
            final_ret = 0;
        } else {
            app_log(LL_ERR, "Loopback file test (%s -> %s) FAILED. Files differ.", input_fpath, output_fpath);
        }
    } else {
        int actual_read = *th_args.fixed_bytes_read;
        int match_success = *th_args.fixed_match;
        app_log(LL_INFO, "Read %d bytes from %s: \"%.*s\"", actual_read, dev_r_path, actual_read, fixed_rx_buf);
        if (match_success == 1) {
            app_log(LL_INFO, "Loopback fixed string test (%s -> %s) PASSED.", dev_s_path, dev_r_path);
            final_ret = 0;
        } else {
            app_log(LL_ERR, "Loopback fixed string test (%s -> %s) FAILED.", dev_s_path, dev_r_path);
            app_log(LL_DEBUG, "Expected: \"%s\" (%d bytes)", fixed_tx_data, fixed_tx_len);
            app_log(LL_DEBUG, "Received: \"%.*s\" (%d bytes)", actual_read, fixed_rx_buf, actual_read);
        }
    }
    
cleanup:
    app_log(LL_INFO, "Closing loopback devices and files...");
    if (fd_recv >= 0) close(fd_recv);
    if (fd_send >= 0) close(fd_send);
    if (input_fd >= 0) close(input_fd);
    if (output_fd >= 0) close(output_fd);
    return final_ret;
}

int main(int argc, char *argv[])
{
    op_mode_t mode = MODE_UNSET;
    char *recv_dev_path = NULL;
    char *send_dev_path = NULL;
    char *dev_path = NULL;
    char *data_str = NULL;
    char *input_file_lb = NULL;
    char *output_file_lb = NULL;
    int baudrate = 0;
    int opt;
    int result = 0;

    if (argc == 1) {
        print_usage();
        exit(EXIT_SUCCESS);
    }

    while ((opt = getopt(argc, argv, "M:r:s:d:b:D:L:hi:o:")) != -1) {
        switch (opt) {
            case 'M':
                if (strcmp(optarg, "forward") == 0) mode = MODE_FORWARD;
                else if (strcmp(optarg, "recv") == 0) mode = MODE_RECEIVE;
                else if (strcmp(optarg, "send") == 0) mode = MODE_SEND;
                else if (strcmp(optarg, "loopback") == 0) mode = MODE_LOOPBACK;
                else {
                    app_log(LL_ERR,
                            "ERROR: Invalid mode '%s'. Use 'forward', 'recv', 'send', or 'loopback'.\n",
                            optarg);
                    print_usage();
                    exit(EXIT_FAILURE);
                }
                break;
            case 'r':
                recv_dev_path = optarg;
                break;
            case 's':
                send_dev_path = optarg;
                break;
            case 'd':
                dev_path = optarg;
                break;
            case 'b':
                baudrate = atoi(optarg);
                break;
            case 'D':
                data_str = optarg;
                break;
            case 'i':
                input_file_lb = optarg;
                break;
            case 'o':
                output_file_lb = optarg;
                break;
            case 'L':
                if (strcmp(optarg, "error") == 0 || strcmp(optarg, "0") == 0) current_log_level = LL_ERR;
                else if (strcmp(optarg, "warn") == 0 || strcmp(optarg, "1") == 0) current_log_level = LL_WARN;
                else if (strcmp(optarg, "info") == 0 || strcmp(optarg, "2") == 0) current_log_level = LL_INFO;
                else if (strcmp(optarg, "debug") == 0 || strcmp(optarg, "3") == 0) current_log_level = LL_DEBUG;
                else {
                    app_log(LL_ERR,
                            "ERROR: Invalid log level '%s'. Use 'error'(0), 'warn'(1), "
                            "'info'(2), or 'debug'(3).\n",
                            optarg);
                    print_usage();
                    exit(EXIT_FAILURE);
                }
                break;
            case 'h':
                print_usage();
                exit(EXIT_SUCCESS);
            default: /* '?' */
                print_usage();
                exit(EXIT_FAILURE);
        }
    }

    app_log(LL_DEBUG, "Log level set to %d", current_log_level);

    if (mode == MODE_UNSET) {
        app_log(LL_ERR, "Operation mode (-M) is required.");
        print_usage();
        exit(EXIT_FAILURE);
    }

    if (baudrate == 0) {
        app_log(LL_ERR, "Baud rate (-b) is required and must be a positive integer.");
        print_usage();
        exit(EXIT_FAILURE);
    }

    switch (mode) {
        case MODE_FORWARD:
            result = handle_forward_mode(recv_dev_path, send_dev_path, baudrate);
            break;
        case MODE_RECEIVE:
            result = handle_receive_mode(dev_path, baudrate);
            break;
        case MODE_SEND:
            result = handle_send_mode(dev_path, baudrate, data_str);
            break;
        case MODE_LOOPBACK:
            result = handle_loopback_mode(recv_dev_path, send_dev_path, baudrate, input_file_lb, output_file_lb);
            break;
        case MODE_UNSET:
        default:
            app_log(LL_ERR, "Invalid internal mode state.");
            exit(EXIT_FAILURE);
    }

    return (result == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}