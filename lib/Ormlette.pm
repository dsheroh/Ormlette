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

  my $tbl_data = _scan_tables($dbh, $package, %params);

  return bless {
    dbh         => $dbh,
    tbl_data    => $tbl_data,
  }, $class;
}

sub _scan_tables {
  my ($dbh, $package, %params) = @_;

  my $table_sql;
  my $scan_sql =
    q(SELECT tbl_name, sql FROM sqlite_master WHERE type = 'table');
  if ($params{tables}) {
    my @tbl_list = @{$params{tables}};
    $scan_sql .= ' AND name IN (' . (join ', ', ('?') x @tbl_list) . ')';
    $table_sql = $dbh->selectall_arrayref($scan_sql, undef, @tbl_list);
  } else {
    $table_sql = $dbh->selectall_arrayref($scan_sql);
  }

  my @tables;
  for (@$table_sql) {
    my @words = split '_', lc $_->[0];
    push @tables, {
      tbl_name  => $_->[0],
      pkg_name  => $package . '::' . (join '', map { ucfirst } @words),
      sql       => $_->[1],
    };
  }

  return \@tables;
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

