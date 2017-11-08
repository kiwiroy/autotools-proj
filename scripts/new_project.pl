#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Cwd qw(abs_path cwd);

{
    my $subdirs = [];
    my $project = undef;
    my $version = 0.01;

    my $makefile_name  = 'Makefile.am';
    my $configure_name = 'configure.ac';
    my @automake_files = qw(AUTHORS ChangeLog INSTALL NEWS README);

    
    my $usage = sub { exec('perldoc', $0); };
    my $add_subdirs = sub { push(@$subdirs, split(/,/, $_[1])); };
    
    GetOptions('help'      => $usage,
	       'subdirs=s' => $add_subdirs,
	       'name=s'    => \$project,
	       'version=i' => \$version,
	       ) or $usage->();
    
    
    if($project) {
	my $object = main->new(name         => $project,
			       configure_ac => $configure_name,
			       makefile_am  => $makefile_name,
			       automake     => \@automake_files,
			       version      => $version);

	$object->create();

	$object->create_subdirs($subdirs);
	
	$object->write_makefile_am();

	$object->write_configure_ac();
	
	$object->write_bootstrap_script();

	$object->success_message();
    } else {
	$usage->();
    }

}

sub new {
    my ($class) = shift;

    my $self = bless({ 
	name         => 'project-name',
	configure_ac => 'configure.ac',
	makefile_am  => 'Makefile.am',
	automake     => [],
	@_, 
	error        => undef,
    }, $class);

    return $self;
}

sub create {
    my ($self) = @_;

    $self->{'abs_path'} = abs_path(cwd());

    eval {
	my $path = $self->{'abs_path'} . "/" . $self->{'name'};
	mkdir $path, 0755 or
	    die "Failed to create '$path': $!";
    };
    if($@) {
	$self->{'error'} = $@;
    } else {
	eval {
	    my $path = $self->{'abs_path'} . "/" . $self->{'name'};
	    chdir $path or die "Failed to cd to '$path': $!";
	};
	if($@) {
	    $self->{'error'} = $@;
	} else {
	    foreach my $automake_req(@{$self->{'automake'}}) {
		open (my $fh, ">$automake_req");
		close ($fh);
	    }
	}
    }

    return 0;
}

sub create_subdirs {
    my $self = shift;
    my $subdirs = shift;

    return 1 if ($self->{'error'});

    $self->{'subdirs'} = $subdirs;

    foreach my $dir(@$subdirs) {
	last if($self->{'error'});
	eval {
	    mkdir $dir, 0755 or die "Failed to create '$dir': $!";
	};
	if($@) {
	    $self->{'error'} = $@;
	}
    }

    return 0;
}

sub write_configure_ac {
    my ($self) = shift;

    return 1 if ($self->{'error'});
    
    my $configure = $self->{'configure_ac'};
    open (my $fh, ">$configure") or $self->{'error'} = $!;

    unless($self->{'error'}) {

	my $name    = $self->{'name'};
	my $version = $self->{'version'};
	my $email   = 'support@domain.com';
	my $source_file  = 'check_i_exist.c';
	my $config_files = join(' ', ('Makefile', map { "$_/Makefile" } @{$self->{'subdirs'}}) );


	# The code to generate the configure.ac

	print $fh <<EOF;
# auto-generated configure.ac, please edit to do what you need it to do

AC_REVISION([\$Revision:\$])
AC_INIT([$name],[$version],[$email])

dnl check we can find the source
AC_CONFIG_SRCDIR([$source_file])
AC_CONFIG_HEADER(config.h)


echo "************************************************************"
echo "* Welcome to ./configure for \$PACKAGE_STRING"
echo "************************************************************"

AC_CANONICAL_BUILD

AC_PROG_CC

AC_HEADER_STDC
AC_CHECK_HEADERS([assert.h ctype.h float.h limits.h math.h stdarg.h stdio.h])
AC_CHECK_HEADERS([sys/wait.h time.h unistd.h])

AC_C_CONST
AC_TYPE_SIZE_T

AC_CHECK_LIB([m], [round], [], [])

AM_INIT_AUTOMAKE

dnl add more macros and tests here...



dnl and now to the output	
AC_CONFIG_FILES([$config_files])
AC_OUTPUT

EOF
    
	close($fh);
    }

    return 0;
}

sub write_makefile_am {
    my $self = shift;

    return 1 if ($self->{'error'});

    my $root_makefile = <<EOF;
SUBDIRS=@{$self->{'subdirs'}}
EOF
    
    my $sub_makefile = <<EOF;
bin_PROGRAMS=test
test_SOURCES=start.c end.c
test_CFLAGS=-Wall
EOF

# block only to get tabbing working.
{
    my $makefile = $self->{'makefile_am'};
    open (my $fh, ">$makefile") or $self->{'error'} = $!;

    unless($self->{'error'}) {
	print $fh $root_makefile;
	
	close($fh);
    }

    foreach my $dir(@{$self->{'subdirs'}}) {
	last if $self->{'error'};

	open (my $fh, ">$dir/$makefile") or $self->{'error'} = $!;

	unless($self->{'error'}) {
	    print $fh $sub_makefile;

	    close ($fh);
	}
    }
}


    return 0;
}


