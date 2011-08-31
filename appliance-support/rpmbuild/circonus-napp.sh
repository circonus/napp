#!/bin/sh
REV=$1
REV2=$2
URL1="https://svn.omniti.com/__raas__/napp/appliance-root"
URL2="https://svn.omniti.com/__raas__/napp/appliance-support"
URL3="https://svn.omniti.com/__raas__/service/trunk/htdocs"
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
rm -rf ${TOPDIR}/BUILD/${NAME}-${VERSION} ${SRCFILE} \
 && svn export --ignore-externals -q $URL1 ${TOPDIR}/BUILD/${NAME}-${VERSION} \
 && svn export --ignore-externals -q $URL3/c ${TOPDIR}/BUILD/${NAME}-${VERSION}/opt/napp/www/c \
 && svn export --ignore-externals -q $URL3/i ${TOPDIR}/BUILD/${NAME}-${VERSION}/opt/napp/www/i \
 && svn export --ignore-externals -q $URL3/s ${TOPDIR}/BUILD/${NAME}-${VERSION}/opt/napp/www/s \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRCFILE} ${NAME}-${VERSION})
NAME2=circonus-selinux-module
SRC2FILE=${TOPDIR}/SOURCES/${NAME2}-${VERSION2}.tar.gz
rm -rf ${TOPDIR}/BUILD/${NAME2} ${SRC2FILE} \
 && svn export -q $URL2 ${TOPDIR}/BUILD/${NAME2} \
 && (cd ${TOPDIR}/BUILD/ && tar zcf ${SRC2FILE} ${NAME2})
cp `dirname $0`/napp-httpd ${TOPDIR}/SOURCES/
cp `dirname $0`/issue-refresh-initscript.patch ${TOPDIR}/SOURCES/
sed -e "s/@@REV@@/$REV/" -e "s/@@REV2@@/$REV2/" -e "s/@@DEPLOY@@/$DEPLOY/" <<EOF  > $SPECFILE
%define		rversion	0.1r@@REV@@
%define		rrelease	0.2
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

BuildRequires:	rpm, coreutils, checkpolicy, policycoreutils
Requires(pre):	chkconfig
Requires(post): chkconfig
Requires(preun): chkconfig, sed
# for /sbin/service
Requires(preun): initscripts
# for /bin/rm
Requires(preun): coreutils
Requires:	mod_wsgi, noit_prod, python-sqlite2, curl, httpd


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
%{__mkdir_p} \$RPM_BUILD_ROOT/etc/cron.daily
%{__cp} -p etc/cron.d/napp \$RPM_BUILD_ROOT/etc/cron.d
%{__ln_s} /opt/napp/bin/crt-refresh \$RPM_BUILD_ROOT/etc/cron.daily
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
if test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
  /usr/sbin/semanage fcontext -a -t etc_t '/opt/napp/etc(/.*)?'
fi


%post
if [ \$1 = 1 ]; then
  /sbin/chkconfig --add noitd-ctlr
  /sbin/chkconfig --add napp-httpd
  /sbin/chkconfig --add issue-refresh
  if test -f /opt/napp/etc/noit.run; then 
     /sbin/service noitd-ctlr stop
     /sbin/service noitd-ctlr start
  fi
  /sbin/service napp-httpd condrestart
  /sbin/service issue-refresh start
fi
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
%dir %{_initrddir}
%dir /opt
%dir /opt/django
/opt/django/*
%dir /opt/noit
%dir /opt/noit/prod
%dir /opt/noit/prod/etc/
%config(noreplace) /opt/noit/prod/etc/noit.conf
/opt/noit/prod/etc/noit.conf.factory
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
/etc/cron.daily/crt-refresh
/opt/napp/selinux/napp.pp


%changelog
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
rpmbuild -bs --define "_source_filedigest_algorithm md5"  --define "_binary_filedigest_algorithm md5" $SPECFILE 
mock -r circonus-5-i386 ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2.src.rpm
cp /var/lib/mock/circonus-5-i386/result/circonus-5-i386/${NAME}-${VERSION}-0.2.i386.rpm /mnt/circonus/i386/RPMS/
mock -r circonus-5-x86_64 ${TOPDIR}/SRPMS/${NAME}-${VERSION}-0.2.src.rpm
cp /var/lib/mock/circonus-5-i386/result/circonus-5-x86_64/${NAME}-${VERSION}-0.2.x86_64.rpm /mnt/circonus/x86_64/RPMS/
/mnt/make-repo-metadata /mnt/circonus/
