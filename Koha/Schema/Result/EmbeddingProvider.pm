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

Primary key for the embedding_providers table

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

Admin-given label for this provider configuration

=head2 url

  data_type: 'varchar'
  is_nullable: 0
  size: 500

Full endpoint URL for the embedding API

=head2 model

  data_type: 'varchar'
  is_nullable: 0
  size: 255

Model name substituted as {{model}} in the request body template

=head2 api_key

  data_type: 'text'
  is_nullable: 1

Bearer token for authentication (empty for Ollama)

=head2 auth_type

  data_type: 'enum'
  default_value: 'none'
  extra: {list => ["none","bearer"]}
  is_nullable: 0

Whether to send an Authorization header

=head2 request_body_template

  data_type: 'text'
  is_nullable: 0

JSON body template with {{text}} and {{model}} as sentinel values

=head2 response_key

  data_type: 'varchar'
  default_value: 'data.0.embedding'
  is_nullable: 0
  size: 255

Dot-notation path to the embedding array in the response

=head2 dimensions

  data_type: 'integer'
  default_value: 768
  is_nullable: 0

Vector dimensionality

=head2 status

  data_type: 'enum'
  default_value: 'inactive'
  extra: {list => ["active","inactive"]}
  is_nullable: 0

Only one provider may be active at a time

=head2 marc_fields_config

  data_type: 'text'
  is_nullable: 1

YAML configuration of biblio/MARC fields used by text_for_biblio

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
    data_type => "enum",
    default_value => "none",
    extra => { list => ["none", "bearer"] },
    is_nullable => 0,
  },
  "request_body_template",
  { data_type => "text", is_nullable => 0 },
  "response_key",
  {
    data_type => "varchar",
    default_value => "data.0.embedding",
    is_nullable => 0,
    size => 255,
  },
  "dimensions",
  { data_type => "integer", default_value => 768, is_nullable => 0 },
  "status",
  {
    data_type => "enum",
    default_value => "inactive",
    extra => { list => ["active", "inactive"] },
    is_nullable => 0,
  },
  "marc_fields_config",
  { data_type => "text", is_nullable => 1 },
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

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2026-05-18 09:45:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:N2LA2CWGn0Gz3YMqJtzIQQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