sub write_bootstrap_script {
    my $self = shift;

    return 1 if ($self->{'error'});

    open(my $fh, '>bootstrap.sh') or die 'Failed to create bootstrap.sh';

    # A bootstrap script to help 'commit' changes when editing autotools files.
    
    print $fh <<'EOF';
#!/bin/bash

# auto-generated bootstrap script, free to edit though

# change to yes to run libtoolize as well
NEED_LIBTOOLIZE=no

# Setup
[ "x$LIBTOOLIZE" != "x" ]  || LIBTOOLIZE=libtoolize
[ "x$AUTOHEADER" != "x" ]  || AUTOHEADER=autoheader
[ "x$ACLOCAL" != "x" ]     || ACLOCAL=aclocal
[ "x$AUTOMAKE" != "x" ]    || AUTOMAKE=automake
[ "x$AUTOCONF" != "x" ]    || AUTOCONF=autoconf
[ "x$AUTOUPDATE" != "x" ]  || AUTOUPDATE=autoupdate

# default to include current directory as we use ac_path_lib.m4
# I did fix it up to work with current autoconf and stop it
# complaining about deprecated macros
DEFAULT_INC="-I . $ACLOCAL_FLAGS"

function message_out
{
    echo "$@";
}

function message_exit
{
    echo "$@" >&2 ;
    exit 1 ;
}

message_out "Running $(which $AUTOUPDATE)"
$AUTOUPDATE                  || message_exit "Failed running $AUTOUPDATE"
message_out "Running $(which $ACLOCAL)"
$ACLOCAL $DEFAULT_INC        || message_exit "Failed running $ACLOCAL (first time) try export ACLOCAL_FLAGS='-I <m4_includes_dir>'"
message_out "Running $(which $AUTOHEADER)"
$AUTOHEADER --warnings=all   || message_exit "Failed running $AUTOHEADER"

if [ "x$NEED_LIBTOOLIZE" == "xyes" ]; then 
  message_out "Running $(which $LIBTOOLIZE)"
  $LIBTOOLIZE --force --copy || message_exit "Failed running $LIBTOOLIZE"
  message_out "Running $(which $ACLOCAL) (again)"
  $ACLOCAL $DEFAULT_INC      || message_exit "Failed running $ACLOCAL (second time) try export ACLOCAL_FLAGS='-I <m4_includes_dir>'"
fi

message_out "Running $(which $AUTOMAKE)"
$AUTOMAKE --gnu     \
    --add-missing   \
    --copy                   || message_exit "Failed running $AUTOMAKE"
message_out "Running $(which $AUTOCONF)"
$AUTOCONF --warnings=all     || message_exit "Failed running $AUTOCONF"

message_out "End of script."
EOF

    close($fh);

    chmod 0755, 'bootstrap.sh';
}


sub success_message {
    my $self = shift;

    my $name    = $self->{'name'};
    my $version = $self->{'version'};

    if($self->{'error'}) {
	print "I failed to complete my task creating project $name-$version\n";
	print "I encountered the following error:\n";
	print $self->{'error'};
	print "\n";
    } else {
	my $path = $self->{'abs_path'} . "/" . $name;
	print "I've finished creating the project $name-$version\n";
	print "The project should now be in $path\n";
    }

}


=pod

=head1 NAME

new_project.pl - create a new project

=head1 USAGE

 ./new_project.pl [options] -name <project-name>

where available options are:

 -subdirs   create a sub dir. Either specify multiple times or comman separated.
 -version   the version. defaults to 0.01

 -name      The name of the project. COMPULSORY


=head1 EXTENDED USAGE

After running the script successfully there will be a new project
directory with all the basic files in.  It's possible to just run
with this basic setup, but it's more likely you'll need to edit 
some of the files produced by this script.

PROJECT/

 bootstrap.sh 

  - should only need editing on addition of AC_LIBTOOL to configure.ac

 configure.ac 
  - add more tests to the file. Also edit the arguments to AC_INIT
    AC_CONFIG_SRCDIR

 Makefile.am
  - edit these files to include the names of the programs and source
    files as per the automake documentation.

 AUTHORS   - add relevant details here
 ChangeLog - will grow as you project does...
 NEWS      - text in here can be interesting for users to read
 INSTALL   - text in here can help users install the project
 README    - text in here usually gets read by users.

=head1 DEVELOPING

When adding files to the project various arguments/variables need to
be kept in step. These include the tests required in configure.ac, the
prgram_name_SOURCES variable, AC_CONFIG_FILES([]) argument, including 
various AC_DEFINE([SPECIAL_FEATURE], 1, [Set to enable special feature])
and other autoconf/automake magic.  See the respective documentation.

=head1 AUTHOR

Roy Storey

=cut



