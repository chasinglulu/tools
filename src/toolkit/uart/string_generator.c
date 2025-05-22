/*
 * SPDX-License-Identifier: GPL-2.0+
 *
 * generates a random string
 *
 * Copyright (C) 2025 chasinglulu <wangkartx@gmail.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_STRING_LENGTH     1024
#define MAX_STRING_LENGTH         (1024 * 1024 * 10)

void print_usage(void) {
    printf("Usage: string_generator [-s <length>] [-o <output_file>]\n"
            "Options:\n"
            "  -s <length>      Specify the length of the random string (default: %d).\n"
            "  -o <output_file> Specify the output file. If not provided, output to stdout.\n"
            "  -h               Display this help message and exit.\n",
            DEFAULT_STRING_LENGTH);
}

int main(int argc, char *argv[]) {
    int string_length = DEFAULT_STRING_LENGTH;
    char *output_filepath = NULL;
    int opt;
    FILE *output_stream = stdout;

    while ((opt = getopt(argc, argv, "s:o:h")) != -1) {
        switch (opt) {
            case 's':
                string_length = atoi(optarg);
                if (string_length <= 0 || string_length > MAX_STRING_LENGTH) {
                    fprintf(stderr, "Error: Invalid string length. Must be between 1 and %d.\n", MAX_STRING_LENGTH);
                    print_usage();
                    return EXIT_FAILURE;
                }
                break;
            case 'o':
                output_filepath = optarg;
                break;
            case 'h':
                print_usage();
                return EXIT_SUCCESS;
            default: /* '?' */
                print_usage();
                return EXIT_FAILURE;
        }
    }

    if (optind < argc) {
        fprintf(stderr, "Error: Unexpected non-option arguments: ");
        while (optind < argc) {
            fprintf(stderr, "%s ", argv[optind++]);
        }
        fprintf(stderr, "\n");
        print_usage();
        return EXIT_FAILURE;
    }

    if (output_filepath != NULL) {
        output_stream = fopen(output_filepath, "w");
        if (output_stream == NULL) {
            perror("Error opening output file");
            return EXIT_FAILURE;
        }
    }

    char *random_string = malloc(string_length + 1);
    if (random_string == NULL) {
        fprintf(stderr, "Error: Memory allocation failed.\n");
        if (output_stream != stdout) {
            fclose(output_stream);
        }
        return EXIT_FAILURE;
    }

    srand(time(NULL));

    for (int i = 0; i < string_length; i++) {
        random_string[i] = (rand() % (126 - 32 + 1)) + 32;
    }
    random_string[string_length] = '\0';

    fprintf(output_stream, "%s", random_string);
    if (output_stream == stdout) {
        fprintf(output_stream, "\n");
    }

    free(random_string);
    if (output_stream != stdout) {
        fclose(output_stream);
        printf("Generated random string of length %d to %s\n", string_length, output_filepath);
    }

    return EXIT_SUCCESS;
}
