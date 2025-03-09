# Localepurge Zypper Plugin

A zypper plugin that removes unused locale files after package installation to save disk space

## Overview

localepurge-zypp is a plugin for the openSUSE zypper package manager and automatically removes locale files that don't match your system's locale settings or should be kept. This helps reduce disk usage by eliminating unused translation files.

## Features

- Automatically removes locale files after package installation
- Respects your system's locale settings
- Configurable through simple configuration file
- Minimal performance impact during package operations
- Compatible with zypper and YaST

## Installation

1. Clone the git repository:

```bash
git clone https://github.com/mendres82/localepurge-zypp
```

2. Install the plugin:

```bash
cd localepurge-zypp
sudo cp localepurge-zypp-plugin.sh /usr/lib/zypp/plugins/commit
sudo chmod +x /usr/lib/zypp/plugins/commit/localepurge-zypp-plugin.sh
sudo cp localepurge-zypp.conf /etc
```

3. Configure the plugin:

Edit the `/etc/localepurge-zypp.conf` file to specify the locales you want to keep.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.


