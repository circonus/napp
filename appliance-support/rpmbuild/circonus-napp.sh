#!/bin/sh

RELMAJOR=`cat /etc/redhat-release | awk '{ print substr($3,0,1) }'`

# check permissions
if [ "x$RELMAJOR" == "x5" ]; then
    for i in `find /mnt/circonus/centos/${RELMAJOR}/i386 -not -user mocker`; do
       test -w $i || echo "fix ownership/permissions for <$i>" && exit 1
    done
fi

for i in `find /mnt/circonus/centos/${RELMAJOR}/x86_64 -not -user mocker`; do
   test -w $i || echo "fix ownership/permissions for <$i>" && exit 1
done

NAME=circonus-napp

# This is used to set the dist macro in rpmbuild and mock
# CentOS 5 buildsys-macros sets %{dist} to ".el5.centos" and we just want ".el5"
if [ "x$RELMAJOR" == "x5" ]; then
   DIST=".el5"
else
   DIST=$(rpm -E %{?dist})
fi

TOPDIR=$(rpm -E %{_topdir})

rm -rf ${TOPDIR}/BUILD/napp \
 && git clone src@src.omniti.com:~circonus/field/napp ${TOPDIR}/BUILD/napp

if [ -z "$REV" ]; then
  REV=`(cd ${TOPDIR}/BUILD/napp && git show --format=%at | head -1)`
fi
if [ -z "$REV2" ]; then
  REV2=`(cd ${TOPDIR}/BUILD/napp && git show --format=%at | head -1)`
fi

# This is used to set the dist macro in rpmbuild and mock
# CentOS 5 buildsys-macros sets %{dist} to ".el5.centos" and we just want ".el5"
if [ "x$RELMAJOR" == "x5" ]; then
   DIST=".el5"
else
   DIST=$(rpm -E %{?dist})
fi

VERSION="0.1r$REV"
VERSION2="0.1r$REV2"

SRCFILE=${TOPDIR}/SOURCES/${NAME}-${VERSION}.tar.gz
SPECFILE=${TOPDIR}/SPECS/${NAME}.spec
rm -rf ${TOPDIR}/BUILD/${NAME}-${VERSION} ${SRCFILE} \
 && mv ${TOPDIR}/BUILD/napp/appliance-root ${TOPDIR}/BUILD/${NAME}-${VERSION} \
 && mkdir ${TOPDIR}/BUILD/${NAME}-${VERSION}/opt/napp/etc/updatelogs \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRCFILE} ${NAME}-${VERSION})
NAME2=circonus-selinux-module
SRC2FILE=${TOPDIR}/SOURCES/${NAME2}-${VERSION2}.tar.gz
rm -rf ${TOPDIR}/BUILD/${NAME2} ${SRC2FILE} \
 && mv ${TOPDIR}/BUILD/napp/appliance-support ${TOPDIR}/BUILD/${NAME2} \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRC2FILE} ${NAME2})
cp `dirname $0`/napp-httpd ${TOPDIR}/SOURCES/
cp `dirname $0`/issue-refresh-initscript.patch ${TOPDIR}/SOURCES/
sed -e "s/@@REV@@/$REV/" -e "s/@@REV2@@/$REV2/" -e "s/@@DEPLOY@@/$DEPLOY/" <<EOF  > $SPECFILE
%define		rversion	0.1r@@REV@@
%define		rrelease	0.2
Name:		circonus-napp
Version:	%{rversion}
Release:	%{rrelease}%{?dist}
Summary:	napp

Group:		Applications/System
License:	Proprietary commercial
Vendor:		Circonus
URL:		http://circonus.com/
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Source:		$NAME-$VERSION.tar.gz
Source1:	$NAME2-$VERSION2.tar.gz
Source2:	napp-httpd
Patch1:		issue-refresh-initscript.patch

BuildRequires:	rpm, coreutils, checkpolicy, policycoreutils
Requires(pre):	chkconfig
Requires(post): chkconfig
Requires(preun): chkconfig, sed
# for /sbin/service
Requires(preun): initscripts
# for /bin/rm
Requires(preun): coreutils
Requires:	mod_wsgi, noit_prod, python-sqlite2, m2crypto, curl, httpd

%if 0%{?rhel} == 6
Requires:	policycoreutils-python
%endif

%description
Napp is a package with Enterprise Appliance files


%policy
%module /opt/napp/selinux/napp.pp
  Name: napp
  Types: targeted


%prep
rm -rf %{name}-%{rversion}
%setup -q -n %{name}-%{rversion}
%setup -q -T -D -a 1 %{name}-%{rversion}
%patch1 -p1
%build
(cd circonus-selinux-module/selinux 
 ./mk-napp-policy)


