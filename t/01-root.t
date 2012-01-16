#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';

use FindBin;
use lib ("$FindBin::Bin/../lib" =~ m[^(/.*)])[0];

use DBI;
use Ormlette;

# access dbh via root namespace
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '');
  my $egg = Ormlette->init($dbh, namespace => 'DBHTest');
  is(DBHTest->dbh, $dbh, 'retrieve dbh via root namespace');
}

