VERSION=0.11_09
DISTNAME=bse-$(VERSION)
DISTBUILD=$(DISTNAME)
DISTTAR=../$(DISTNAME).tar
DISTTGZ=$(DISTTAR).gz

help:
	@echo make dist - build the tar.gz file
	@echo make clean - delete generated files
	@echo make distdir - build distribution directory
	@echo make docs - build documentation

# this target needs to be modified so that the output directory includes
# the release number
dist: $(DISTTGZ)

$(DISTTGZ): distdir
	if [ -e $(DISTTGZ) ] ; \
	  then echo $(DISTTGZ) already exists ; \
	       exit 1 ; \
	fi
	tar cf $(DISTTAR) $(DISTBUILD)
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	gzip $(DISTTAR)

#	tar czf $(DISTFILE) -C .. bse --exclude '*~' --exclude '*,v' --exclude 'pod2html-*cache'

distdir: docs dbinfo
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	perl -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	mkdir $(DISTBUILD)/site/htdocs/shop
	find $(DISTBUILD) -type f | xargs chmod u+w

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

# this is very rough
testinst: distdir
	perl localinst.perl $(DISTBUILD)
	perl -MExtUtils::Command -e rm_rf $(DISTBUILD)

testfiles: distdir
	perl localinst.perl $(DISTBUILD) leavedb
	perl -MExtUtils::Command -e rm_rf $(DISTBUILD)

test: testinst
	perl -MTest::Harness=runtests -It -e 'runtests glob q!t/*.t!'
