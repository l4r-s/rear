
# This file is part of Relax and Recover, licensed under the GNU General
# Public License. Refer to the included LICENSE for full text of license.

# Add the rescue kernel and initrd to the local GRUB 2 bootloader.

# Only do it when explicitly enabled:
is_true "$GRUB_RESCUE" || return

# Only run this script when GRUB 2 is there
# (grub-probe or grub2-probe only exist in GRUB 2)
# in particular do not run this script when GRUB Legacy is used
# (for GRUB Legacy output/default/94_grub_rescue.sh is run):
type -p grub-probe >&2 || type -p grub2-probe >&2 || { LogPrint "Skipping GRUB_RESCUE setup for GRUB 2 (no GRUB 2 found)." ; return ; }

# Now GRUB_RESCUE is explicitly wanted and this script is the right one to set it up.
LogPrint "Setting up GRUB_RESCUE: Adding Relax-and-Recover rescue system to the local GRUB 2 configuration."
# Now error out whenever it cannot setup the GRUB_RESCUE functionality.

# Either grub-mkpasswd-pbkdf2 or grub2-mkpasswd-pbkdf2 is required:
local grub_mkpasswd_binary=""
has_binary grub-mkpasswd-pbkdf2 && grub_mkpasswd_binary=$( get_path grub-mkpasswd-pbkdf2 )
has_binary grub2-mkpasswd-pbkdf2 && grub_mkpasswd_binary=$( get_path grub2-mkpasswd-pbkdf2 )
test "$grub_mkpasswd_binary" || Error "Cannot setup GRUB_RESCUE: Neither grub-mkpasswd-pbkdf2 nor grub2-mkpasswd-pbkdf2 found."

### Use strings as grub --version syncs all disks
#grub_version=$(get_version "grub --version")
# FIXME:
# This works with GRUB Legacy
# e.g. on my <jsmeix@suse.de> SLES11 system:
#   # strings /usr/sbin/grub | sed -rn 's/^[^0-9\.]*([0-9]+\.[-0-9a-z\.]+).*$/\1/p' | tail -n 1
#   0.97
#   # /usr/sbin/grub --version
#   grub (GNU GRUB 0.97)
#   # rpm -q grub
#   grub-0.97-162.172.1
# But it does no longer result the right version when grub_mkpasswd_binary is uesd
# e.g. on my <jsmeix@suse.de> SLES12 system:
#   # strings /usr/bin/grub2-mkpasswd-pbkdf2 | sed -rn 's/^[^0-9\.]*([0-9]+\.[-0-9a-z\.]+).*$/\1/p' | tail -n 1
#   1.2.840.113549.1.1.12
#   # /usr/bin/grub2-mkpasswd-pbkdf2 --version
#   /usr/bin/grub2-mkpasswd-pbkdf2 (GRUB2) 2.02~beta2
#   # rpm -q grub2
#   grub2-2.02~beta2-69.1.x86_64
# Because this works on my <jsmeix@suse.de> SLES12 system:
#   # strings /usr/bin/grub2-mkpasswd-pbkdf2 | grep '^2\.' | head -n 1
#   2.02~beta2
# I <jsmeix@suse.de> simply use that for now until someone provides a better solution:
local grub_version=$( strings $grub_mkpasswd_binary | grep '^2\.' | head -n 1 )
test "$grub_version" || Error "Cannot setup GRUB_RESCUE: It seems '$grub_mkpasswd_binary' is of unsupported version 'grub_version'."

# Ensure that kernel and initrd are there:
test -r "$KERNEL_FILE" || Error "Cannot setup GRUB_RESCUE: Cannot read kernel file '$KERNEL_FILE'."
test -r "$TMP_DIR/initrd.cgz" || Error "Cannot setup GRUB_RESCUE: Cannot read initrd '$TMP_DIR/initrd.cgz'."

# Esure there is sufficient disk space in /boot for the local Relax-and-Recover rescue system:
function total_filesize {
    stat --format '%s' $@ | awk 'BEGIN { t=0 } { t+=$1 } END { print t }'
}
local available_space=$(df -Pkl /boot | awk 'END { print $4 * 1024 }')
local used_space=$(total_filesize /boot/rear-kernel /boot/rear-initrd.cgz)
local required_space=$(total_filesize $KERNEL_FILE $TMP_DIR/initrd.cgz)
if (( available_space + used_space < required_space )) ; then
    required_MiB=$(( required_space / 1024 / 1024 ))
    available_MiB=$(( ( available_space + used_space ) / 1024 / 1024 ))
    Error "Cannot setup GRUB_RESCUE: Not enough disk space in /boot for Relax-and-Recover rescue system. Required: $required_MiB MiB. Available: $available_MiB MiB."
