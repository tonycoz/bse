VERSION=0.10_01
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
	-rm -rf $(DISTBUILD)
	gzip $(DISTTAR)

#	tar czf $(DISTFILE) -C .. bse --exclude '*~' --exclude '*,v' --exclude 'pod2html-*cache'

distdir:
	-rm -rf $(DISTBUILD)
	perl -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	mkdir $(DISTBUILD)/site/htdocs/shop
	find $(DISTBUILD) -type f | xargs chmod u+w

clean:
	-rm site/htdocs/index.html
	-rm site/htdocs/shop/*.html
	-rm site/htdocs/a/*.html
	-cd site/htdocs/images ; \
	for i in *.gif ; do \
	  if [ $$i != trans_pixel.gif ] ; then \
	    rm $$i ; \
	  fi ; \
	done
	-rm site/htdocs/images/*.jpg
	-rm -rf $(DISTBUILD)

docs: INSTALL.txt INSTALL.html otherdocs

INSTALL.txt: INSTALL.pod
	pod2text <INSTALL.pod >INSTALL.txt

INSTALL.html: INSTALL.pod
	pod2html --infile=INSTALL.pod --outfile=INSTALL.html
	-rm pod2html-dircache pod2html-itemcache

otherdocs:
	cd site/docs ; make all

# this is very rough
testinst: distdir
	perl localinst.perl $(DISTBUILD)
