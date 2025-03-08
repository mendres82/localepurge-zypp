#
# spec file for package zypper-upgraderepo-plugin
#
# Copyright (c) 2018 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

Name:           localepurge-zypp
Version:        0.3.2
Release:        0
Requires:       zypper >= 1.13.10
Url:            https://github.com/mendres82/localepurge-zypp
Source:         %{name}-%{version}.tar.xz
BuildArch:      noarch
Summary:        Zypper plugin that removes unnecessary locale files during package installation
License:        MIT
Group:          System/Packages

%description
This script is a plugin for the zypper package manager that removes unnecessary locale files
during package installation to save disk space.

%prep
%autosetup

%build

%install
mkdir -p %{buildroot}/usr/lib/zypp/plugins/commit %{buildroot}/etc
install -m 755 localepurge-zypp-plugin.sh %{buildroot}/usr/lib/zypp/plugins/commit/
install -m 644 localepurge-zypp.conf %{buildroot}/etc/

%files
/usr/lib/zypp
/usr/lib/zypp/plugins
/usr/lib/zypp/plugins/commit
%attr(0755,root,root) /usr/lib/zypp/plugins/commit/localepurge-zypp-plugin.sh
%attr(0644,root,root) %config(noreplace) /etc/localepurge-zypp.conf

%changelog
