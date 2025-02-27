#!/usr/bin/env bash
set -eu

# Default values
img_size="20M"
volume_label=""
root_dir=""
img_file=""

# Function to display usage information
usage() {
    echo "Usage: $0 [options] <image name>"
    echo "Options:"
    echo "  -s <size>   Image size (default: 20M)"
    echo "  -l <label>  Volume label"
    echo "  -d <dir>    Source directory"
    echo "  -h          Show this help message"
    exit 1
}

# Parse command-line options
while getopts "s:l:d:h" opt; do
  case "$opt" in
    s) img_size="$OPTARG" ;;
    l) volume_label="-L '$OPTARG'" ;;
    d) root_dir="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
  esac
done

# Remove parsed options from the argument list
shift $((OPTIND - 1))

# Check if image name is provided
if [ $# -eq 0 ]; then
  echo "Error: Image name is required" >&2
  usage
fi

img_file="$1"

# Check if source directory is provided
if [ -z "$root_dir" ]; then
    echo "Error: Source directory is required" >&2
    usage
fi

echo "DIR: $root_dir"
echo "Image Size: $img_size"
echo "Volume Label: $volume_label"

# Create a 20M ext4 image from a directory without sudo.
mke2fs $volume_label -N 0 -O ^64bit -d "$root_dir" -m 5 -r 1 -t ext4 "$img_file" "$img_size"
