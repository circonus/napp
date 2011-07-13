#!/bin/sh
NAME=circonus-release
TOPDIR=$(rpm -E %{_topdir})
YUMREPO=Circonus.repo
GPGKEY=RPM-GPG-KEY-CIRCONUS
SPECFILE=${TOPDIR}/SPECS/${NAME}.spec
URL="http://updates.circonus.com/circonus"
cat <<EOF >$SPECFILE
%define		rversion	0.1
%define		rrelease	0.1
Name:		circonus-release
Version:	%{rversion}
Release:	%{rrelease}
Summary:	yum-repo line and rpm signing key

Group:          System Environment/Base
License:	Proprietary commercial
URL:		${URL}

Source0:        ${URL}/${GPGKEY}
Source1:        ${YUMREPO}
Vendor:		Circonus

BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildArch:     noarch
Requires:      redhat-release >=  5


%description
This package contains the Packages for Enterprise Circonus Appliance 
repository GPG key as well as configuration for yum.

%prep
%setup -q  -c -T
install -pm 644 %{SOURCE0} .
install -pm 644 %{SOURCE1} .

%build


%install
rm -rf \$RPM_BUILD_ROOT

#GPG Key
install -Dpm 644 %{SOURCE0} \
    \$RPM_BUILD_ROOT%{_sysconfdir}/pki/rpm-gpg/${GPGKEY}

# yum
install -dm 755 \$RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d
install -pm 644 %{SOURCE1} \
    \$RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d

%clean
rm -rf \$RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%config(noreplace) /etc/yum.repos.d/*
/etc/pki/rpm-gpg/*

%changelog
* Wed Jul 13 2011 Sergey Ivanov <seriv@omniti.com> - 0.1-0.1
- initial release
EOF
cat <<EOF > ${TOPDIR}/SOURCES/${YUMREPO}
# ${YUMREPO}
#
[circonus]
name=Circonus - Base
gpgcheck=1
baseurl=http://updates.circonus.com/circonus/\$basearch/
EOF
rm -rf ${TOPDIR}/SOURCES/${GPGKEY} && curl -o ${TOPDIR}/SOURCES/${GPGKEY} ${URL}/${GPGKEY} 
rpmbuild -ba --sign $SPECFILE
