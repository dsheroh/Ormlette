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
  Ormlette->init($dbh, namespace => 'DBHTest');
  is(DBHTest::DbhTest->dbh, $dbh, 'retrieve dbh via table class');
}

# get table names from table classes
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE first_tbl ( id integer )');
  $dbh->do('CREATE TABLE second_tbl (id integer )');
  Ormlette->init($dbh, namespace => 'TblName');
  is(TblName::FirstTbl->table, 'first_tbl', 'first table name ok');
  is(TblName::SecondTbl->table, 'second_tbl', 'second table name ok');
}

# default ->new returns an object and allows values to be set
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  Ormlette->init($dbh, namespace => 'BasicNew');
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
  Ormlette->init($dbh, namespace => 'NoOverride');
  isa_ok(NoOverride::Test->new, 'Original');
}

# ->select with null criteria
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( my_int integer, my_str varchar(10) )');
  Ormlette->init($dbh, namespace => 'SelectAll');

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
  Ormlette->init($dbh, namespace => 'SelectCrit');

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
  Ormlette->init($dbh, namespace => 'SelectBless');

  $dbh->do(q(INSERT INTO test (my_int, my_str) VALUES (12, 'twelve')));
  isa_ok(SelectBless::Test->select->[0], 'SelectBless::Test');
}

# no mutating methods if readonly set
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer )');
  Ormlette->init($dbh, namespace => 'ROMethods', readonly => 1);
  is(ROMethods::Test->can('new'), undef, 'no ->new with readonly');
  is(ROMethods::Test->can('_ormlette_new'), undef,
    'no ->_ormlette_new with readonly');
}

# create ->load method iff table has a primary key
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE keyed ( id integer primary key )');
  $dbh->do('CREATE TABLE no_key ( id integer )');
  Ormlette->init($dbh, namespace => 'KeyCheck');
  is(ref KeyCheck::Keyed->can('load'), 'CODE',
    'create ->load if primary key is present');
  is(KeyCheck::NoKey->can('load'), undef, 'no ->load without primary key');
}

# retrieve records with ->load
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE keyed ( id integer primary key, my_txt char(10) )');
  $dbh->do('CREATE TABLE multi_key
    ( id1 integer, id2 integer, non_key text, PRIMARY KEY (id1, id2) )');
  Ormlette->init($dbh, namespace => 'KeyLoad');

  $dbh->do(q(INSERT INTO keyed (id, my_txt) VALUES ( 18, 'eighteen' )));
  $dbh->do(q(INSERT INTO keyed (id, my_txt) VALUES ( 19, 'nineteen' )));
  $dbh->do(q(INSERT INTO multi_key (id1, id2, non_key) VALUES ( 1, 2, 'tre')));
  $dbh->do(q(INSERT INTO multi_key (id1, id2, non_key) VALUES ( 4, 5, 'six')));

  my $obj = KeyLoad::Keyed->load(18);
  isa_ok($obj, 'KeyLoad::Keyed');
  is_deeply($obj, { id => 18, my_txt => 'eighteen' },
    '->load with single-field key');
  is(KeyLoad::Keyed->load(4), undef,
    '->load with single-field key returns nothing on missing key');

  undef $obj;
  $obj = KeyLoad::MultiKey->load(4, 5);
  isa_ok($obj, 'KeyLoad::MultiKey');
  is_deeply($obj, { id1 => 4, id2 => 5, non_key => 'six' },
    '->load with multi-field key');
  is(KeyLoad::MultiKey->load(2, 'tre'), undef,
    '->load with multi-field key returns nothing on missing key');
}

# add records with ->insert
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE no_key ( id integer, my_txt char(10) )');
  $dbh->do('CREATE TABLE keyed ( id integer primary key, my_txt char(10) )');
  Ormlette->init($dbh, namespace => 'Insert');

  isa_ok(Insert::NoKey->new(id => 1, my_txt => 'foo')->insert, 'Insert::NoKey');
  isa_ok(Insert::Keyed->new(id => 2, my_txt => 'bar')->insert, 'Insert::Keyed');

  is_deeply(Insert::NoKey->new(id => 3, my_txt => 'baz')->insert,
    { id => 3, my_txt => 'baz' }, 'correct return from keyless ->insert');
  is_deeply(Insert::Keyed->new(id => 4, my_txt => 'wibble')->insert,
    { id => 4, my_txt => 'wibble' }, 'correct return from keyed ->insert');
  is_deeply(Insert::Keyed->new(my_txt => 'xyzzy')->insert,
    { id => 5, my_txt => 'xyzzy' }, 'correct return from autokeyed ->insert');

  is_deeply(Insert::NoKey->select('WHERE id = 3'),
    [ { id => 3, my_txt => 'baz' } ], '->select inserted keyless record');
  is_deeply(Insert::Keyed->load(5),
    { id => 5, my_txt => 'xyzzy' }, '->load inserted autokey record');
}

# ->update records in keyed table
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE keyed ( id integer primary key, my_txt char(10) )');
  Ormlette->init($dbh, namespace => 'Update');

  my $obj = Update::Keyed->new(id => 42, my_txt => 'fourty-two')->insert;
  $obj->{my_txt} = 'twoscore and two';
  is($obj->update, $obj, 'correct return value from ->update');

  my $reload = Update::Keyed->load(42);
  is_deeply($reload, $obj, 'updated original object retrieved');

  $reload->{my_txt} = 'The Ultimate Answer';
  $reload->update;
  undef $obj;
  $obj= Update::Keyed->load(42);
  is_deeply($obj, $reload, 'update of loaded object reloaded');
}

# construct and save with ->create
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  $dbh->do('CREATE TABLE test ( id integer primary key, my_txt char(10) )');
  Ormlette->init($dbh, namespace => 'Create');

  isa_ok(Create::Test->create(my_txt => 'created'), 'Create::Test');
  is_deeply(Create::Test->load(1), { id => 1, my_txt => 'created' },
    'reload object built with ->create');
}

