use utf8;
package Koha::Schema::Result::EmbeddingProvider;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::EmbeddingProvider

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<embedding_providers>

=cut

__PACKAGE__->table("embedding_providers");

=head1 ACCESSORS

=head2 embedding_provider_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 url

  data_type: 'varchar'
  is_nullable: 0
  size: 500

=head2 model

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 api_key

  data_type: 'text'
  is_nullable: 1

=head2 auth_type

  data_type: 'enum'
  default_value: 'none'
  extra: {list => ["none","bearer"]}
  is_nullable: 0

=head2 request_body_template

  data_type: 'text'
  is_nullable: 0

=head2 response_key

  data_type: 'varchar'
  default_value: 'data.0.embedding'
  is_nullable: 0
  size: 255

=head2 dimensions

  data_type: 'integer'
  default_value: 768
  is_nullable: 0

=head2 status

  data_type: 'enum'
  default_value: 'inactive'
  extra: {list => ["active","inactive"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "embedding_provider_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "url",
  { data_type => "varchar", is_nullable => 0, size => 500 },
  "model",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "api_key",
  { data_type => "text", is_nullable => 1 },
  "auth_type",
  {
    data_type     => "enum",
    default_value => "none",
    extra         => { list => [ "none", "bearer" ] },
    is_nullable   => 0,
  },
  "request_body_template",
  { data_type => "text", is_nullable => 0 },
  "response_key",
  {
    data_type     => "varchar",
    default_value => "data.0.embedding",
    is_nullable   => 0,
    size          => 255,
  },
  "dimensions",
  { data_type => "integer", default_value => 768, is_nullable => 0 },
  "status",
  {
    data_type     => "enum",
    default_value => "inactive",
    extra         => { list => [ "active", "inactive" ] },
    is_nullable   => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</embedding_provider_id>

=back

=cut

__PACKAGE__->set_primary_key("embedding_provider_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint( "name", ["name"] );

# Created by DBIx::Class::Schema::Loader v0.07051
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:placeholder

1;