fi

# Ensure a GRUB2 configuration file is found:
local grub_conf=""
if is_true $USING_UEFI_BOOTLOADER ; then
    # set to 1 means using UEFI
    grub_conf="$( dirname $UEFI_BOOTLOADER )/grub.cfg"
elif has_binary grub2-probe ; then
    grub_conf=$( readlink -f /boot/grub2/grub.cfg )
else
    grub_conf=$( readlink -f /boot/grub/grub.cfg )
fi
test -w "$grub_conf" || Error "Cannot setup GRUB_RESCUE: GRUB 2 configuration '$grub_conf' cannot be modified."

# Set up GRUB 2 password protection if enabled:
if test "$GRUB_RESCUE_PASSWORD" ; then
    # When GRUB_RESCUE_USER is not specified, use by default GRUB_SUPERUSER (by default GRUB_SUPERUSER is empty):
    test "$GRUB_RESCUE_USER" || GRUB_RESCUE_USER="$GRUB_SUPERUSER"
    test "$GRUB_RESCUE_USER" || Error "Non-empty GRUB_RESCUE_PASSWORD requires that a GRUB_RESCUE_USER is specified."
    LogPrint "Setting up GRUB 2 password protection with GRUB 2 user '$GRUB_RESCUE_USER'".
    local grub_rescue_password_PBKDF2_hash=""
    # Make a PBKDF2 hash of the GRUB_RESCUE_PASSWORD if it is not yet in this form:
    if [[ "${GRUB_RESCUE_PASSWORD:0:11}" == 'grub.pbkdf2' ]] ; then
        grub_rescue_password_PBKDF2_hash="$GRUB_RESCUE_PASSWORD"
    else
        grub_rescue_password_PBKDF2_hash="$( echo -e "$GRUB_RESCUE_PASSWORD\n$GRUB_RESCUE_PASSWORD" | $grub_mkpasswd_binary | grep -o 'grub.pbkdf2.*' )"
    fi
    # Ensure the password is in the form of a PBKDF2 hash:
    if [[ ! "${grub_rescue_password_PBKDF2_hash:0:11}" == 'grub.pbkdf2' ]] ; then
        Error "Cannot setup GRUB_RESCUE: GRUB 2 password '${grub_rescue_password_PBKDF2_hash:0:40}...' seems to be not in the form of a PBKDF2_hash."
    fi
    # Set up a GRUB 2 superuser if enabled:
    LogPrint "Setting up GRUB 2 superuser '$GRUB_SUPERUSER'."
    if test "$GRUB_SUPERUSER" ; then
        local grub_users_file="/etc/grub.d/01_users"
        if [[ ! -f $grub_users_file ]] ; then
            ( echo "#!/bin/sh"
              echo "cat << EOF"
              echo "set superusers=\"$GRUB_SUPERUSER\""
              echo "password_pbkdf2 $GRUB_SUPERUSER $grub_rescue_password_PBKDF2_hash"
              echo "EOF"
            ) > $grub_users_file
        fi
        local grub_pass_set=$( tail -n 4 $grub_users_file | grep -E "cat|set superusers|password_pbkdf2|EOF" | wc -l )
        if [[ $grub_pass_set < 4 ]] ; then
            ( echo "#!/bin/sh"
              echo "cat << EOF"
              echo "set superusers=\"$GRUB_SUPERUSER\""
              echo "password_pbkdf2 $GRUB_SUPERUSER $grub_rescue_password_PBKDF2_hash"
              echo "EOF"
            ) > $grub_users_file
        fi
        local grub_super_set=$( grep 'set superusers' $grub_users_file | cut -f2 -d '"' )
        if [[ ! $grub_super_set == $GRUB_SUPERUSER ]] ; then
            sed -i "s/set superusers=\"\S*\"/set superusers=\"$GRUB_SUPERUSER\"/" $grub_users_file
            sed -i "s/password_pbkdf2\s\S*\s\S*/password_pbkdf2 $GRUB_SUPERUSER $grub_rescue_password_PBKDF2_hash/" $grub_users_file
        fi
        local grub_enc_password=$( grep "password_pbkdf2" $grub_users_file | awk '{print $3}' )
        if [[ ! $grub_enc_password == $grub_rescue_password_PBKDF2_hash ]] ; then
            sed -i "s/password_pbkdf2\s\S*\s\S*/password_pbkdf2 $GRUB_SUPERUSER $grub_rescue_password_PBKDF2_hash/" $grub_users_file
        fi
        # Ensure the grub users file is executable:
        test -x $grub_users_file || chmod 755 $grub_users_file
    fi
