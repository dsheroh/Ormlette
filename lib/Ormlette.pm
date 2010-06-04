package Ormlette;
# ABSTRACT: Light and fluffy object persistence

use strict;
use warnings;

our $VERSION = 0.001000;

use Carp 'croak';

my $debug;

sub init {
  my ($class, $dbh, %params) = @_;

  croak 'First param to Ormlette->init must be a connected database handle'
    unless $dbh->isa('DBI::db');

  $debug = 1 if $params{debug};

  my $package = $params{package} || caller;

  my $tbl_names = _scan_tables($dbh, $package, %params);

  my $self = bless {
    dbh         => $dbh,
    package     => $package,
    tbl_names   => $tbl_names,
  }, $class;

  $self->_build_root_pkg;
  $self->_build_table_pkg($_) for keys %$tbl_names;

  return $self;
}

sub dbh { $_[0]->{dbh} }

sub _scan_tables {
  my ($dbh, $package, %params) = @_;

  my $tables;
  my $table_sql =
    q(SELECT tbl_name FROM sqlite_master WHERE type = 'table');
  if ($params{tables}) {
    my @tbl_list = @{$params{tables}};
    $table_sql .= ' AND name IN (' . (join ', ', ('?') x @tbl_list) . ')';
    $tables = $dbh->selectcol_arrayref($table_sql, undef, @tbl_list);
  } else {
    $tables = $dbh->selectcol_arrayref($table_sql);
  }

  my %tbl_names;
  for (@$tables) {
    my @words = split '_', lc $_;
    $tbl_names{$_} = $package . '::' . (join '', map { ucfirst } @words);
  }

  return \%tbl_names;
}

# Code generation methods below

sub _build_root_pkg {
  my $self = shift;

  my $pkg_src = $self->_pkg_core($self->{package});

  $self->_compile_pkg($pkg_src)
    unless $self->{package}->can('_ormlette_init');
  $self->_init_pkg($self->{package});
}

sub _build_table_pkg {
  my ($self, $tbl_name) = @_;

  my $pkg_src = $self->_pkg_core($self->{tbl_names}{$tbl_name});

  $self->_compile_pkg($pkg_src)
    unless $self->{tbl_names}{$tbl_name}->can('_ormlette_init');
  $self->_init_pkg($self->{tbl_names}{$tbl_name});
}

sub _compile_pkg {
  my ($self, $pkg_src) = @_;
  local $@;
  eval $pkg_src;
  die $@ if $@;
}

sub _init_pkg {
  my ($self, $pkg_name) = @_;
  $pkg_name ||= 'main';
  $pkg_name->_ormlette_init($self);
}

sub _pkg_core {
  my ($self, $pkg_name) = @_;

  my $core_src = <<"END_CODE";
package $pkg_name;

use strict;
use warnings;

my \$dbh;

sub dbh { \$dbh }

sub _ormlette_init {
  my (undef, \$egg) = \@_;
  \$dbh = \$egg->dbh;
}

END_CODE
}

1;

__END__

=head1 SYNOPSIS

Write me!

=method init ($dbh, %params)

Attaches Ormlette methods to classes corresponding to tables in the database
connected to $dbh.  Recognized parameters:

=head2 debug

The C<debug> option will cause additional debugging information to be printed
to STDERR as Ormlette does its initialization.

=head2 package

By default, Ormlette will use the name of the package which calls C<init> as
the base namespace for its generated code.  If you want the code to be placed
into a different namespace, use the C<package> parameter to override this
default.

=head2 tables

If you only require Ormlette code to be generated for some of the tables in
your database, providing a reference to a list of table names in the C<tables>
parameter will cause all other tables to be ignored.

=method dbh

Returns the internal database handle used for database interaction.  Can be
called on the core Ormlette object, the root namespace of its generated code,
or any of the persistent classes generated in that namespace.

