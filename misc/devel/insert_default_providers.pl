#!/usr/bin/perl

# Copyright 2026 Openfifth
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

insert_default_providers.pl - Insert default Ollama embedding and LLM provider records

=head1 SYNOPSIS

insert_default_providers.pl [--embed-url <url>]

  --embed-url  Full URL of the Ollama embedding endpoint
               (default: http://ollama:11434/api/embeddings)
  -h|--help    Show this help

=head1 DESCRIPTION

Inserts two provider records into the database:

  1. An embedding provider using nomic-embed-text (set as active)
  2. A Claude stub LLM provider on port 11435 of the Docker host (set as active)

Skips insertion if a record with the same name already exists, so the script
is safe to run more than once.

=cut

use Modern::Perl;
use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );

use Koha::Script;
use C4::Context;
use Koha::EmbeddingProvider;
use Koha::EmbeddingProviders;
use Koha::LLMProvider;
use Koha::LLMProviders;

my $embed_url = 'http://ollama:11434/api/embed';
my $help;

GetOptions(
    'embed-url=s' => \$embed_url,
    'h|help'      => \$help,
) or pod2usage(1);

pod2usage(0) if $help;

# --- Embedding provider (nomic-embed-text) ---

my $embed_name = 'Ollama nomic-embed-text';

my $marc_fields_config = <<'YAML';
biblio_fields:
  - title
  - subtitle
  - author
marc_fields:
  - tag: "6.."
    subfield: "a"
    include_authorities: true
  - tag: "520"
    subfield: "a"
YAML

if ( Koha::EmbeddingProviders->search( { name => $embed_name } )->count ) {
    say "SKIP: Embedding provider '$embed_name' already exists";
} else {
    Koha::EmbeddingProvider->new(
        {
            name                  => $embed_name,
            url                   => $embed_url,
            model                 => 'nomic-embed-text',
            auth_type             => 'none',
            request_body_template => '{"model":"{{model}}","input":"search_document: {{text}}"}',
            query_body_template   => '{"model":"{{model}}","input":"search_query: {{text}}"}',
            response_key          => 'embeddings.0',
            dimensions            => 768,
            batch_size            => 100,
            status                => 'active',
            marc_fields_config    => $marc_fields_config,
        }
    )->store;
    say "OK:   Inserted embedding provider '$embed_name'";
    say "      URL: $embed_url";
}

# --- LLM provider (Claude stub) ---

my $llm_name = 'Claude stub (local dev)';
my $llm_url  = 'http://host.docker.internal:11435/v1/chat/completions';

if ( Koha::LLMProviders->search( { name => $llm_name } )->count ) {
    say "SKIP: LLM provider '$llm_name' already exists";
} else {
    Koha::LLMProvider->new(
        {
            name                  => $llm_name,
            url                   => $llm_url,
            model                 => 'claude-stub',
            api_key               => '',
            auth_type             => 'none',
            request_body_template => '{"model":"{{model}}","messages":"{{messages}}","stream":false}',
            response_key          => 'choices.0.message.content',
            status                => 'active',
        }
    )->store;
    say "OK:   Inserted LLM provider '$llm_name'";
    say "      URL: $llm_url";
}

# --- Enable AgentSearchEnabled ---

if ( C4::Context->preference('AgentSearchEnabled') ) {
    say "SKIP: AgentSearchEnabled is already enabled";
} else {
    C4::Context->set_preference( 'AgentSearchEnabled', 1 );
    say "OK:   Enabled AgentSearchEnabled syspref";
}
