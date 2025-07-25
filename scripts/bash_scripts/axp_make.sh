#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangxinlu@aliyun.com>
#
# This script generates AXP files for different projects.
#

set -e

# Determine BUILD_DIR based on script location relative to build directory
# Assuming this script is in build/scripts/
BUILD_DIR=$(cd "$(dirname "$0")/.." ; pwd)

# Parse command line arguments
parse_arguments() {
    while getopts "abcdghl:n:os:tuv:x" opt; do
        case "$opt" in
            a) SUPPORT_AB=TRUE ;;
            b) SECURE_BOOT=TRUE ;;
            c) ENABLE_CIPHER=TRUE ;;
            d) ROOTFS_DMVERITY=TRUE ;;
            g) SUPPORT_GZIPD=TRUE ;;
            l) LIBC_NAME=$OPTARG ;;
            n) PLATFORM=$OPTARG ;;
            o) SUPPORT_OPTEE=TRUE ;;
            s) SENSOR_MODEL=$OPTARG ;;
            t) SUPPORT_ATF=TRUE ;;
            u) BUILD_UBUNTU_AXP=TRUE ;;
            v) VERSION=$OPTARG ;;
            x) DEBUG=TRUE ;;
            h) print_usage; exit 0 ;;
            *) print_usage; exit 1 ;;
        esac
    done

    debug "Arguments parsed:"
    debug "  SUPPORT_OPTEE=$SUPPORT_OPTEE"
    debug "  PLATFORM=$PLATFORM"
    debug "  SENSOR_MODEL=$SENSOR_MODEL"
    debug "  BUILD_UBUNTU_AXP=$BUILD_UBUNTU_AXP"
    debug "  VERSION=$VERSION"
    debug "  SUPPORT_GZIPD=$SUPPORT_GZIPD"
    debug "  SUPPORT_AB=$SUPPORT_AB"
    debug "  LIBC_NAME=$LIBC_NAME"
    debug "  SECURE_BOOT=$SECURE_BOOT"
    debug "  SUPPORT_ATF=$SUPPORT_ATF"
    debug "  ENABLE_CIPHER=$ENABLE_CIPHER"
    debug "  ROOTFS_DMVERITY=$ROOTFS_DMVERITY"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a  Enable AB partition"
    echo "  -b  Enable secure boot"
    echo "  -c  Enable image cipher"
    echo "  -d  Enable rootfs dm-verity"
    echo "  -g  Support GZIP"
    echo "  -h  Show this help message"
    echo "  -l  Specify libc name (e.g. glibc)"
    echo "  -o  Support OPTEE"
    echo "  -n  Project name (e.g. laguna_nand)"
    echo "  -s  Sensor Model"
    echo "  -t  Support ATF"
    echo "  -u  Build Ubuntu AXP"
    echo "  -v  SDK version (e.g. 1.0.0)"
    echo "  -x  Enable debug output"
    echo
    echo "Example:"
    echo "  $0 -p my_platform -v 1.0.0 -l glibc -a -b"
}

# Debug output function
debug() {
    if [ "$DEBUG" = "TRUE" ]; then
        echo "DEBUG: $1"
    fi
}

# Generate AXP filename
generate_axp_filename() {
    PROJECT=${PLATFORM#*\_}
    CHIP_NAME=${PROJECT%\_*}
    HOME_PATH=$(cd $BUILD_DIR/..; pwd)
    OUTPUT_PATH=$BUILD_DIR/out
    TIMESTAMP_PATH=$OUTPUT_PATH/$PROJECT/timestamp

    if [ -s "$TIMESTAMP_PATH" ]; then
        BUILD_TIMESTAMP=$(cat "$TIMESTAMP_PATH")
        debug "Using timestamp from file: $BUILD_TIMESTAMP"
    else
        BUILD_TIMESTAMP=$(date "+%Y%m%d%H%M")
        debug "Timestamp file not found or empty, using current date: $BUILD_TIMESTAMP"
    fi
    VERSION_EXT=${VERSION}_${BUILD_TIMESTAMP}

    debug "Generating AXP filename..."
    if [ -z "$SENSOR_MODEL" ]; then
        AXP_NAME=${PLATFORM}_${VERSION_EXT}
        [ -n "$LIBC_NAME" ] && AXP_NAME+=_${LIBC_NAME}
    else
        SENSOR_MODEL=$(echo $SENSOR_MODEL | tr ' ' '_')
        AXP_NAME=${PLATFORM}_${SENSOR_MODEL}_${VERSION_EXT}
        [ -n "$LIBC_NAME" ] && AXP_NAME+=_${LIBC_NAME}
    fi
    AXP_NAME+=.axp

    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ]; then
        AXP_UBUNTU_ROOTFS_NAME=${AXP_NAME/%.axp/_ubuntu_rootfs.axp}
        debug "AXP_UBUNTU_ROOTFS_NAME=$AXP_UBUNTU_ROOTFS_NAME"
    fi

    debug "PROJECT=$PROJECT"
    debug "CHIP_NAME=$CHIP_NAME"
    debug "VERSION_EXT=$VERSION_EXT"
    debug "AXP_NAME=$AXP_NAME"
}

