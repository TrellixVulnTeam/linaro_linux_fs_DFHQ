# The default profile installing local software packages used by aptdaemon
Profile: ubuntu/aptdaemon
Extends: debian/aptdaemon
Disable-Tags:
	FSSTND-dir-in-usr,
	FSSTND-dir-in-var,
	arch-dependent-file-in-usr-share,
        binary-file-compressed-with-upx,
	binary-or-shlib-defines-rpath,
        control-interpreter-in-usr-local,
	copyright-contains-dh_make-todo-boilerplate,
	copyright-file-compressed,
 	copyright-file-is-symlink,
	copyright-refers-to-incorrect-directory,
	copyright-refers-to-old-directory,
 	debian-rules-missing-required-target,
	debian-rules-not-a-makefile,
	description-is-dh_make-template,
	description-synopsis-is-empty,
	dir-or-file-in-srv,
	dir-or-file-in-var-www,
	embedded-library,
	extended-description-is-empty,
	file-in-etc-not-marked-as-conffile,
	file-in-usr-marked-as-conffile,
	install-info-used-in-maintainer-script,
 	library-in-debug-or-profile-should-not-be-stripped,
	magic-arch-in-arch-list,
	missing-build-dependency,
	mknod-in-maintainer-script,
	no-architecture-field,
	no-copyright-file,
 	no-maintainer-field,
	no-shlibs-control-file,
	package-installs-python-bytecode,
	section-is-dh_make-template,
	statically-linked-binary,
	udeb-uses-unsupported-compression-for-data-tarball,
 	uploader-address-is-on-localhost,
	uploader-address-malformed,
	uploader-name-missing,
	usr-share-doc-symlink-to-foreign-package,
	usr-share-doc-symlink-without-dependency,
