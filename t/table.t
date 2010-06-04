#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::Exception;

use FindBin;
use lib ("$FindBin::Bin/../lib" =~ m[^(/.*)])[0];

use DBI;
use Ormlette;

# access dbh via table class
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE dbh_test ( id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'DBHTest');
  is(DBHTest::DbhTest->dbh, $dbh, 'retrieve dbh via table class');
}

# get table names from table classes
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE first_tbl ( id integer )');
  $dbh->do('CREATE TABLE second_tbl (id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'TblName');
  is(TblName::FirstTbl->table, 'first_tbl', 'first table name ok');
  is(TblName::SecondTbl->table, 'second_tbl', 'second table name ok');
}

# default ->new returns an object and allows values to be set
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'BasicNew');
  isa_ok(BasicNew::Test->new, 'BasicNew::Test');
  my $obj = BasicNew::Test->new(foo => 1, bar => 'baz');
  is_deeply($obj, { foo => 1, bar => 'baz' }, 'params accepted by ->new');
}

# if ->new is already defined, don't replace it
{
  package NoOverride::Test;
  sub new { return bless { }, 'Original' };

  package main;
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'NoOverride');
  isa_ok(NoOverride::Test->new, 'Original');
}