generate_sdcard_filename() {
	debug "Generating SDcard filename..."
	if [ -z "$SENSOR_MODEL" ]; then
		SDIMG_NAME=${PLATFORM}_sdcard_${VERSION_EXT}.zip
	else
		SENSOR_MODEL=$(echo $SENSOR_MODEL | tr ' ' '_')
		SDIMG_NAME=${PLATFORM}_sdcard_${SENSOR_MODEL}_${VERSION_EXT}.zip
	fi
	debug "SDIMG_NAME=$SDIMG_NAME"
}

# Initialize paths
initialize_paths() {
    debug "Initializing paths..."
    IMG_PATH=$OUTPUT_PATH/$PROJECT/images
    SAFE_IMG_PATH=$OUTPUT_PATH/$PROJECT/images/SafetyIsland
    ENV_PATH=$OUTPUT_PATH/$PROJECT/images/ota_env.txt
    AXP_PATH=$OUTPUT_PATH/$AXP_NAME
    SDIMG_PATH=$OUTPUT_PATH/$SDIMG_NAME
    GEN_AXP_TOOL=$HOME_PATH/build/scripts/create_axp.py
    GEN_XML_TOOL=$HOME_PATH/build/scripts/convert.py
    GEN_SDIMG_TOOL=$HOME_PATH/build/scripts/create_sdcard_image.py
    JSON_PATH=$HOME_PATH/build/out/$PROJECT/images/$PROJECT.json
    PAC_XML_PATH=$HOME_PATH/build/out/$PROJECT/images/$PROJECT.xml
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ] ; then
        AXP_UBUNTU_ROOTFS_PATH=$OUTPUT_PATH/$AXP_UBUNTU_ROOTFS_NAME
    fi

    debug "Paths initialized:"
    debug "  HOME_PATH=$HOME_PATH"
    debug "  BUILD_DIR=$BUILD_DIR"
    debug "  OUTPUT_PATH=$OUTPUT_PATH"
    debug "  TIMESTAMP_PATH=$TIMESTAMP_PATH"
    debug "  IMG_PATH=$IMG_PATH"
    debug "  AXP_PATH=$AXP_PATH"
    debug "  SDIMG_PATH=$SDIMG_PATH"
    debug "  GEN_AXP_TOOL=$GEN_AXP_TOOL"
    debug "  GEN_XML_TOOL=$GEN_XML_TOOL"
    debug "  GEN_SDIMG_TOOL=$GEN_SDIMG_TOOL"
    debug "  JSON_PATH=$JSON_PATH"
    debug "  PAC_XML_PATH=$PAC_XML_PATH"
    debug "  PROJECT_MAK=$PROJECT_MAK"
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ] ; then
        debug "  AXP_UBUNTU_ROOTFS_PATH=$AXP_UBUNTU_ROOTFS_PATH"
    fi
}

