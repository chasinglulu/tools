#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# This script is used to generate AXP files for different projects.
# It parses command line arguments, sets up paths, and generates AXP parameters.
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# SPDX-License-Identifier: GPL-2.0+
# -----------------------------------------------------------------------------

set -e

# Parse command line arguments
parse_arguments() {
    while getopts "abghl:n:o:s:tuv:x" opt; do
        case "$opt" in
            a) SUPPORT_AB=TRUE ;;
            b) SECURE_BOOT=TRUE ;;
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
}

# Print usage information
print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a  Enable AB partition"
    echo "  -b  Enable secure boot"
    echo "  -g  Support GZIP"
    echo "  -h  Show this help message"
    echo "  -l  Specify libc name (e.g. glibc)"
    echo "  -o  Support OPTEE"
    echo "  -n  Platform name (e.g. axera_fpga)"
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
    debug "Generating AXP filename..."
    CHIP_NAME=${PROJECT%\_*}
    VERSION_EXT=${VERSION}_$(date "+%Y%m%d%H%M%S")

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

# Initialize paths
initialize_paths() {
    debug "Initializing paths..."
    LOCAL_PATH=$(pwd)
    HOME_PATH=$LOCAL_PATH/..
    OUTPUT_PATH=$LOCAL_PATH/out
    IMG_PATH=$OUTPUT_PATH/$PROJECT/images
    SAFE_IMG_PATH=$OUTPUT_PATH/$PROJECT/images/SafetyIsland
    ENV_PATH=$OUTPUT_PATH/$PROJECT/images/ota_env.txt
    AXP_PATH=$OUTPUT_PATH/$AXP_NAME
    GEN_AXP_TOOL=$HOME_PATH/build/scripts/create_axp.py
    GEN_XML_TOOL=$HOME_PATH/build/scripts/convert.py
    JSON_PATH=$HOME_PATH/build/out/$PROJECT/images/$PROJECT.json
    PAC_XML_PATH=$HOME_PATH/build/out/$PROJECT/images/$PROJECT.xml
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ] ; then
        AXP_UBUNTU_ROOTFS_PATH=$OUTPUT_PATH/$AXP_UBUNTU_ROOTFS_NAME
    fi

    debug "Paths initialized:"
    debug "  LOCAL_PATH=$LOCAL_PATH"
    debug "  HOME_PATH=$HOME_PATH"
    debug "  OUTPUT_PATH=$OUTPUT_PATH"
    debug "  IMG_PATH=$IMG_PATH"
    debug "  AXP_PATH=$AXP_PATH"
    debug "  GEN_AXP_TOOL=$GEN_AXP_TOOL"
    debug "  GEN_XML_TOOL=$GEN_XML_TOOL"
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
        else
            OPTEE_PATH=$IMG_PATH/optee.img
            OPTEE_A_PATH=$IMG_PATH/optee.img
            OPTEE_B_PATH=$IMG_PATH/optee.img
        fi
    fi

    ROOTFS_PATH=$IMG_PATH/rootfs_sparse_ext4.img
    PARAM_PATH=$IMG_PATH/param_sparse.ext4
    SOC_PATH=$IMG_PATH/soc_sparse_ext4.img
    OPT_PATH=$IMG_PATH/opt_sparse_ext4.img
    CUSTOMER_PATH=$IMG_PATH/customer.img
    MODEL_PATH=$IMG_PATH/model.img
    if [ "$BUILD_UBUNTU_AXP" = "TRUE" ]; then
        UBUNTU_ROOTFS_PATH=$IMG_PATH/ubuntu_rootfs_sparse_ext4.img
    fi

    debug "Image paths initialized:"
    debug "  EIP_PATH=$EIP_PATH"
    debug "  FDL1_PATH=$FDL1_PATH"
    debug "  FDL2_PATH=$FDL2_PATH"
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

initialize_project_specific_paths() {
    debug "Initializing project-specific paths..."
    if [[ "$PROJECT" =~ "m57h_nand" ]] ; then
        PARAM_PATH=$IMG_PATH/param.ubi
        ROOTFS_PATH=$IMG_PATH/rootfs_soc_opt.ubi
    elif [[ "$PROJECT" =~ "m57h_nor" ]] ; then
        ROOTFS_PATH=$IMG_PATH/rootfs.img
        OPT_PATH=$IMG_PATH/opt.img
    elif [[ "$PROJECT" =~ "m57h_hyper" ]] ;then
        :
    elif [[ "$PROJECT" =~ "m57h_emmc" ]] ;then
        :
    elif [[ "$PROJECT" =~ "fpga" ]] ;then
        :
    elif [[ "$PROJECT" =~ "demo_nor_nand" ]] ;then
        :
    elif [[ "$PROJECT" =~ "evb" ]] ; then
        :
    else
        echo "Error: Unsupported project name: $PROJECT"
        exit 1
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
    initialize_paths
    initialize_image_paths
    initialize_project_specific_paths

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
}

main "$@"
