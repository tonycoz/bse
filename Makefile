VERSION=0.18
DISTNAME=bse-$(VERSION)
DISTBUILD=$(DISTNAME)
DISTTAR=../$(DISTNAME).tar
DISTTGZ=$(DISTTAR).gz
WEBBASE=/home/httpd/html/bse

help:
	@echo make dist - build the tar.gz file and copy to distribution directory
	@echo make 'archive - build the tar.gz (in the parent directory)'
	@echo make clean - delete generated files
	@echo make distdir - build distribution directory
	@echo make docs - build documentation
	@echo make testup - upgrade an installation

# this target needs to be modified so that the output directory includes
# the release number
dist: cleantree $(DISTTGZ)
	cp $(DISTTGZ) $(WEBBASE)/dists/
	cp site/docs/bse.html $(WEBBASE)/relnotes/bse-$(VERSION).html
	cp site/docs/*.html $(WEBBASE)/docs
	svn cp . http://svn.develop-help.com/devsvn/bse/tags/bse-$(VERSION)

# make sure everything is committed
cleantree:
	if grep -q 'perl.*-d:ptkdb' site/cgi-bin/*.pl site/cgi-bin/admin/*.pl ; \
	  then echo '***' The debugger is still enabled ; \
	  exit 1; \
	fi
	test -z "`svn status`" || ( echo "Uncommitted files in the tree"; exit 1 )

archive: $(DISTTGZ)

$(DISTTGZ): distdir
	if [ -e $(DISTTGZ) ] ; \
	  then echo $(DISTTGZ) already exists ; \
	       exit 1 ; \
	fi
	tar cf $(DISTTAR) $(DISTBUILD)
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	gzip $(DISTTAR)

#	tar czf $(DISTFILE) -C .. bse --exclude '*~' --exclude '*,v' --exclude 'pod2html-*cache'

# recent ExtUtils::Manifest don't copy the executable bit, fix that here

distdir: docs dbinfo version
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	perl -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	mkdir $(DISTBUILD)/site/htdocs/shop
	find $(DISTBUILD) -type f | xargs chmod u+w
	for i in `cat MANIFEST` ; do if [ -x $$i ] ; then chmod a+x $(DISTBUILD)/$$i ; fi ; done

clean:
	-perl -MExtUtils::Command -e rm_f site/htdocs/index.html site/htdocs/shop/*.html site/htdocs/a/*.html
	-cd site/htdocs/images ; \
	for i in *.gif ; do \
	  if [ $$i != trans_pixel.gif ] ; then \
	    rm $$i ; \
	  fi ; \
	done
	-perl -MExtUtils::Command -e rm_f site/htdocs/images/*.jpg
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)

docs: INSTALL.txt INSTALL.html otherdocs

INSTALL.txt: INSTALL.pod
	pod2text <INSTALL.pod >INSTALL.txt

INSTALL.html: INSTALL.pod
	pod2html --infile=INSTALL.pod --outfile=INSTALL.html
	-rm pod2html-dircache pod2html-itemcache

otherdocs:
	cd site/docs ; make all

dbinfo: site/util/mysql.str

site/util/mysql.str: schema/bse.sql
	perl schema/mysql_build.pl >site/util/mysql.str

version: site/cgi-bin/modules/BSE/Version.pm

site/cgi-bin/modules/BSE/Version.pm: Makefile
	echo 'package BSE::Version;' >site/cgi-bin/modules/BSE/Version.pm
	echo 'use strict;' >>site/cgi-bin/modules/BSE/Version.pm
	echo  >>site/cgi-bin/modules/BSE/Version.pm
	echo 'my $$VERSION = "$(VERSION)";' >>site/cgi-bin/modules/BSE/Version.pm
	echo  >>site/cgi-bin/modules/BSE/Version.pm
	echo 'sub version { $$VERSION }' >>site/cgi-bin/modules/BSE/Version.pm
	echo  >>site/cgi-bin/modules/BSE/Version.pm
	echo '1;' >>site/cgi-bin/modules/BSE/Version.pm

svnversion:
	perl site/util/bse_mksvnversion.pl $(VERSION) site/cgi-bin/modules/BSE/Version.pm

# this is very rough
testinst: distdir
	perl localinst.perl $(DISTBUILD)
	perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	cd `perl -lne 'do { print $$1; exit; } if /^base_dir\s*=\s*(.*)/' test.cfg`/util ; perl loaddata.pl ../data/db

testup: distdir
	perl localinst.perl $(DISTBUILD) leavedb
	perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	cd `perl -lne 'do { print $$1; exit; } if /^base_dir\s*=\s*(.*)/' test.cfg`/util ; perl upgrade_mysql.pl -b ; perl loaddata.pl ../data/db

test: testinst
	perl -MTest::Harness=runtests -Isite/cgi-bin/modules -It -e 'runtests glob q!t/*.t!'

manicheck:
	perl -MExtUtils::Manifest=manicheck -e 'manicheck()'

filecheck:
	perl -MExtUtils::Manifest=filecheck -e 'filecheck()'