# Initialize image paths
initialize_image_paths() {
    debug "Initializing image paths..."

    # This script sets up various environment variables pointing to image files
    # used in the build process. The variables are defined as follows:
    #
    # FDL1_PATH: Path to the fdl1_signed.img file.
    # SBL_PATH: Path to the sbl_signed.img file.
    # SBL_A_PATH: Path to the sbl_signed.img file (alternative A).
    # SBL_B_PATH: Path to the sbl_signed.img file (alternative B).
    # RTOS_PATH: Path to the Mcal_Demo_signed.img file.
    # RTOS_A_PATH: Path to the Mcal_Demo_signed.img file (alternative A).
    # RTOS_B_PATH: Path to the Mcal_Demo_signed.img file (alternative B).
    # SPL_PATH: Path to the u-boot-spl_signed.img file.
    # SPL_A_PATH: Path to the u-boot-spl_signed.img file (alternative A).
    # SPL_B_PATH: Path to the u-boot-spl_signed.img file (alternative B).
    #
    # Note:
    # These images are loaded by the Safety domain, regardless of whether
    # secure boot is enabled. The same image is used in all cases, and even though
    # the filenames include "signed", these images have headers and signature data added.
    FDL1_PATH=$SAFE_IMG_PATH/fdl1_signed.img
    SBL_PATH=$SAFE_IMG_PATH/sbl_signed.img
    SBL_A_PATH=$SAFE_IMG_PATH/sbl_signed.img
    SBL_B_PATH=$SAFE_IMG_PATH/sbl_signed.img
    RTOS_PATH=$SAFE_IMG_PATH/Mcal_Demo_signed.img
    RTOS_A_PATH=$SAFE_IMG_PATH/Mcal_Demo_signed.img
    RTOS_B_PATH=$SAFE_IMG_PATH/Mcal_Demo_signed.img
    SPL_PATH=$IMG_PATH/u-boot-spl_signed.img
    SPL_A_PATH=$IMG_PATH/u-boot-spl_signed.img
    SPL_B_PATH=$IMG_PATH/u-boot-spl_signed.img
    ROOTFS_PATH=$IMG_PATH/rootfs.img
    ROOTFS_A_PATH=$IMG_PATH/rootfs.img
    ROOTFS_B_PATH=$IMG_PATH/rootfs.img

    if [ "$SECURE_BOOT" = "TRUE" ]; then
        cp $HOME_PATH/build/scripts/imgsign/eip130_fw.bin $IMG_PATH/eip_m57h.img

        EIP_PATH=$IMG_PATH/eip_m57h.img
        FDL2_PATH=$IMG_PATH/fdl2_signed.img
        UBOOT_PATH=$IMG_PATH/u-boot_signed.img
        UBOOT_A_PATH=$IMG_PATH/u-boot_signed.img
        UBOOT_B_PATH=$IMG_PATH/u-boot_signed.img
        KERNEL_PATH=$IMG_PATH/kernel_signed.img
        KERNEL_A_PATH=$IMG_PATH/kernel_signed.img
        KERNEL_B_PATH=$IMG_PATH/kernel_signed.img
        if [ "$ROOTFS_DMVERITY" = "TRUE" ]; then
            ROOTFS_PATH=$IMG_PATH/rootfs_signed.img
            ROOTFS_A_PATH=$IMG_PATH/rootfs_signed.img
            ROOTFS_B_PATH=$IMG_PATH/rootfs_signed.img
        fi
        if [ "$ENABLE_CIPHER" = "TRUE" ]; then
            SBL_PATH=$SAFE_IMG_PATH/sbl_enc_signed.img
            SBL_A_PATH=$SAFE_IMG_PATH/sbl_enc_signed.img
            SBL_B_PATH=$SAFE_IMG_PATH/sbl_enc_signed.img
            RTOS_PATH=$SAFE_IMG_PATH/Mcal_Demo_enc_signed.img
            RTOS_A_PATH=$SAFE_IMG_PATH/Mcal_Demo_enc_signed.img
            RTOS_B_PATH=$SAFE_IMG_PATH/Mcal_Demo_enc_signed.img
            SPL_PATH=$IMG_PATH/u-boot-spl_enc_signed.img
            SPL_A_PATH=$IMG_PATH/u-boot-spl_enc_signed.img
            SPL_B_PATH=$IMG_PATH/u-boot-spl_enc_signed.img
            UBOOT_PATH=$IMG_PATH/u-boot_enc_signed.img
            UBOOT_A_PATH=$IMG_PATH/u-boot_enc_signed.img
            UBOOT_B_PATH=$IMG_PATH/u-boot_enc_signed.img
            KERNEL_PATH=$IMG_PATH/kernel_enc_signed.img
            KERNEL_A_PATH=$IMG_PATH/kernel_enc_signed.img
            KERNEL_B_PATH=$IMG_PATH/kernel_enc_signed.img
        fi
    else
        FDL2_PATH=$IMG_PATH/fdl2.img
        UBOOT_PATH=$IMG_PATH/u-boot.img
        UBOOT_A_PATH=$IMG_PATH/u-boot.img
        UBOOT_B_PATH=$IMG_PATH/u-boot.img
        KERNEL_PATH=$IMG_PATH/kernel.img
        KERNEL_A_PATH=$IMG_PATH/kernel.img
        KERNEL_B_PATH=$IMG_PATH/kernel.img
    fi

    MISC_PATH=$IMG_PATH/misc.img
    MISC_BAK_PATH=$IMG_PATH/misc.img
    UBOOTENV_PATH=$IMG_PATH/ubootenv.img
    UBOOTENV_BAK_PATH=$IMG_PATH/ubootenv.img

    if [ "$SUPPORT_ATF" = "TRUE" ]; then
        if [ "$SECURE_BOOT" = "TRUE" ]; then
            ATF_PATH=$IMG_PATH/bl31_signed.img
            ATF_A_PATH=$IMG_PATH/bl31_signed.img
            ATF_B_PATH=$IMG_PATH/bl31_signed.img
            if [ "$ENABLE_CIPHER" = "TRUE" ]; then
                ATF_PATH=$IMG_PATH/bl31_enc_signed.img
                ATF_A_PATH=$IMG_PATH/bl31_enc_signed.img
                ATF_B_PATH=$IMG_PATH/bl31_enc_signed.img
            fi
        else
            ATF_PATH=$IMG_PATH/bl31.img
            ATF_A_PATH=$IMG_PATH/bl31.img
            ATF_B_PATH=$IMG_PATH/bl31.img
        fi
    fi
    if [ "$SUPPORT_OPTEE" = "TRUE" ]; then
        if [ "$SECURE_BOOT" = "TRUE" ]; then
            OPTEE_PATH=$IMG_PATH/optee_signed.img
            OPTEE_A_PATH=$IMG_PATH/optee_signed.img
            OPTEE_B_PATH=$IMG_PATH/optee_signed.img
            if [ "$ENABLE_CIPHER" = "TRUE" ]; then
                OPTEE_PATH=$IMG_PATH/optee_enc_signed.img
                OPTEE_A_PATH=$IMG_PATH/optee_enc_signed.img
                OPTEE_B_PATH=$IMG_PATH/optee_enc_signed.img
            fi
        else
            OPTEE_PATH=$IMG_PATH/optee.img
            OPTEE_A_PATH=$IMG_PATH/optee.img
            OPTEE_B_PATH=$IMG_PATH/optee.img
        fi
    fi

    #ROOTFS_PATH=$IMG_PATH/rootfs_sparse_ext4.img
    #PARAM_PATH=$IMG_PATH/param_sparse.ext4
    #SOC_PATH=$IMG_PATH/soc_sparse_ext4.img
    #OPT_PATH=$IMG_PATH/opt_sparse_ext4.img
    #CUSTOMER_PATH=$IMG_PATH/customer.img
    #MODEL_PATH=$IMG_PATH/model.img
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ]; then
        UBUNTU_ROOTFS_PATH=$IMG_PATH/ubuntu_rootfs_sparse_ext4.img
    fi

    debug "Image paths initialized:"
    debug "  EIP_PATH=$EIP_PATH"
    debug "  FDL1_PATH=$FDL1_PATH"
    debug "  FDL2_PATH=$FDL2_PATH"
    debug "  SBL_PATH=$SBL_PATH"
    debug "  RTOS_PATH=$RTOS_PATH"
    debug "  SPL_PATH=$SPL_PATH"
    debug "  UBOOT_PATH=$UBOOT_PATH"
    debug "  KERNEL_PATH=$KERNEL_PATH"
    debug "  ATF_PATH=$ATF_PATH"
    debug "  OPTEE_PATH=$OPTEE_PATH"
    debug "  ROOTFS_PATH=$ROOTFS_PATH"
    debug "  PARAM_PATH=$PARAM_PATH"
    debug "  SOC_PATH=$SOC_PATH"
    debug "  OPT_PATH=$OPT_PATH"
    debug "  CUSTOMER_PATH=$CUSTOMER_PATH"
    debug "  MODEL_PATH=$MODEL_PATH"
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ] ; then
        debug "  UBUNTU_ROOTFS_PATH=$UBUNTU_ROOTFS_PATH"
    fi

    # Check if files exist
    paths=(
     "$EIP_PATH" "$FDL1_PATH" "$FDL2_PATH" "$SPL_PATH" "$UBOOT_PATH"
     "$KERNEL_PATH" "$ATF_PATH" "$OPTEE_PATH"
    )
    for path in "${paths[@]}"; do
      if [ -n "$path" ] && [ ! -f "$path" ]; then
        echo "Error: File not found: $path"
        exit 1
      fi
    done
    debug "Image paths initialized."
}

