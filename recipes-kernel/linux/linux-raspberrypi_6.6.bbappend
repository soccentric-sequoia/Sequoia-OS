# Workaround for rpi-6.6.y being force-pushed: the commit pinned in the recipe
# may no longer exist in the branch history. Switch to nobranch=1 so BitBake
# skips the "revision must be in branch" validation and fetches cleanly.

# Replace the machine SRC_URI entry with one that has nobranch=1
SRC_URI:remove = "git://github.com/raspberrypi/linux.git;name=machine;branch=${KBRANCH};protocol=https"
SRC_URI:append = " git://github.com/raspberrypi/linux.git;name=machine;nobranch=1;protocol=https"

# Pin to the current HEAD of rpi-6.6.y (update when meta-raspberrypi is bumped)
SRCREV_machine:raspberrypi5 = "bba53a117a4a5c29da892962332ff1605990e17a"
SRCREV_machine               = "bba53a117a4a5c29da892962332ff1605990e17a"

# Disable shallow fetching — avoids the commit-reachability check race
BB_GIT_SHALLOW:pn-linux-raspberrypi = "0"

# The pinned commit is 6.6.78 but the recipe PV is 6.6.63 — skip the mismatch check
KERNEL_VERSION_SANITY_SKIP = "1"
