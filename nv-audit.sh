#!/bin/sh
# nv-audit.sh - find what still routes GL/Vulkan/VA to nouveau/Mesa instead of NVIDIA.
# Run as your normal user, with the offending apps (Steam etc.) OPEN.
# Read-only; changes nothing.

VARS='__GLX_VENDOR_LIBRARY_NAME|__EGL_VENDOR_LIBRARY_(FILENAMES|DIRS)|VK_ICD_FILENAMES|VK_DRIVER_FILES|MESA_LOADER_DRIVER_OVERRIDE|LIBGL_ALWAYS_SOFTWARE|LIBGL_DRIVERS_PATH|DRI_PRIME|LIBVA_DRIVER_NAME|VDPAU_DRIVER|NOUVEAU_'

h() { printf '\n== %s ==\n' "$1"; }

h "kernel / binding"
uname -r
lsmod | grep -E '^(nouveau|nvidia)' || echo "(neither nouveau nor nvidia in lsmod)"
lspci -nnk -d 10de: | grep -E 'VGA|3D|Kernel driver in use|Kernel modules'

h "module vs userspace version (must match)"
head -1 /proc/driver/nvidia/version 2>/dev/null || echo "NO nvidia kernel module loaded"
nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1
dkms status 2>/dev/null | grep -i nvidia

h "nouveau blacklist + initramfs"
grep -rsn nouveau /etc/modprobe.d/ /usr/lib/modprobe.d/ /lib/modprobe.d/ || echo "NO nouveau blacklist found"
grep -o 'modprobe.blacklist=[^ ]*\|nouveau[^ ]*' /proc/cmdline
lsinitramfs "/boot/initrd.img-$(uname -r)" 2>/dev/null | grep -E '/nouveau|/nvidia' | sed 's/^/initrd: /'

h "installed NVIDIA packages by arch (amd64 and i386 versions must be identical)"
dpkg-query -W -f='${db:Status-Abbrev} ${Package}:${Architecture} ${Version}\n' \
  '*nvidia*' 'libcuda*' 'libnvcuvid*' 'libgl1-nvidia*' 'libegl-nvidia*' 'libgles-nvidia*' 2>/dev/null \
  | awk '$1=="ii"{print $2, $3}' | sort
dpkg --print-foreign-architectures | grep -q i386 || echo "!! i386 architecture NOT enabled (Steam needs it)"
dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' xserver-xorg-video-nouveau 2>/dev/null | awk '$1=="ii"{print "installed: "$2}'

h "GLVND / Vulkan vendor registrations"
ls -1 /usr/share/glvnd/egl_vendor.d/ /etc/glvnd/egl_vendor.d/ 2>/dev/null
ls -1 /usr/share/vulkan/icd.d/ /etc/vulkan/icd.d/ 2>/dev/null

h "Xorg driver actually used"
for l in /var/log/Xorg.0.log "$HOME/.local/share/xorg/Xorg.0.log"; do
  [ -r "$l" ] && grep -E 'LoadModule: "(nvidia|nouveau|modesetting|glx)"|nouveau|NVIDIA GLX Module' "$l" | sed "s|^|$(basename "$l"): |" | head -15
done

h "environment overrides (current shell)"
env | grep -E "^($VARS)" || echo "(none)"

h "environment overrides (files)"
grep -rsnE "$VARS" \
  "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.zprofile" \
  "$HOME/.xinitrc" "$HOME/.xsession" "$HOME/.xsessionrc" "$HOME/.xprofile" "$HOME/.pam_environment" \
  "$HOME/.config/i3/" "$HOME/.config/environment.d/" "$HOME/.local/share/applications/" \
  /etc/environment /etc/environment.d/ /etc/profile.d/ /etc/X11/Xsession.d/ /usr/share/applications/ \
  || echo "(none)"

h "Steam per-game launch options mentioning overrides"
for f in "$HOME"/.steam/steam/userdata/*/config/localconfig.vdf \
         "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf \
         "$HOME"/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata/*/config/localconfig.vdf; do
  [ -r "$f" ] && grep -nE "LaunchOptions.*($VARS|nouveau|mesa)" "$f" | sed "s|^|$f: |"
done

h "Flatpak GL extensions (must match kernel module version exactly)"
if command -v flatpak >/dev/null; then
  flatpak list --columns=application,branch,installation | grep -iE 'Platform\.GL|nvidia|steam' || echo "(none)"
else
  echo "(flatpak not installed)"
fi

h "live processes on the wrong path"
echo "PID     COMM                 NV  FALLBACK-LIBS"
for m in /proc/[0-9]*/maps; do
  pid=${m#/proc/}; pid=${pid%/maps}
  bad=$(grep -oE '(nouveau_dri|libGLX_mesa|swrast_dri|kms_swrast_dri|libvulkan_nouveau|nouveau_drv_video|libvdpau_nouveau)\.so[^ ]*' "$m" 2>/dev/null | sort -u | tr '\n' ' ')
  [ -z "$bad" ] && continue
  if grep -qE 'libGLX_nvidia|libnvidia-(glcore|eglcore)' "$m" 2>/dev/null; then nv=yes; else nv=NO; fi
  printf '%-7s %-20s %-3s %s\n' "$pid" "$(cat /proc/$pid/comm 2>/dev/null)" "$nv" "$bad"
done
echo
echo "NV=NO + nouveau_dri/libGLX_mesa/swrast  -> real fallback, that process is not on NVIDIA."
echo "NV=yes + swrast only                    -> usually harmless Mesa EGL probing."
echo "*_drv_video / vdpau_nouveau             -> VA-API/VDPAU video decode path (browsers, mpv)."
