#!/bin/bash

# Validate number of arguments
if [ $# -ne 2 ]; then
    echo "Error: Invalid number of arguments"
    echo ""
    echo "Usage:"
    echo "  $0 <kernel_image> <stack_log_file>"
    echo ""
    echo "Example:"
    echo "  $0 ./target/osdk/aster-kernel/aster-kernel-osdk-bin qemu.log"
    echo ""
    exit 1
fi

KERNEL_IMAGE="$1"
STACK_LOG="$2"

# Validate kernel image
if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "Error: Kernel image '$KERNEL_IMAGE' not found"
    exit 1
fi

# Validate stack log file
if [ ! -f "$STACK_LOG" ]; then
    echo "Error: Stack log file '$STACK_LOG' not found"
    exit 1
fi

# Check if addr2line is available
if ! command -v addr2line &> /dev/null; then
    echo "Error: addr2line not found. Please install binutils package."
    exit 1
fi

echo "=========================================="
echo "Call Stack Analysis"
echo "=========================================="
echo "Kernel: $KERNEL_IMAGE"
echo ""

# all PC address
ADDRESSES=$(grep -oP 'pc\s+0x[0-9a-f]+' "$STACK_LOG" | awk '{print $2}')

# Check if any addresses were found
if [ -z "$ADDRESSES" ]; then
    echo "Error: No PC addresses found in '$STACK_LOG'"
    echo "Expected format: 'pc 0x...' in the log file"
    exit 1
fi

# count
COUNT=$(echo "$ADDRESSES" | wc -l)
echo "Found $COUNT stack frames"
echo "=========================================="
echo ""

# process all address
FRAME_NUM=1
while IFS= read -r addr; do
    if [ -n "$addr" ]; then
        echo "Frame $FRAME_NUM: $addr"

        # Use addr2line to get function name and location
        RESULT=$(addr2line -e "$KERNEL_IMAGE" -f -C -i -p "$addr" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$RESULT" ] && [ "$RESULT" != "??:0" ]; then
            echo "  $RESULT"
        else
            echo "  [No debug info available]"
        fi
        echo ""

        ((FRAME_NUM++))
    fi
done <<< "$ADDRESSES"

echo "=========================================="
echo "Summary with raw addresses only"
echo "=========================================="
echo "$ADDRESSES" | nl -w2 -s': '

# Option: output all symbol stack
echo ""
echo "=========================================="
echo "Symbolicated Call Stack"
echo "=========================================="
addr2line -e "$KERNEL_IMAGE" -f -C -i $ADDRESSES 2>/dev/null | \
    awk '{if(NR%2==1) printf "  %-30s ", $0; else print "at " $0}'
