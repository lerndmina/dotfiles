 
# Dotfiles

This repository contains my personal dotfiles. They are managed using [GNU Stow](https://www.gnu.org/software/stow/), a free, portable, lightweight symlink farm manager. This allows the dotfiles to be organized in a clean way, while also being easily stowable to the home directory.

## Getting Started

## Installing GNU Stow

Depending on your Linux distribution, the command to install GNU Stow may vary:

- **Ubuntu/Debian**:

```bash
sudo apt-get install stow
```

- **Fedora**:

```bash
sudo dnf install stow
```

- **Arch Linux**:

```bash
sudo pacman -S stow
```

- **openSUSE**:

```bash
sudo zypper install stow
```

After installing, you can verify the installation by running:

```bash
stow --version
```

## Installation

1. Clone this repository into your home directory:

```bash
cd ~
git clone https://github.com/yourusername/dotfiles.git
```

2. Navigate into the dotfiles directory:

```bash
cd dotfiles
```

3. Use GNU Stow to symlink the dotfiles to your home directory. For example, to stow the vim dotfiles, you would type:

```bash
stow vim
```

This will create symlinks for all the vim dotfiles into your home directory.

Repeat this step for every package you want to stow.