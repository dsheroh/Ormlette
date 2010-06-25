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

use Carp 'croak';

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

  my @accessor_fields = grep { !$pkg_name->can($_) } @$field_list;
  my $code;
  $code = $self->_add_accessors($pkg_name, @accessor_fields)
    if @accessor_fields;

  $code .= <<"END_CODE";
sub table { '$tbl_name' }

sub _ormlette_init_table {
  my (\$class, \$ormlette, \$table_name) = \@_;
  \$class->_ormlette_init(\$ormlette);
}

sub iterate {
  my \$class = shift;
  my \$callback = shift;

  my \$sql = 'SELECT $select_fields FROM $tbl_name';
  \$sql .= ' ' . shift if \@_;
  my \$sth = \$class->dbh->prepare_cached(\$sql);
  \$sth->execute(\@_);

  while (\$_ = \$class->_ormlette_load_from_sth(\$sth)) {
    \$callback->();
  }
}

sub select {
  my \$class = shift;
  my \@results;
  \$class->iterate(sub { push \@results, \$_ }, \@_);
  return \\\@results;
}

sub _ormlette_load_from_sth {
  my (\$class, \$sth) = \@_;

  \$sth->bind_columns(\\(my ($field_vars)));
  return unless \$sth->fetch;

  return bless { $inflate_fields }, \$class;
}

END_CODE

  $code .= <<"END_CODE";
sub load {
  my \$class = shift;

  croak '->load requires at least one argument' unless \@_;

  my \$sql = 'SELECT $select_fields FROM $tbl_name WHERE ';
  my \@criteria;

END_CODE

  my @key = $self->dbh->primary_key(undef, undef, $tbl_name);
  if (@key == 1) {
    my $key_criteria = $key[0] . ' = ?';

    $code .= <<"END_CODE";

  if (\@_ == 1) {
    \$sql .= '$key_criteria';
    \@criteria = \@_;
  } else {
    croak 'if not using a single-field key, ->load requires a hash of criteria'
      unless \@_ % 2 == 0;

    my \%params = \@_;
    \$sql .= join ' AND ', map { "\$_ = ?" } keys \%params;
    \@criteria = values \%params;
  }
END_CODE
  } else { # no primary key
    $code .= <<"END_CODE";
  croak 'if not using a single-field key, ->load requires a hash of criteria'
    unless \@_ % 2 == 0;

  my \%params = \@_;
  \$sql .= join ' AND ', map { "\$_ = ?" } keys \%params;
  \$sql .= ' LIMIT 1';
  \@criteria = values \%params;
END_CODE
  }

  $code .= <<"END_CODE";
  my \$sth = \$class->dbh->prepare_cached(\$sql);
  \$sth->execute(\@criteria);

  my \$obj = \$class->_ormlette_load_from_sth(\$sth);
  \$sth->finish;

  return \$obj;
}
END_CODE

  $code .= $self->_table_mutators($tbl_name, $field_list)
    unless $self->{readonly};

  return $code;
}

sub _add_accessors {
  my ($self, $pkg_name, @accessor_fields) = @_;

  my $accessor_sub;
  if ($self->{readonly}) {
    $accessor_sub = '$_[0]->{$attr}';
  } else {
    $accessor_sub = '
      $_[0]->{$attr} = $_[1] if defined $_[1];
      $_[0]->{$attr};'
  }

  my $field_list = join ' ', @accessor_fields;
  return <<"END_CODE";
{
  no strict 'refs';
  for my \$attr (qw( $field_list )) {
    *\$attr = sub {
      $accessor_sub
    };
  }
}
END_CODE
}

sub _table_mutators {
  my ($self, $tbl_name, $field_list) = @_;
  my $pkg_name = $self->{tbl_names}{$tbl_name};

  my $insert_fields = join ', ', @$field_list;
  my $insert_params = join ', ', ('?') x @$field_list;
  my $insert_values = join ', ', map { "\$self->{$_}" } @$field_list;
  my $handle_autoincrement = '';
  my $init_all_attribs = join ",\n    ",
    map { "'$_' => \$params{'$_'}" } @$field_list;

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
  my (\$class, \%params) = \@_;
  bless {
    $init_all_attribs
  }, \$class;
}

