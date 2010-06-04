package Ormlette;
# ABSTRACT: Light and fluffy object persistence

use strict;
use warnings;

our $VERSION = 0.001000;

use Carp 'croak';

sub init {
  my ($class, $dbh, %params) = @_;

  croak 'First param to Ormlette->init must be a connected database handle'
    unless $dbh->isa('DBI::db');

  my $debug = 1 if $params{debug};
  my $namespace = $params{namespace} || caller;

  my $tbl_names = _scan_tables($dbh, $namespace, %params);

  my $self = bless {
    dbh         => $dbh,
    debug       => $debug,
    namespace   => $namespace,
    readonly    => $params{readonly} ? 1 : 0,
    tbl_names   => $tbl_names,
  }, $class;

  $self->_build_root_pkg;
  $self->_build_table_pkg($_) for keys %$tbl_names;

  return $self;
}

sub dbh { $_[0]->{dbh} }

sub _scan_tables {
  my ($dbh, $namespace, %params) = @_;

  my @tables = $dbh->tables(undef, undef, undef, 'TABLE');
  if (my $quote_char = $dbh->get_info(29)) {
    for (@tables) {
      s/$quote_char$//;
      s/^.*$quote_char//;
    }
  }

  if ($params{tables}) {
    my %include = map { $_ => 1 } @{$params{tables}};
    @tables = grep { $include{$_} } @tables;
  }

  my %tbl_names;
  for (@tables) {
    my @words = split '_', lc $_;
    $tbl_names{$_} = $namespace . '::' . (join '', map { ucfirst } @words);
  }

  return \%tbl_names;
}

sub _scan_fields {
  my ($self, $tbl_name) = @_;

  my $sth = $self->dbh->prepare("SELECT * FROM $tbl_name LIMIT 0");
  $sth->execute;
  return $sth->{NAME};
}

# Code generation methods below

sub _build_root_pkg {
  my $self = shift;
  my $pkg_name = $self->{namespace};

  my $pkg_src = $self->_pkg_core($pkg_name);
  $pkg_src .= $self->_root_methods;

  $self->_compile_pkg($pkg_src) unless $pkg_name->can('_ormlette_init');
  $pkg_name->_ormlette_init_root($self);
}

sub _build_table_pkg {
  my ($self, $tbl_name) = @_;
  my $pkg_name = $self->{tbl_names}{$tbl_name};

  my $field_list = $self->_scan_fields($tbl_name);

  my $pkg_src = $self->_pkg_core($pkg_name);
  $pkg_src .= $self->_table_methods($tbl_name, $field_list);

  $self->_compile_pkg($pkg_src) unless $pkg_name->can('_ormlette_init');
  $pkg_name->_ormlette_init_table($self, $tbl_name);
}

sub _compile_pkg {
  my ($self, $pkg_src) = @_;
  local $@;
  print STDERR $pkg_src if $self->{debug};
  eval $pkg_src;
  die $@ if $@;
}

sub _pkg_core {
  my ($self, $pkg_name) = @_;

  return <<"END_CODE";
package $pkg_name;

use strict;
use warnings;

my \$_ormlette_dbh;

sub dbh { \$_ormlette_dbh }

sub _ormlette_init {
  my (\$class, \$ormlette) = \@_;
  \$_ormlette_dbh = \$ormlette->dbh;
}

END_CODE
}

sub _root_methods {
  my $self = shift;

  return <<"END_CODE";
sub _ormlette_init_root {
  my (\$class, \$ormlette) = \@_;
  \$class->_ormlette_init(\$ormlette);
}

END_CODE
}

sub _table_methods {
  my ($self, $tbl_name, $field_list) = @_;
  my $pkg_name = $self->{tbl_names}{$tbl_name};

  my $select_fields = join ', ', @$field_list;
  my $field_vars = '$' . join ', $', @$field_list;
  my $inflate_fields; $inflate_fields .= "$_ => \$$_, " for @$field_list;

  my $code = <<"END_CODE";
sub table { '$tbl_name' }

sub _ormlette_init_table {
  my (\$class, \$ormlette, \$table_name) = \@_;
  \$class->_ormlette_init(\$ormlette);
}

sub select {
  my \$class = shift;

  my \$sql = 'SELECT $select_fields FROM $tbl_name';
  \$sql .= ' ' . shift if \@_;
  my \$sth = \$class->dbh->prepare_cached(\$sql);
  \$sth->execute(\@_);

  my \@results;
  while (my \$obj = \$class->_ormlette_load_from_sth(\$sth)) {
    push \@results, \$obj;
  }

  return \\\@results;
}

sub _ormlette_load_from_sth {
  my (\$class, \$sth) = \@_;

  \$sth->bind_columns(\\(my ($field_vars)));
  return unless \$sth->fetch;

  return bless { $inflate_fields }, \$class;
}

END_CODE

  my @key = $self->dbh->primary_key(undef, undef, $tbl_name);
  if (@key) {
    my $key_criteria = join ' AND ', map { "$_ = ?" } @key;

    $code .= <<"END_CODE";
sub load {
  my \$class = shift;

  my \$sql = 'SELECT $select_fields FROM $tbl_name WHERE $key_criteria';
  my \$sth = \$class->dbh->prepare_cached(\$sql);
  \$sth->execute(\@_);

  my \$obj = \$class->_ormlette_load_from_sth(\$sth);
  \$sth->finish;

  return \$obj;
}
END_CODE
  }

  $code .= $self->_table_mutators($tbl_name, $field_list)
    unless $self->{readonly};

  return $code;
}

