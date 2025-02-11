#!/usr/bin/env bash
# vim: tabstop=4 shiftwidth=4 expandtab colorcolumn=80 foldmethod=marker :

# uncomment the next line to enable script debugging
# set -x

# make sure we have the kernel directory defined
if [ -z "${KDIR}" ] ; then
    echo "error: you must supply environment variable KDIR" 1>&2
    echo "       or you do not have the kernel-devel installed" 1>&2
    exit 1
fi

#
# "syms" is an associative array, where the "key"
# is a symbol that we try to find (using grep) in
# the "value", i.e. we try to find the string
# "sysfs_emit" in the include file sysfs.h. Based
# on that, we create a cpp #define or #undef.
#
declare -A syms
syms[kmem_cache_create_usercopy]='slab.h'
syms[file_inode]='fs.h'
syms[sysfs_emit]='sysfs.h'

output='config.h'
kparent="${KDIR%/*}"

#
# use the "fs.h" to determine where the kernel headers are located
#
if [ -e "${KDIR}/include/linux/fs.h" ]
then
    hdrs="${KDIR}/include"
elif [ -e "${kparent}/source/include/linux/fs.h" ]
then
    hdrs="${kparent}/source/include"
else
    echo "Cannot infer kernel headers location" 1>&2
    exit 1
fi

rm -f "${output}"

cat <<EOF >"${output}"
/* Autogenerated by kernel/config.sh - do not edit
 */

#ifndef _MHVTL_KERNEL_CONFIG_H
#define _MHVTL_KERNEL_CONFIG_H


EOF

#
# start checking for compatability issues
#

#
# first, check the symbols in our associative array
#
for sym in ${!syms[@]}
do
    grep -q "${sym}" "${hdrs}/linux/${syms[$sym]}"
    if [ $? -eq 0 ]
    then
        printf '#define HAVE_%s\n' \
            "$( echo "${sym}" | tr [:lower:] [:upper:] )" >> "${output}"
    else
        printf '#undef HAVE_%s\n' \
            "$( echo "${sym}" | tr [:lower:] [:upper:] )" >> "${output}"
    fi
done

#
# do we have a "genhd.h" present?
#
if [ -e "${hdrs}/linux/genhd.h" ]; then
    echo "#define HAVE_GENHD"
else
    echo "#undef HAVE_GENHD"
fi >> "${output}"

#
# see if "struct file_operations" has member "unlocked_ioctl"
# (otherwise, just "ioctl")
#
syms[file_operations]='fs.h'
if grep -q unlocked_ioctl "${hdrs}/linux/fs.h"; then
    echo "#ifndef HAVE_UNLOCKED_IOCTL"
    echo "#define HAVE_UNLOCKED_IOCTL"
    echo "#endif"
else
    echo "#undef HAVE_UNLOCKED_IOCTL"
fi >> "${output}"

#
# check for the scsi queue command taking one or two args
#
str=$( grep 'rc = func_name##_lck' ${hdrs}/scsi/scsi_host.h )
if [[ "$str" == *,* ]] ; then
    echo "#undef QUEUECOMMAND_LCK_ONE_ARG"
else
    echo "#ifndef QUEUECOMMAND_LCK_ONE_ARG"
    echo "#define QUEUECOMMAND_LCK_ONE_ARG"
    echo "#endif"
fi >> "${output}"

#
# check for DEFINE_SEMAPHORE() taking an argument or not
#
if grep -q 'DEFINE_SEMAPHORE(_name, _n)' "${hdrs}/linux/semaphore.h"; then
    echo "#ifndef DEFINE_SEMAPHORE_HAS_NUMERIC_ARG"
    echo "#define DEFINE_SEMAPHORE_HAS_NUMERIC_ARG"
    echo "#endif"
else
    echo "#undef DEFINE_SEMAPHORE_HAS_NUMERIC_ARG"
fi >> "${output}"

#
# check if scsi_host_template argument to scsi_host_alloc
# is const
#
if fgrep -q 'extern struct Scsi_Host *scsi_host_alloc(const' \
        "${hdrs}/scsi/scsi_host.h"; then
    # the first argument to scsi_host_alloc needs to be a "const"
    echo "#ifndef DEFINE_CONST_STRUCT_SCSI_HOST_TEMPLATE"
    echo "#define DEFINE_CONST_STRUCT_SCSI_HOST_TEMPLATE"
    echo "#endif"
else
    echo "#undef DEFINE_CONST_STRUCT_SCSI_HOST_TEMPLATE"
fi >> "${output}"

#
# We need to find the definition for "struct bus_type", so that we
# can if the "match" member of this struct, which points to a function,
# has a 2nd argument that is const or not.
#

# The pattern to find (if "const" is needed)
pat='int (*match)(struct device *dev, const struct device_driver *drv);'

# First, find the file
bus_type_def_file=$(grep -rl 'struct bus_type {' ${hdrs})
: {bus_type_def_file:="not-found"}

# Now check for the 2nd argument needs a "const"
if [ -r "$bus_type_def_file" ] &&
   fgrep -q "$pat" "$bus_type_def_file"; then
    # the second argument needs a "const" definition
    echo "#ifndef DEFINE_CONST_STRUCT_DEVICE_DRIVER"
    echo "#define DEFINE_CONST_STRUCT_DEVICE_DRIVER"
    echo "#endif"
else
    echo "#undef DEFINE_CONST_STRUCT_DEVICE_DRIVER"
fi >> "${output}"

#
# check if slave_configure has been renamed to sdev_configure
#
pat='int (* sdev_configure)(struct scsi_device *, struct queue_limits *lim);'
if fgrep -q "$pat" "${hdrs}/scsi/scsi_host.h"; then
    echo "#ifndef DEFINE_QUEUE_LIMITS_SCSI_DEV_CONFIGURE"
    echo "#define DEFINE_QUEUE_LIMITS_SCSI_DEV_CONFIGURE"
    echo "#endif"
else
    echo "#undef DEFINE_QUEUE_LIMITS_SCSI_DEV_CONFIGURE"
fi >> "${output}"

printf '\n\n#endif /* _MHVTL_KERNEL_CONFIG_H */\n' >> "${output}"
