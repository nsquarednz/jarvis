#
# Call this makefile from the top-level jarvis checkout - like
#
# make -f pkg/rpm/Makefile

PACKAGE=jarvis
ROOT=/usr/share/jarvis

all: rpms

clean:
	-rm -rf *~ *.tar
	-rm -rf rpm-build/ rpms/

uninstall_rpms: clean
	-rpm -e ${PACKAGE}

sdist: clean
	tar cf ${PACKAGE}.tar --exclude=CVS --exclude=.hg --exclude=pkg --exclude=BUILDROOT *

rpms: sdist
	mkdir -p rpms
	rpmbuild -v --define "_topdir %(pwd)" \
		--define "_builddir %{_topdir}" \
		--define "_rpmdir %(pwd)/rpms" \
		--define "_srcrpmdir %{_rpmdir}" \
		--define "_sourcedir %(pwd)" \
		-ba pkg/rpm/${PACKAGE}.spec

# Install is called by 'rpms' via rpmbuild

install:
	mkdir -p ${DESTDIR}/${ROOT}/
	mkdir -p ${DESTDIR}/etc/httpd/conf.d/
	mkdir -p ${DESTDIR}/etc/jarvis/
	tar xvf ${PACKAGE}.tar -C ${DESTDIR}/${ROOT}/
	cp ${DESTDIR}/${ROOT}/etc/apache/jarvis.conf ${DESTDIR}/etc/httpd/conf.d/jarvis.conf
	touch ${DESTDIR}/etc/jarvis/jarvis-app-config-goes-here.txt


