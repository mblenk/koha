use utf8;
package Koha::Schema::Result::LlmProvider;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::LlmProvider

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<llm_providers>

=cut

__PACKAGE__->table("llm_providers");

=head1 ACCESSORS

=head2 llm_provider_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

Primary key for the llm_providers table

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

Admin-given label for this provider configuration

=head2 url

  data_type: 'varchar'
  is_nullable: 0
  size: 500

Full endpoint URL for the chat completions API

=head2 model

  data_type: 'varchar'
  is_nullable: 0
  size: 255

Model name substituted as {{model}} in the request body template

=head2 api_key

  data_type: 'text'
  is_nullable: 1

Bearer token for authentication

=head2 auth_type

  data_type: 'enum'
  default_value: 'none'
  extra: {list => ["none","bearer"]}
  is_nullable: 0

Whether to send an Authorization header

=head2 request_body_template

  data_type: 'text'
  is_nullable: 0

JSON body template with {{model}}, {{messages}}, {{system_prompt}}, and {{tool_definitions}} as sentinel values

=head2 response_key

  data_type: 'varchar'
  default_value: 'choices.0.message.content'
  is_nullable: 0
  size: 255

Dot-notation path to the reply text in the response

=head2 tool_definitions

  data_type: 'text'
  is_nullable: 1

JSON array of tool definitions in provider-specific format; substituted via {{tool_definitions}} sentinel in the request body template

=head2 system_prompt

  data_type: 'text'
  is_nullable: 1

System prompt injected at the start of every conversation

=head2 status

  data_type: 'enum'
  default_value: 'inactive'
  extra: {list => ["active","inactive"]}
  is_nullable: 0

Only one provider may be active at a time

=cut

__PACKAGE__->add_columns(
  "llm_provider_id",
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
    default_value => "choices.0.message.content",
    is_nullable => 0,
    size => 255,
  },
  "tool_definitions",
  { data_type => "text", is_nullable => 1 },
  "system_prompt",
  { data_type => "text", is_nullable => 1 },
  "status",
  {
    data_type => "enum",
    default_value => "inactive",
    extra => { list => ["active", "inactive"] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</llm_provider_id>

=back

=cut

__PACKAGE__->set_primary_key("llm_provider_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2026-06-02 10:35:51
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:adiGSu6/n16elJJHrD/90Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
