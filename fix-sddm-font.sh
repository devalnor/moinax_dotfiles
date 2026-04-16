#!/bin/bash
set -e

# Fix SDDM password bullet character by setting Noto Sans as the greeter font
# Run with: sudo ./fix-sddm-font.sh

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo"
    exit 1
fi

# Fix SDDM config — add Font to [Theme] section
tee /etc/sddm.conf.d/theme.conf > /dev/null <<EOF
[Theme]
Current=breeze
Font="Noto Sans"

[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=kwin_wayland --no-global-shortcuts --no-lockscreen --locale1
EOF

# Revert the wrong theme.conf.user (remove font line we added earlier)
if [ -f /usr/share/sddm/themes/breeze/theme.conf.user ]; then
    tee /usr/share/sddm/themes/breeze/theme.conf.user > /dev/null <<EOF
[General]
background=/usr/share/sddm/themes/breeze/wallpaper.jpg
EOF
fi

echo "Done. SDDM font set to Noto Sans. Reboot to see the change."