initialize_sdcard_specific_paths() {
	debug "Initializing SDCard image paths..."
	BOOT_PATH=$SAFE_IMG_PATH/boot.bin
	FDL_PARTITION_PATH=$IMG_PATH/fdl_partition.img

	debug "SDCard Image paths initialized:"
	debug "  BOOT_PATH=$BOOT_PATH"
	debug "  FDL_PARTITION_PATH=$FDL_PARTITION_PATH"

	# Check if files exist
	if [ ! -f "$BOOT_PATH" ]; then
		echo "Error: BOOT_PATH file not found: $BOOT_PATH"
		exit 1
	fi
	if [ ! -f "$FDL_PARTITION_PATH" ]; then
		echo "Error: FDL_PARTITION_PATH file not found: $FDL_PARTITION_PATH"
		exit 1
	fi

	debug "SDCard image specific paths initialization completed."
}

initialize_project_specific_paths() {
    debug "Initializing project-specific paths..."
    if [[ "$PROJECT" =~ "m57h_nand" ]] ; then
        PARAM_PATH=$IMG_PATH/param.ubi
    elif [[ "$PROJECT" =~ "slt" ]] ;then
        RTOS_PATH=$SAFE_IMG_PATH/BareDemo_signed.img
        RTOS_A_PATH=$SAFE_IMG_PATH/BareDemo_signed.img
        RTOS_B_PATH=$SAFE_IMG_PATH/BareDemo_signed.img
        if [ "$ENABLE_CIPHER" = "TRUE" ]; then
            RTOS_PATH=$SAFE_IMG_PATH/BareDemo_enc_signed.img
            RTOS_A_PATH=$SAFE_IMG_PATH/BareDemo_enc_signed.img
            RTOS_B_PATH=$SAFE_IMG_PATH/BareDemo_enc_signed.img
        fi
    else
        debug "Warning: Unsupported project name: $PROJECT specific path initialize"
        return
    fi
    debug "Project-specific paths initialized."
}

