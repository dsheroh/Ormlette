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
  is($egg->dbh, $dbh, 'dbh accessible via ->dbh');
}

# identify tables and construct correct package names
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test1 ( id integer )');
  $dbh->do('CREATE TABLE TEST_taBle_2 (id integer )');
  my $egg = Ormlette->init($dbh);
  is_deeply($egg->{tbl_names}, {
    test1 => 'main::Test1', TEST_taBle_2 => 'main::TestTable2',
  }, 'found all tables and built package names');
}

# correctly identify root namespace
{
  package Root;
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  my $egg = Ormlette->init($dbh);

  package main;
  is_deeply($egg->{tbl_names}, { test => 'Root::Test' },
    'packages placed in correct namespace by default');
  is(Root->dbh, $dbh, 'default root namespace knows dbh');
  is(Root::Test->dbh, $dbh, 'default table package knows dbh');
}

# use 'namespace' param to override root namespace
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test_table ( id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'Egg');
  is_deeply($egg->{tbl_names}, {
    test_table => 'Egg::TestTable',
  }, 'override root ormlette namespace with namespace param');
}

# restrict list of packages touched using tables param
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE tbl_test ( id integer )');
  $dbh->do('CREATE TABLE ignore_me (id integer )');
  my $egg = Ormlette->init($dbh, tables => [ 'tbl_test', 'bogus' ]);
  is_deeply($egg->{tbl_names}, {
    tbl_test => 'main::TblTest',
  }, 'tables param causes non-listed tables to be ignored');

  $egg = Ormlette->init($dbh, tables => [ ]);
  is_deeply($egg->{tbl_names}, { }, 'empty tables param ignores everything');
}