sub _table_mutators {
  my ($self, $tbl_name, $field_list) = @_;
  my $pkg_name = $self->{tbl_names}{$tbl_name};

  my $insert_fields = join ', ', @$field_list;
  my $insert_params = join ', ', ('?') x @$field_list;
  my $insert_values = join ', ', map { "\$self->{$_}" } @$field_list;
  my $handle_autoincrement = '';

  my @key = $self->dbh->primary_key(undef, undef, $tbl_name);
  if (@key == 1) {
    my $key_field = $key[0];
    $handle_autoincrement = qq(
\$self->{$key_field} =
  \$self->dbh->last_insert_id(undef, undef, qw( $tbl_name $key_field ))
    unless defined \$self->{$key_field};);
  }

  my $code = <<"END_CODE";

sub _ormlette_new {
  my \$class = shift;
  bless { \@_ }, \$class;
}

sub insert {
  my \$self = shift;

  my \$sql =
    'INSERT INTO $tbl_name ( $insert_fields ) VALUES ( $insert_params )';
  my \$sth = \$self->dbh->prepare_cached(\$sql);
  \$sth->execute($insert_values);
  $handle_autoincrement;
  return \$self;
}
END_CODE

  if (@key) {
    my $key_criteria = join ' AND ', map { "$_ = ?" } @key;
    my $key_values = join ', ', map { "\$self->{$_}" } @key;
    my $update_fields = join ', ', map { "$_ = ?" } @$field_list;

    $code .= <<"END_CODE";
sub update {
  my \$self = shift;

  my \$sql = 'UPDATE $tbl_name SET $update_fields WHERE $key_criteria';
  my \$sth = \$self->dbh->prepare_cached(\$sql);
  \$sth->execute($insert_values, $key_values);

  return \$self;
}
END_CODE
  }

  unless ($pkg_name->can('new')) {
    $code .= '
sub new { my $class = shift; $class->_ormlette_new(@_); }
';
  }

  return $code;
}

1;

__END__

=head1 SYNOPSIS

Write me!

=head1 Ormlette Core Methods

=method init ($dbh, %params)

Attaches Ormlette methods to classes corresponding to tables in the database
connected to $dbh.  Recognized parameters:

=head2 debug

The C<debug> option will cause additional debugging information to be printed
to STDERR as Ormlette does its initialization.

=head2 namespace

By default, Ormlette will use the name of the package which calls C<init> as
the base namespace for its generated code.  If you want the code to be placed
into a different namespace, use the C<namespace> parameter to override this
default.

=head2 readonly

If C<readonly> is set to a true value, no data-altering methods will be
generated and generated accessors will be read-only.

=head2 tables

If you only require Ormlette code to be generated for some of the tables in
your database, providing a reference to a list of table names in the C<tables>
parameter will cause all other tables to be ignored.

=method dbh

Returns the internal database handle used for database interaction.  Can be
called on the core Ormlette object, the root namespace of its generated code,
or any of the persistent classes generated in that namespace.

=head1 Root Namespace Methods

=method dbh

Returns the database handle attached by Ormlette to the root namespace.  If
multiple Ormlette objects have been instantiated with the same C<namespace>,
this will return the handle corresponding to the most-recently constructed
Ormlette.

=head1 Table Class Methods

=method dbh

Returns the database handle used by Ormlette operations on this class.

=method insert

Inserts the object into the database as a new record.  This method will fail if
the record cannot be inserted.  If the table uses an autoincrement/serial
primary key and no value for that key is set in the object, the object will be
updated with the id assigned by the database.

This method will not be generated if C<readonly> is set.

=method new

Basic constructor which accepts a hash of values and blesses them into the
class.  If a ->new method has already been defined, it will not be replaced.
If you wish to retain the default constructor functionality within your
custom ->new method, you can call $class->_ormlette_new to do so.

This method will not be generated if C<readonly> is set.

=method load(1, 2, 3)

Retrieves a single object from the database based on its primary key value(s).
If the table has a multi-field primary key, the values must be listed in the
same order as the fields in the primary key declaration.  Returns undef if no
matching record exists.

This method will only be generated for tables which have a primary key.

=method select
=method select('WHERE id = 42');
=method select('WHERE id > ? ORDER BY name LIMIT 5', 3);

Returns a reference to an array containing all objects matching the query
specified in the parameters, in the order returned by that query.  If no
parameters are provided, returns objects for all records in the database's
natural sort order.

As this method simply appends its parameters to "SELECT (fields) FROM (table)",
arbitrarily-complex queries can be built up in the parameters, including joins
and subqueries.

=method table

Returns the table name in which Ormlette stores this class's data.

=method update

Updates the object's existing database record.  This method will fail if the
object does not already exist in the database.

This method will not be generated if C<readonly> is set or for tables which
do not have a primary key.

