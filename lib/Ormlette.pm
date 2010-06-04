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
    tbl_names   => $tbl_names,
  }, $class;

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

