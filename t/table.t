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

# ->select with null criteria
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( my_int integer, my_str varchar(10) )');
  my $egg = Ormlette->init($dbh, namespace => 'SelectAll');

  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (7, 'seven')));
  is_deeply(SelectAll::Test->select, [ { my_int => 7, my_str => 'seven' } ],
    'retrieved only object in table with ->select');

  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (8, 'eight')));
  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (9, 'nine')));
  is_deeply(
    [ sort { $a->{my_int} <=> $b->{my_int} } @{SelectAll::Test->select} ],
    [ { my_int => 7, my_str => 'seven' }, 
      { my_int => 8, my_str => 'eight' }, 
      { my_int => 9, my_str => 'nine' } ],
    'retrieved all objects in table with ->select');
}

# ->select with criteria
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( my_int integer, my_str varchar(10) )');
  my $egg = Ormlette->init($dbh, namespace => 'SelectCrit');

  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (9, 'nine')));
  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (42, 'answer')));
  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (23, 'skidoo')));
  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (99, 'bottles')));

  is_deeply(SelectCrit::Test->select('WHERE my_int = 9'),
    [ { my_int => 9, my_str => 'nine' } ],
    '->select one record by hardcoded value');
  is_deeply(SelectCrit::Test->select('WHERE my_str = ?', 'answer'),
    [ { my_int => 42, my_str => 'answer' } ],
    '->select one record by placeholder');
  is_deeply(SelectCrit::Test->select('WHERE my_int > 40 ORDER BY my_int DESC'),
    [ { my_int => 99, my_str => 'bottles' },
      { my_int => 42, my_str => 'answer' } ],
    '->select and order multiple records');
  is_deeply(SelectCrit::Test->select('WHERE 0 = 1'), [ ],
    '->select returns an empty list when no records match');
}

# select returns properly-blessed objects
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( my_int integer, my_str varchar(10) )');
  my $egg = Ormlette->init($dbh, namespace => 'SelectBless');

  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (12, 'twelve')));
  isa_ok(SelectBless::Test->select->[0], 'SelectBless::Test');
}

# no mutating methods if readonly set
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  my $egg = Ormlette->init($dbh, namespace => 'ROMethods', readonly => 1);
  is(ROMethods::Test->can('new'), undef, 'no ->new with readonly');
  is(ROMethods::Test->can('_ormlette_new'), undef,
    'no ->_ormlette_new with readonly');
}