fi

# Finding UUID of filesystem containing /boot
grub_boot_uuid=$( df /boot | awk 'END {print $1}' | xargs blkid -s UUID -o value )

# Stop if $grub_boot_uuid is not a valid UUID
blkid -U $grub_boot_uuid > /dev/null 2>&1 || Error "$grub_boot_uuid is not a valid UUID"

# Creating Relax-and-Recover grub menu entry:
local grub_rear_menu_entry_file="/etc/grub.d/45_rear"
  ( echo "#!/bin/bash"
    echo "cat << EOF"
    echo "menuentry \"Relax-and-Recover\" --class os --users \"\" {"
    echo "          search --no-floppy --fs-uuid  --set=root $grub_boot_uuid"
    echo "          linux  /boot/rear-kernel $KERNEL_CMDLINE"
    echo "          initrd /boot/rear-initrd.cgz"
  ) > $grub_rear_menu_entry_file
if test "$grub_rescue_password_PBKDF2_hash" ; then
    # Specify GRUB 2 password protection if enabled:
    echo "          password_pbkdf2 $GRUB_RESCUE_USER $grub_rescue_password_PBKDF2_hash" >> $grub_rear_menu_entry_file
fi
  ( echo "}"
    echo "EOF"
  ) >> $grub_rear_menu_entry_file
chmod 755 $grub_rear_menu_entry_file

# Generate a GRUB 2 configuration file:
if [[ $( type -f grub2-mkconfig ) ]] ; then
    grub2-mkconfig -o $TMP_DIR/grub.cfg || Error "Failed to generate GRUB 2 configuration file (using grub2-mkconfig)."
else
    grub-mkconfig -o $TMP_DIR/grub.cfg || Error "Failed to generate GRUB 2 configuration file (using grub-mkconfig)."
fi
test -s $TMP_DIR/grub.cfg || BugError "Generated empty GRUB 2 configuration file '$TMP_DIR/grub.cfg'"

# Modifying local GRUB 2 configuration if it was actually changed:
if ! diff -u $grub_conf $TMP_DIR/grub.cfg >&2 ; then
    LogPrint "Modifying local GRUB 2 configuration."
    cp -af $v $grub_conf $grub_conf.old >&2
    cat $TMP_DIR/grub.cfg >$grub_conf
fi

# Provide the kernel as /boot/rear-kernel
if [[ $( stat -L -c '%d' $KERNEL_FILE ) == $( stat -L -c '%d' /boot/ ) ]] ; then
    # Hardlink file, if possible:
    cp -pLlf $v $KERNEL_FILE /boot/rear-kernel >&2
elif [[ $( stat -L -c '%s %Y' $KERNEL_FILE ) == $( stat -L -c '%s %Y' /boot/rear-kernel ) ]] ; then
    # If an already existing /boot/rear-kernel has exact same size and modification time
    # as the current KERNEL_FILE, assume both are the same and do nothing:
    :
else
    # In all other cases, replace /boot/rear-kernel with the current KERNEL_FILE:
    cp -pLf $v $KERNEL_FILE /boot/rear-kernel >&2
fi
BugIfError "Unable to copy '$KERNEL_FILE' to /boot"

# Provide the rear recovery system in TMP_DIR/initrd.cgz as /boot/rear-initrd.cgz
cp -af $v $TMP_DIR/initrd.cgz /boot/rear-initrd.cgz >&2 || BugError "Unable to copy '$TMP_DIR/initrd.cgz' to /boot"

LogPrint "Finished GRUB_RESCUE setup: Added 'Relax-and-Recover' GRUB 2 menu entry."