%install
%{__rm} -rf \$RPM_BUILD_ROOT
%{__mkdir} \$RPM_BUILD_ROOT
%{__cp} -pr opt \$RPM_BUILD_ROOT
%{__mkdir_p} \$RPM_BUILD_ROOT/opt/napp/selinux
%{__install} -m 0755 circonus-selinux-module/selinux/napp.pp \$RPM_BUILD_ROOT/opt/napp/selinux/napp.pp
( cd \$RPM_BUILD_ROOT; find . -type d -name '.svn' | xargs rm -rf )


%clean
rm -rf \$RPM_BUILD_ROOT


%pre
if test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
  /usr/sbin/semanage fcontext -a -t etc_t '/opt/napp/etc(/.*)?'
fi


%post
if test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
  semodule -i /opt/napp/selinux/napp.pp
  restorecon -r /opt/napp/etc
fi


%preun
if [ \$1 = 0 ]; then
  /sbin/chkconfig --del noitd-ctlr
  /sbin/chkconfig --del napp-httpd
  /sbin/chkconfig --del issue-refresh
  /sbin/service noitd-ctlr stop
  /sbin/service napp-httpd stop
  if test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
    semodule -r napp
  fi
fi


%postun
if [ \$1 = 0 ]; then
  if test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
    /usr/sbin/semanage fcontext -d -t etc_t "/opt/napp/etc"
  fi
fi


%files
%defattr(-,root,root,-)
%dir /opt
%dir /opt/noit
%dir /opt/noit/prod
%dir /opt/noit/prod/etc/
%config(noreplace) /opt/noit/prod/etc/noit.conf
/opt/noit/prod/etc/noit.conf.factory
%dir /opt/napp
%attr(0755,nobody,root) %dir /opt/napp/etc
%attr(0755,nobody,root) /opt/napp/etc/check-for-updates
%attr(0755,nobody,root) %dir /opt/napp/etc/ssl
%dir /opt/napp/bin
%dir /opt/napp/noitweb
%dir /opt/napp/www
/opt/napp/bin/*
/opt/napp/noitweb/*
/opt/napp/www/*
/opt/napp/etc/*
/opt/napp/etc/ssl/ca.crt
/opt/napp/selinux/napp.pp


%changelog
* Fri Aug 10 2012 Eric Sproul <esproul@omniti.com> - 0.1r1339085555-0.2
- fix dependency for el6, add dist name
* Fri Aug 12 2011 Sergey Ivanov <seriv@omniti.com> - 0.1r8614-0.2
- fix typo
* Mon May 23 2011 Sergey Ivanov <seriv@omniti.com> - 0.1r8614-0.1
- link crt-refresh to /etc/cron.daily
* Wed Dec 22 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r6841-0.1
- fix scripts to work in case selinux disabled
* Tue Jul 27 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r5470-0.2
- removed requires to circonus-noit-modules as obsolete
* Thu Jun 3 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r5079-0.1
- tid12581, condrestart after install/upgrade;
  don't rely on source revision number due to potential changes in external repos
* Thu Apr 29 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r4807-0.3
- fix fcontext pattern: '/opt/napp/etc(/.*)?'
* Thu Apr 29 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r4807-0.2
- added restorecon call in postinstall script; applied fcontext to /opt/napp/etc
* Fri Apr 09 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r4340-0.1
- added requirements for httpd and curl
* Mon Mar 22 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r4005-0.1
- svn changes and fix install path for crontab
* Mon Mar 22 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r3999-0.3
- semodule -u can't update to the same version, -i works.
  /opt/napp/etc/django-stuff/napp_stub.sqlite should be preserved if touched by user
* Mon Mar 22 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r3711-0.2
- Set selinux context etc_t for everything under /opt/noit/etc/
* Wed Mar 10 2010 Sergey Ivanov <seriv@omniti.com> - 0.1r3711-0.1
- Initial package.
EOF

rpmbuild -bs --define "_source_filedigest_algorithm md5"  --define "_binary_filedigest_algorithm md5" --define "dist $DIST" $SPECFILE 

if [ "x$RELMAJOR" == "x5" ]; then
    echo "Mocking: mock -r circonus-${RELMAJOR}-i386 --define=\"dist $DIST\" ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2${DIST}.src.rpm"
    mock -r circonus-${RELMAJOR}-i386 --define="dist $DIST" ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2${DIST}.src.rpm
    cp /var/lib/mock/circonus-${RELMAJOR}-i386/result/${NAME}-${VERSION}-0.2${DIST}.i386.rpm /mnt/circonus/centos/${RELMAJOR}/i386/RPMS/
fi

echo "Mocking: mock -r circonus-${RELMAJOR}-x86_64 --define=\"dist $DIST\" ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2${DIST}.src.rpm"
mock -r circonus-${RELMAJOR}-x86_64 --define="dist $DIST" ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2${DIST}.src.rpm
cp /var/lib/mock/circonus-${RELMAJOR}-x86_64/result/${NAME}-${VERSION}-0.2${DIST}.x86_64.rpm /mnt/circonus/centos/${RELMAJOR}/x86_64/RPMS/

/mnt/make-repo-metadata /mnt/circonus/centos/${RELMAJOR}
