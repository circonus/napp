#!/bin/sh
REV=$1
REV2=$2
URL1="https://svn.omniti.com/raas/napp/appliance-root"
URL2="https://svn.omniti.com/raas/napp/appliance-support"
if [ -z "$REV" ]; then
  REV=`svn info $URL1 | awk '/^Last Changed Rev:/{print $NF;}'`
fi
if [ -z "$REV2" ]; then
  REV2=`svn info $URL2 | awk '/^Last Changed Rev:/{print $NF;}'`
fi
VERSION="0.1r$REV"
VERSION2="0.1r$REV2"
NAME=circonus-napp
TOPDIR=$(rpm -E %{_topdir})
SRCFILE=${TOPDIR}/SOURCES/${NAME}-${VERSION}.tar.gz
SPECFILE=${TOPDIR}/SPECS/${NAME}.spec
if ! test -f ${SRCFILE}; then 
 rm -rf ${TOPDIR}/BUILD/${NAME}-${VERSION} \
 && svn export -q $URL1 ${TOPDIR}/BUILD/${NAME}-${VERSION} \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRCFILE} ${NAME}-${VERSION})
fi
NAME2=circonus-selinux-module
SRC2FILE=${TOPDIR}/SOURCES/${NAME2}-${VERSION2}.tar.gz
if ! test -f ${SRC2FILE}; then 
 rm -rf ${TOPDIR}/BUILD/${NAME2} \
 && svn export -q $URL2 ${TOPDIR}/BUILD/${NAME2} \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRC2FILE} ${NAME2})
fi
cp `dirname $0`/napp-httpd ${TOPDIR}/SOURCES/
cp `dirname $0`/issue-refresh-initscript.patch ${TOPDIR}/SOURCES/
sed -e "s/@@REV@@/$REV/" -e "s/@@REV2@@/$REV2/" -e "s/@@DEPLOY@@/$DEPLOY/" <<EOF  > $SPECFILE
%define		rversion	0.1r@@REV@@
%define		rrelease	0.5
Name:		circonus-napp
Version:	%{rversion}
Release:	%{rrelease}
Summary:	napp

Group:		Applications/System
License:	Proprietary commercial
Vendor:		Circonus
URL:		https://svn.omniti.com/trac/raas
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Source:		$NAME-$VERSION.tar.gz
Source1:	$NAME2-$VERSION2.tar.gz
Source2:	napp-httpd
Patch1:		issue-refresh-initscript.patch

BuildRequires:	rpm, coreutils
Requires(pre):	chkconfig
Requires(post): chkconfig
Requires(preun): chkconfig, sed
# for /sbin/service
Requires(preun): initscripts
# for /bin/rm
Requires(preun): coreutils
Requires:	mod_wsgi, circonus-noit-modules_prod, noit_prod, python-sqlite2, curl, httpd


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
%{__mkdir_p} \$RPM_BUILD_ROOT/etc/cron.d
%{__cp} -p etc/cron.d/napp \$RPM_BUILD_ROOT/etc/cron.d
%{__mkdir_p} \$RPM_BUILD_ROOT%{_initrddir}
%{__ln_s} /opt/napp/bin/issue-refresh \$RPM_BUILD_ROOT%{_initrddir}
%{__ln_s} /opt/napp/bin/noitd-ctlr \$RPM_BUILD_ROOT%{_initrddir}
%{__install} -m 0755 %SOURCE2 \$RPM_BUILD_ROOT/opt/napp/bin/napp-httpd
%{__mkdir_p} \$RPM_BUILD_ROOT/opt/napp/selinux
%{__install} -m 0755 circonus-selinux-module/selinux/napp.pp \$RPM_BUILD_ROOT/opt/napp/selinux/napp.pp
%{__ln_s} /opt/napp/bin/napp-httpd \$RPM_BUILD_ROOT%{_initrddir}
( cd \$RPM_BUILD_ROOT; find . -type d -name '.svn' | xargs rm -rf )


%clean
rm -rf \$RPM_BUILD_ROOT


%pre
/usr/sbin/semanage fcontext -a -t etc_t '/opt/napp/etc(/.*)?'


%post
if [ \$1 = 1 ]; then
  /sbin/chkconfig --add noitd-ctlr
  /sbin/chkconfig --add napp-httpd
  /sbin/chkconfig --add issue-refresh
  /sbin/service noitd-ctlr start
  /sbin/service napp-httpd start
  /sbin/service issue-refresh start
fi
semodule -i /opt/napp/selinux/napp.pp
restorecon -r /opt/napp/etc


%preun
if [ \$1 = 0 ]; then
  /sbin/chkconfig --del noitd-ctlr
  /sbin/chkconfig --del napp-httpd
  /sbin/chkconfig --del issue-refresh
  /sbin/service noitd-ctlr stop
  /sbin/service napp-httpd stop
  semodule -r napp
fi


%postun
if [ \$1 = 0 ]; then
  /usr/sbin/semanage fcontext -d -t etc_t "/opt/napp/etc"
fi


%files
%defattr(-,root,root,-)
%dir %{_initrddir}
%dir /opt
%dir /opt/django
/opt/django/*
%dir /opt/noit
%dir /opt/noit/prod
%dir /opt/noit/prod/etc/
%config(noreplace) /opt/noit/prod/etc/noit.conf
%dir /opt/napp
%attr(0755,nobody,root) %dir /opt/napp/etc
%attr(0755,nobody,root) /opt/napp/etc/check-for-updates
%attr(0755,nobody,root) %dir /opt/napp/etc/django-stuff
%attr(0755,nobody,root) %dir /opt/napp/etc/ssl
%attr(0755,nobody,root) %dir /opt/napp/etc/updatelogs
%attr(0644,nobody,root) /opt/napp/etc/django-stuff/napp_stub.sqlite.factory
%config(noreplace) %attr(0644,nobody,root) /opt/napp/etc/django-stuff/napp_stub.sqlite
%attr(0644,nobody,root) /opt/napp/etc/httpd.conf
%attr(0644,nobody,root) /opt/napp/etc/napp-openssl.cnf
%dir /opt/napp/base
%dir /opt/napp/bin
%dir /opt/napp/setup
%dir /opt/napp/templates
%dir /opt/napp/www
/opt/napp/base/*
/opt/napp/bin/*
/opt/napp/setup/*
/opt/napp/templates/*
/opt/napp/www/*
/opt/napp/*.py*
/opt/napp/napp.wsgi
/opt/napp/stub
/opt/napp/etc/ssl/ca.crt
/etc/rc.d/init.d/noitd-ctlr
/etc/rc.d/init.d/napp-httpd
/etc/rc.d/init.d/issue-refresh
/etc/cron.d/napp
/opt/napp/selinux/napp.pp


%changelog
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
rpmbuild -ba $SPECFILE
