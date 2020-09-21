
#!/bin/bash

name=$1
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "${CYAN}Installing packages...${NC}"
pacman -S --noconfirm gnome firefox emacs gnome-tweaks sudo lightdm
systemctl enable lightdm.service

echo "${CYAN}Installing doom emacs...${NC}"
sudo -U $name git clone --depth 1 https://github.com/hlissner/doom-emacs ~/.emacs.d
sudo -U $name /home/$name/.emacs.d/bin/doom install

echo "${CYAN}Installing material shell..${NC}"
mshell_path=/home/$name/.local/share/gnome-shell/extensions/material-shell@papyelgringo
sudo -U $name git clone https://github.com/material-shell/material-shell.git $mshell_path
cd $mshell_path
sudo -U $name makepkg -si
sudo -U $name gnome-extensions enable material-shell@papyelgringo

echo "${CYAN}Changing gnome settings...${NC}"
sudo -U $name gsettings set org.gnome.shell.extensions.user-theme name "Adwaita Dark"
sudo -U $name gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'ch'), ('xkb', 'us')]"
sudo -U $name gdbus call --session --dest org.gnome.Shell \
    --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Eval \
    "imports.ui.status.keyboard.getInputSourceManager().inputSources[0].activate()"