sub create {
  my \$class = shift;
  \$class->new(\@_)->insert;
}

sub insert {
  my \$self = shift;
  my \$sql =
    'INSERT INTO $tbl_name ( $insert_fields ) VALUES ( $insert_params )';
  my \$sth = \$self->dbh->prepare_cached(\$sql);
  \$sth->execute($insert_values);
  $handle_autoincrement
  \$sth->finish;
  return \$self;
}

sub truncate {
  my \$class = shift;
  croak '->truncate must be called as a class method' if ref \$class;
  my \$sql = 'DELETE FROM $tbl_name';
  my \$sth = dbh->prepare_cached(\$sql);
  \$sth->execute;
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
  \$sth->finish;

  return \$self;
}

sub delete {
  my \$self = shift;
  my \$sql = 'DELETE FROM $tbl_name';
  if (ref \$self) {
    \$sql .= ' WHERE $key_criteria';
    \@_ = ( $key_values );
  } else {
    return unless \@_;
    \$sql .= ' ' . shift;
  }
  my \$sth = \$self->dbh->prepare_cached(\$sql);
  \$sth->execute(\@_);
}
END_CODE
  } else { # no primary key
    $code .= <<"END_CODE";
sub delete {
  my \$class = shift;
  croak '->delete may not be called as an instance method for an unkeyed table'
    if ref \$class;
  return unless \@_;
  my \$sql = 'DELETE FROM $tbl_name ' . shift;
  my \$sth = \$class->dbh->prepare_cached(\$sql);
  \$sth->execute(\@_);
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

In addition to the methods listed below, accessors will be generated for each
field found in the table unless an accessor for that field already exists,
providing the convenience of not having to create all the accessors yourself
while also allowing for custom accessors to be used where needed.  Generated
accessors will be read-only if C<readonly> is set or writable using the
"$obj->attr('new value')" convention otherwise.

Note that the generated accessors are extremely simple and make no attempt at
performing any form of data validation, so you may wish to use another fine
CPAN module to generate accessors before initializing Ormlette.

=method create

Constructs an object by calling C<new>, then uses C<insert> to immediately
store it to the database.

This method will not be generated if C<readonly> is set.

=method dbh

Returns the database handle used by Ormlette operations on this class.

=method delete
=method delete('WHERE name = ?', 'John Doe')

As a class method, deletes all objects matching the criteria specified in the
parameters.  In an attempt to avoid data loss from accidentally calling
C<delete> as a class method when intending to use it as an instance method,
nothing will be done if no criteria are provided.

As an instance method, deletes the object from the database.  In this case, any
parameters will be ignored.  The in-memory object is unaffected and remains
available for further use, including re-saving it to the database.

This method will not be generated if C<readonly> is set.  The instance method
variant will only be generated for tables which have a primary key.

=method insert

Inserts the object into the database as a new record.  This method will fail if
the record cannot be inserted.  If the table uses an autoincrement/serial
primary key and no value for that key is set in the object, the in-memory
object will be updated with the id assigned by the database.

This method will not be generated if C<readonly> is set.

=method iterate(sub { print $_->id })
=method iterate(sub { print $_->name }, 'WHERE age > ?', 18)

Takes a sub reference as the first parameter and passes each object returned by
the subsequent query to the referenced sub in C<$_> for processing.  The
primary difference between this method and C<select> is that C<iterate> only
loads one record into memory at a time, while C<select> loads all records at
once, which may require unacceptable amounts of memory when dealing with larger
data sets.

=method new

Basic constructor which accepts a hash of values and blesses them into the
class.  If a ->new method has already been defined, it will not be replaced.
If you wish to retain the default constructor functionality within your
custom ->new method, you can call $class->_ormlette_new to do so.

This method will not be generated if C<readonly> is set.

=method load(1)
=method load(foo => 1, bar => 2)

Retrieves a single object from the database based on the specified criteria.

If the table has a single-field primary key, passing a single argument will
retrieve the record with that value as its primary key.

Lookups on non-key fields or multiple-field primary keys can be performed by
passing a hash of field => value pairs.  If more than one record matches the
given criteria, only one will be returned, but which one will be returned is
database-dependent and may or may not be consistent from one call to the next.

Returns undef if no matching record exists.

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

