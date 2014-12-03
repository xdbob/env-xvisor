#! /bin/bash


ELF=$1
BIN=$2
DTB=$3
OUT=$4


INSTR="mcr	15, 0, r0, cr1, cr0, {0}"
START_SECTION=_start

declare -x START_ADDR=
declare -x MMU_OFFSET=
declare -x MMU_PHYS_OFF=

function check_env() {
    for var in TOOLCHAIN_PREFIX RAM_BASE BASE_ADDR BOARD; do
	if [ -z "${!var}" ]; then
	    echo "$0: Error: \"${var}\" is not set or empty, exiting"
	    exit 1
	fi
    done
}

function check_args() {
    for var in ELF BIN DTB; do
	if [ ! -e "${!var}" ]; then
	    echo "$0: Error: \"${!var}\" does not exists, exiting"
	    exit 1
	fi
    done

    OUTDIR=$(dirname ${OUT})
    mkdir -p ${OUTDIR}
    if [ $? -ne 0 ]; then
	echo "$0: Error: Failed to create \"${OUTDIR}\" directory, exiting"
	exit 1
    fi
}

function addrbase_get() {
    BOL="[ ]*[0-9]+: "
    ADDR="([0-9a-f]+)"
    PROP="[ ]+.*NOTYPE[ ]+GLOBAL[ ]+DEFAULT.*[ ]+"
    START_ADDR=$(${TOOLCHAIN_PREFIX}readelf -s ${ELF} | \
	sed -rne "s/^${BOL}${ADDR}${PROP}${START_SECTION}$/\1/p")
    if [ -z "${START_ADDR}" ]; then
	echo "\"${START_SECTION}\" not found in ${ELF}, exiting"
	exit 1
    fi
    START_ADDR=0x${START_ADDR}
}

function mmuset_get() {
    OFFSET_MAX=$((START_ADDR + 0x1000))
    MMU_OFFSET=0x$(${TOOLCHAIN_PREFIX}objdump -d --stop-address=${OFFSET_MAX} \
	${ELF} | grep "${INSTR}" | cut -d : -f 1)
    MMU_OFFSET=$((MMU_OFFSET + 4))
    MMU_PHYS_OFF=$((MMU_OFFSET - START_ADDR + BASE_ADDR))
}

function addrdtb_get() {
	DTB_BASE=$((RAM_BASE + 0x0))
}

function hexify() {
    for var in RAM_ADDR BASE_ADDR MMU_OFFSET MMU_PHYS_OFF DTB_BASE; do
	export ${var}=$(printf "0x%x" ${!var})
    done
}

function print_info() {
    if [ -z "${DEBUG}" ]; then
	return
    fi
    echo "Generating \"${OUT}\":"
    printf "  DTB loaded at:\t${RAM_ADDR}\n"
    printf "  Load base address:\t${BASE_ADDR}\n"
    printf "  Virtual base address:\t${START_ADDR}\n"
    printf "  MMU set (LMA):\t${MMU_PHYS_OFF}\n"
    printf "  MMU set (VMA):\t${MMU_OFFSET}\n"
}

function write_tcl() {
    cat > ${OUT} <<EOF
# Generated OpenOCD TCL configuration file for ${BOARD}
# to load and run Xvisor.
# Generated by ${USER} on $(date)

proc xvisor_load {} {
    load_image ${DTB} ${DTB_BASE} bin
    load_image ${BIN} ${BASE_ADDR} bin

    reg r2 ${DTB_BASE}
    reg pc ${BASE_ADDR}
}

proc xvisor_verify {} {
    verify_image ${DTB} ${DTB_BASE} bin
    verify_image ${BIN} ${BASE_ADDR} bin
}

proc xvisor_init {} {
    xvisor_load

    # Wait for MMU init
    bp ${MMU_PHYS_OFF} 4 hw
    # Start Xvisor
    resume ${BASE_ADDR}
    # Wait for the breakpoint
    wait_halt
    # Remove it
    rbp ${MMU_PHYS_OFF}
    # MMU should now be enabled, update the status
    # with a single step
    step
}
EOF
}

check_env
check_args
addrbase_get
mmuset_get
addrdtb_get
hexify
print_info
write_tcl
