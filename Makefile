VERSION=0.23
DISTNAME=bse-$(VERSION)
DISTBUILD=$(DISTNAME)
DISTTAR=../$(DISTNAME).tar
DISTTGZ=$(DISTTAR).gz
WEBBASE=/home/tony/www/bse
PERL=$(shell perl -It -MBSE::Test -e 'print BSE::Test::test_perl()')
PERLBIN=$(shell $(PERL) -MConfig -e 'print $Config{installbin}')

BSEMODULES=site/cgi-bin/modules/BSE/Modules.pm

NOOP=echo Nothing

HTMLDEPS=$(shell $(PERL) -lane 'print $$F[0] if $$F[0] =~ /\.(pm|pl|pod)$$/' MANIFEST)

MODULES=$(shell grep cgi-bin/.*\.pm MANIFEST | sed -e '/^\#/d' -e 's/[ \t].*//' -e '/^site\/cgi-bin\/modules\/BSE\/\(Modules\|Version\)\.pm/d' )
VERSIONDEPS=$(shell $(PERL) site/util/bse_versiondeps.pl MANIFEST)

POD2TEXT=$(PERLBIN)/pod2text
POD2HTML=$(PERLBIN)/pod2html

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
	git tag -m "$(VERSION) release" r$(VERSION)

# make sure everything is committed
cleantree:
	if grep -q 'perl.*-d:ptkdb' site/cgi-bin/*.pl site/cgi-bin/admin/*.pl ; \
	  then echo '***' The debugger is still enabled ; \
	  exit 1; \
	fi
	test -z "`git status -s`" || ( echo "Uncommitted files in the tree"; exit 1 )

archive: $(DISTTGZ)

$(DISTTGZ): distdir
	if [ -e $(DISTTGZ) ] ; \
	  then echo $(DISTTGZ) already exists ; \
	       exit 1 ; \
	fi
	tar cf $(DISTTAR) $(DISTBUILD)
	-$(PERL) -MExtUtils::Command -e rm_rf $(DISTBUILD)
	gzip $(DISTTAR)

#	tar czf $(DISTFILE) -C .. bse --exclude '*~' --exclude '*,v' --exclude 'pod2html-*cache'

# recent ExtUtils::Manifest don't copy the executable bit, fix that here

distdir: docs dbinfo version
	-$(PERL) -MExtUtils::Command -e rm_rf $(DISTBUILD)
	$(PERL) -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	$(PERL) site/util/make_versions.pl $(DISTBUILD)/$(BSEMODULES)
	mkdir $(DISTBUILD)/site/htdocs/shop
	find $(DISTBUILD) -type f | xargs chmod u+w
	for i in `cat MANIFEST` ; do if [ -x $$i ] ; then chmod a+x $(DISTBUILD)/$$i ; fi ; done

clean:
	$(NOOP)

docs: INSTALL.txt INSTALL.html otherdocs

INSTALL.txt: INSTALL.pod
	$(POD2TEXT) <INSTALL.pod >INSTALL.txt

INSTALL.html: INSTALL.pod
	$(POD2HTML) --infile=INSTALL.pod --outfile=INSTALL.html
	-rm pod2html-dircache pod2html-itemcache pod2htmd.tmp pod2htmi.tmp

otherdocs:
	cd site/docs ; make all PERL=$(PERL)

dbinfo: site/util/mysql.str

site/util/mysql.str: schema/bse.sql schema/mysql_build.pl
	$(PERL) schema/mysql_build.pl >site/util/mysql.str

version: site/cgi-bin/modules/BSE/Version.pm

site/cgi-bin/modules/BSE/Version.pm: $(VERSIONDEPS)
	$(PERL) site/util/bse_mkgitversion.pl $(VERSION) site/cgi-bin/modules/BSE/Version.pm

modversion: $(BSEMODULES)

$(BSEMODULES): $(MODULES) site/util/make_versions.pl
	$(PERL) site/util/make_versions.pl $(BSEMODULES)

# this is very rough
testinst: distdir
	$(PERL) localinst.perl $(DISTBUILD)
	$(PERL) -MExtUtils::Command -e rm_rf $(DISTBUILD)
	cd `$(PERL) -lne 'do { print $$1; exit; } if /^base_dir\s*=\s*(.*)/' test.cfg`/util ; $(PERL) loaddata.pl ../data/db

testup: checkver distdir
	$(PERL) localinst.perl $(DISTBUILD) leavedb
	$(PERL) -MExtUtils::Command -e rm_rf $(DISTBUILD)
	cd `$(PERL) -lne 'do { print $$1; exit; } if /^base_dir\s*=\s*(.*)/' test.cfg`/util ; $(PERL) upgrade_mysql.pl -b ; $(PERL) loaddata.pl ../data/db

checkver:
	if [ -d .git ] ; then perl site/util/check_versions.pl ; fi

TEST_FILES=t/*.t t/*/*.t
TEST_VERBOSE=0

test: testup
	$(PERL) '-MTest::Harness=runtests,$$verbose' -Isite/cgi-bin/modules -It -e '$$verbose=$(TEST_VERBOSE); runtests @ARGV' $(TEST_FILES)

regen_known_errors:
	$(PERL) t/t98podcheck.t -r

manicheck:
	$(PERL) -MExtUtils::Manifest=manicheck -e 'manicheck()'

filecheck:
	$(PERL) -MExtUtils::Manifest=filecheck -e 'filecheck()'

manifest:
	$(PERL) -MExtUtils::Manifest=mkmanifest -e mkmanifest

htmldocs: $(HTMLDEPS)
	if [ -z "$(HTMLDOCDIR)" ] ; then \
	  echo Supply HTMLDOCDIR ; exit 1 ; \
	fi
	[ -d "$(HTMLDOCDIR)" ] || mkdir -p "$(HTMLDOCDIR)"
	$(PERL) makehtmldocs.pl "$(HTMLDOCDIR)" 
