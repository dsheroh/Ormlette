#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::Exception;

use FindBin;
use lib ("$FindBin::Bin/../lib" =~ m[^(/.*)])[0];

use DBI;
use Ormlette;

# die on attempt to init with invalid dbh
{
  dies_ok { Ormlette->init } 'init dies with no params';
  dies_ok { Ormlette->init(42) } 'init dies with invalid dbh param';
}

# initialize from connected dbh
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  my $egg = Ormlette->init($dbh);
  isa_ok($egg, 'Ormlette');
  is($egg->{dbh}, $dbh, 'dbh stored in ormlette');
}

# identify tables and construct correct package names
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do(my $sql1 = 'CREATE TABLE test1 ( id integer )');
  $dbh->do(my $sql2 = 'CREATE TABLE TEST_taBle_2 (id integer )');
  my $egg = Ormlette->init($dbh);
  is_deeply($egg->{tbl_data}, [
    { tbl_name => 'test1', pkg_name => 'main::Test1', sql => $sql1 },
    { tbl_name => 'TEST_taBle_2', pkg_name => 'main::TestTable2', sql => $sql2 },
  ], 'found all tables and built package names');
}

# use 'package' param to override root egg namespace
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do(my $sql = 'CREATE TABLE test_table ( id integer )');
  my $egg = Ormlette->init($dbh, package => 'Egg');
  is_deeply($egg->{tbl_data}, [
    { tbl_name => 'test_table', pkg_name => 'Egg::TestTable', sql => $sql },
  ], 'override root ormlette namespace with package param');
}

# restrict list of packages touched using tables param
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do(my $sql1 = 'CREATE TABLE tbl_test ( id integer )');
  $dbh->do(my $sql2 = 'CREATE TABLE ignore_me (id integer )');
  my $egg = Ormlette->init($dbh, tables => [ 'tbl_test', 'bogus' ]);
  is_deeply($egg->{tbl_data}, [
    { tbl_name => 'tbl_test', pkg_name => 'main::TblTest', sql => $sql1 },
  ], 'tables param causes non-listed tables to be ignored');
}