# Generate AXP parameters
generate_axp_parameters() {
    debug "Generating AXP parameters..."
    AXP_PARM=""

    # Use image names parsed from XML output if available
    if [ $# -ge 1 ] && [ -n "$*" ]; then
        debug "Using image names from XML output"
        for image in "$@"; do
            image_path_var="${image}_PATH"
            if [ -n "${!image_path_var}" ]; then
                AXP_PARM+=" $image=${!image_path_var}"
            else
                echo "Error: No path found for image $image"
                exit 1
            fi
        done
    fi

    AXP_PARM="${AXP_PARM# }"
    debug "AXP_PARM=$AXP_PARM"
}

create_sdcard_image() {
    debug "Creating FDL SDCard image ..."

    debug "Original Partition List: $IMAGE_NAMES"

    local sd_img_arr=()
    local orig_img_arr=($IMAGE_NAMES)

    for item in "${orig_img_arr[@]}"; do
        if [[ "$item" != "FDL1" ]]; then
            sd_img_arr+=("$item")
        fi
    done
    sd_img_arr+=("BOOT" "FDL_PARTITION")


    local sd_img_str=$(IFS=" "; echo "${sd_img_arr[*]}")
    debug "Effective Partition List: $sd_img_str"

    debug "Generating SDCard image parameters..."
    SDIMG_PARM=""

    for image_label in "${sd_img_arr[@]}"; do
        local image_path_var="${image_label}_PATH"
        if [ -n "${!image_path_var}" ] && [ -f "${!image_path_var}" ]; then
            debug "Found path for $image_label: ${!image_path_var}"
            SDIMG_PARM+=" $image_label=${!image_path_var}"
        else
            echo "Error: No path found for image $image_label"
            exit 1
        fi
    done

    SDIMG_PARM="${SDIMG_PARM# }"
    debug "SDIMG_PARM=$SDIMG_PARM"

    SDIMG_GEN_CMD="python3 $GEN_SDIMG_TOOL -o $SDIMG_PATH -P $SDIMG_PARM"
    if [ "$DEBUG" = "TRUE" ]; then
        SDIMG_GEN_CMD+=" -d -v"
        debug "SDIMG_GEN_CMD: $SDIMG_GEN_CMD"
    fi

    # Execute SDCard Image generation command
    $SDIMG_GEN_CMD
    SDIMG_RETURN_CODE=$?

    if [ $SDIMG_RETURN_CODE -ne 0 ]; then
        echo "Error: SDCard image generation failed with code $SDIMG_RETURN_CODE" >&2
        exit 1
    fi

    debug "SDCard image generation finished."
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    parse_arguments "$@"

    if [ -z "$PLATFORM" ]; then
        echo "PLATFORM is not set. Using default value: axera_m57h"
        PROJECT="axera_m57h"
    fi

    if [ -z "$VERSION" ]; then
        echo "VERSION is not set. Using default value: 1.0.0"
        VERSION="1.0.0"
    fi

    generate_axp_filename
    generate_sdcard_filename
    initialize_paths
    initialize_image_paths
    initialize_project_specific_paths
    initialize_sdcard_specific_paths

    debug "Chip SoC Name: $CHIP_NAME"

    # Construct the XML generation command
    XML_GEN_CMD="python3 $GEN_XML_TOOL -n $PROJECT -v $VERSION -i $JSON_PATH -o $PAC_XML_PATH -mf $ENV_PATH"
    if [ "$SECURE_BOOT" = "TRUE" ]; then
        XML_GEN_CMD+=" -s"
    fi

    if [ "$DEBUG" = "TRUE" ]; then
        XML_GEN_CMD+=" -d"
        debug "XML_GEN_CMD: $XML_GEN_CMD"
    fi

    # Disable set -e temporarily
    set +e

    # Capture the output of the XML generation command (only for parsing image names)
    XML_OUTPUT=$($XML_GEN_CMD 2>&1)
    XML_RETURN_CODE=$?

    # Re-enable set -e
    set -e

    if [ $XML_RETURN_CODE -ne 0 ]; then
        echo "Error: XML generation failed with code $XML_RETURN_CODE" >&2
        echo "Output: $XML_OUTPUT" >&2
        exit 1
    fi

    if [ "$DEBUG" = "TRUE" ]; then
		echo "XML generation output:"
		echo "$XML_OUTPUT"
	fi

    # Extract image names from the output
    IMAGE_NAMES=$(echo "$XML_OUTPUT" | grep "Image names:" | sed 's/Image names: //g')

    if [ -z "$IMAGE_NAMES" ]; then
        echo "No image names found in XML output"
        IMAGE_NAMES_ARRAY=()
        exit 1
    else
        # Store image names in an array
        # read -r -a IMAGE_NAMES_ARRAY <<< "$IMAGE_NAMES"
        IMAGE_NAMES_ARRAY=()
        IFS=' '
        for image in $IMAGE_NAMES; do
            IMAGE_NAMES_ARRAY+=("$image")
        done
        debug "Extracted image names: ${IMAGE_NAMES_ARRAY[*]}"
    fi

    generate_axp_parameters "${IMAGE_NAMES_ARRAY[@]}"

    AXP_GEN_CMD="python3 $GEN_AXP_TOOL -n $PROJECT -v $VERSION_EXT -x $PAC_XML_PATH -o $AXP_PATH -P ${AXP_PARM}"

    if [ "$DEBUG" = "TRUE" ]; then
        AXP_GEN_CMD+=" -d -V"
        debug "AXP_GEN_CMD: $AXP_GEN_CMD"
    fi

    # Execute AXP generation command
    $AXP_GEN_CMD
    AXP_RETURN_CODE=$?

    if [ $AXP_RETURN_CODE -ne 0 ]; then
        echo "Error: AXP generation failed with code $AXP_RETURN_CODE" >&2
        exit 1
    fi
    echo "AXP_PATH=\"$AXP_PATH\"" >> $ENV_PATH
    echo "VERSION=\"$VERSION\"" >> $ENV_PATH

    # Execute SD card image creation if applicable
    create_sdcard_image
}

main "$@"
