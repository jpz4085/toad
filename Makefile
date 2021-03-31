PREFIX?=	/usr/local
BINDIR= 	${PREFIX}/libexec
MANDIR= 	${PREFIX}/man/man
SHAREDIR=	${PREFIX}/share
EXAMPLEDIR=	${SHAREDIR}/examples/toad

PROG=		toadd
MAN=		toad.8 toadd.8

INSTALL_DIR=	install -d -o root -g wheel -m 755
INSTALL_SCRIPT=	install -c -S -o root -g bin -m 555

CPPFLAGS+=	-DLIBEXECDIR=\"${BINDIR}\"
LDADD= 		-lutil

WARNINGS=	Yes
CFLAGS+=	-Werror

CLEANFILES=	hotplug-scripts

all:
	sed -e 's,@PREFIX@,${PREFIX},g' ${.CURDIR}/hotplug-scripts.in > \
		${.CURDIR}/hotplug-scripts

afterinstall:
	${INSTALL_DIR} -d ${DESTDIR}${EXAMPLEDIR}
	${INSTALL_SCRIPT} ${.CURDIR}/hotplug-scripts ${DESTDIR}${EXAMPLEDIR}
	${INSTALL_SCRIPT} ${.CURDIR}/toad.pl ${DESTDIR}${BINDIR}/toad

maninstall:
	makewhatis ${PREFIX}/man

uninstall:
	rm ${DESTDIR}${BINDIR}/toad ${DESTDIR}${BINDIR}/${PROG}
	rm ${DESTDIR}${MANDIR}8/toad.8 ${DESTDIR}${MANDIR}8/toadd.8
	rm -r ${EXAMPLEDIR}
	makewhatis ${PREFIX}/man

.include <bsd.prog.mk>
