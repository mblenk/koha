package Koha::SearchEngine::Embedder;

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

Koha::SearchEngine::Embedder - provider-agnostic text embedding client

=head1 SYNOPSIS

    use Koha::SearchEngine::Embedder;

    my $embedder = Koha::SearchEngine::Embedder->new();
    my $vector   = $embedder->embed("books about the French Revolution");
    # $vector is an arrayref of floats, or undef on failure

    my $text = Koha::SearchEngine::Embedder->text_for_biblio($biblionumber);

=head1 DESCRIPTION

Sends text to an embedding API and returns a dense vector (arrayref of floats).
The provider is selected via the C<VectorSearchProvider> system preference.

Built-in providers:

=over 4

=item C<ollama> — Ollama local API (POST /api/embeddings)

=item C<openai> — OpenAI-compatible API (POST /v1/embeddings)

=item C<voyage> — Voyage AI / Anthropic (POST /v1/embeddings, array input)

=item C<cohere> — Cohere API (POST /v1/embed, array input)

=back

New providers can be added by inserting an entry into C<%PROVIDER_CONFIG>.

Returns C<undef> silently on any failure so callers can degrade gracefully.

=head1 METHODS

=cut

use Modern::Perl;

use Try::Tiny qw( catch try );
use LWP::UserAgent;
use HTTP::Request;
use JSON qw( decode_json encode_json );
use C4::Context;
use Koha::Biblios;

use constant MAX_TEXT_LENGTH => 2000;
use constant LWP_TIMEOUT     => 30;

my $PROVIDER_CONFIG = {
    ollama => {
        label       => 'Ollama (local)',
        url         => 'http://localhost:11434/api/embeddings',
        auth        => 'none',
        build_input => sub { ( prompt => $_[0] ) },
        extract     => sub { $_[0]->{embedding} },
    },
    openai => {
        label       => 'OpenAI-compatible API',
        url         => 'https://api.openai.com/v1/embeddings',
        auth        => 'bearer',
        build_input => sub { ( input => $_[0] ) },
        extract     => sub { $_[0]->{data}[0]{embedding} },
    },
    voyage => {
        label       => 'Voyage AI (Anthropic)',
        url         => 'https://api.voyageai.com/v1/embeddings',
        auth        => 'bearer',
        build_input => sub { ( input => [ $_[0] ] ) },
        extract     => sub { $_[0]->{data}[0]{embedding} },
    },
    cohere => {
        label       => 'Cohere',
        url         => 'https://api.cohere.ai/v1/embed',
        auth        => 'bearer',
        build_input => sub { ( texts => [ $_[0] ] ) },
        extract     => sub { $_[0]->{embeddings}[0] },
    },
};

=head2 providers

    my $providers = Koha::SearchEngine::Embedder->providers();

Returns a hashref of C<< { provider_key => display_label } >> for all built-in
providers. Used to populate the C<VectorSearchProvider> system preference dropdown.

=cut

sub providers {
    return { map { $_ => $PROVIDER_CONFIG->{$_}{label} } keys %{$PROVIDER_CONFIG} };
}

=head2 new

    my $embedder = Koha::SearchEngine::Embedder->new( %args );

Constructor. C<provider> and C<model> are required — they must be supplied either
as named arguments or via the corresponding system preferences. Dies if either is
missing or empty. C<api_key> is optional (leave unset for Ollama). The endpoint
URL is determined by the provider and lives in C<$PROVIDER_CONFIG>.

    provider    — embedding provider key (VectorSearchProvider)
    model       — model name            (VectorSearchModel)
    api_key     — API key               (VectorSearchAPIKey)

=cut

sub new {
    my ( $class, %args ) = @_;

    my $provider = $args{provider} // C4::Context->preference('VectorSearchProvider');
    my $model    = $args{model}    // C4::Context->preference('VectorSearchModel');

    die "Koha::SearchEngine::Embedder: VectorSearchProvider is not configured"
        unless $provider;
    die "Koha::SearchEngine::Embedder: VectorSearchModel is not configured"
        unless $model;

    my $self = {
        _provider => $provider,
        _model    => $model,
        _api_key  => $args{api_key} // C4::Context->preference('VectorSearchAPIKey') // '',
        _ua       => LWP::UserAgent->new( timeout => LWP_TIMEOUT ),
    };
    return bless $self, $class;
}

=head2 embed

    my $vector = $embedder->embed( $text );

Returns an arrayref of floats on success, or C<undef> on empty input or any
failure (HTTP error, network error, unexpected response).

=cut

sub embed {
    my ( $self, $text ) = @_;
    return undef unless defined $text && length $text;

    $text = substr( $text, 0, MAX_TEXT_LENGTH ) if length($text) > MAX_TEXT_LENGTH;

    my $vector = try {
        $self->_do_embed($text);
    } catch {
        warn "Koha::SearchEngine::Embedder: embedding failed: $_";
        undef;
    };

    return $vector;
}

=head2 text_for_biblio

    my $text = Koha::SearchEngine::Embedder->text_for_biblio( $biblionumber );

Builds the plain-text representation of a biblio record for embedding.
Concatenates title, subtitle, author, subject headings (6XX $a), and abstract.
Returns C<undef> if the record is not found or produces no content.

Can be called as either a class or instance method.

=cut

sub text_for_biblio {
    my ( $class_or_self, $biblionumber ) = @_;

    my $biblio = Koha::Biblios->find($biblionumber);
    return undef unless $biblio;

    my @parts;
    push @parts, $biblio->title    if $biblio->title;
    push @parts, $biblio->subtitle if $biblio->subtitle;
    push @parts, $biblio->author   if $biblio->author;

    my $record = $biblio->metadata->record;
    if ($record) {
        for my $field ( $record->field('6..') ) {
            my $subfield_a = $field->subfield('a');
            push @parts, $subfield_a if $subfield_a;
        }
        for my $field ( $record->field('520') ) {
            my $subfield_a = $field->subfield('a');
            push @parts, $subfield_a if $subfield_a;
        }
    }

    return undef unless @parts;

    my $text = join( ' ', @parts );
    $text = substr( $text, 0, MAX_TEXT_LENGTH ) if length($text) > MAX_TEXT_LENGTH;
    return $text;
}

=head2 _do_embed

    my $embedding = $self->_do_embed( $text );

Internal dispatcher. Looks up the active provider in C<$PROVIDER_CONFIG>,
builds and sends the HTTP request, and returns the embedding arrayref.
Dies on HTTP error, missing embedding, or unknown provider — the caller
(C<embed>) catches and converts to C<undef>.

=cut

sub _do_embed {
    my ( $self, $text ) = @_;

    my $config = $PROVIDER_CONFIG->{ $self->{_provider} }
        or die "Unknown embedding provider '$self->{_provider}'";

    my $req = HTTP::Request->new( POST => $config->{url} );
    $req->content_type('application/json; charset=UTF-8');
    $req->header( 'Authorization' => 'Bearer ' . $self->{_api_key} )
        if $config->{auth} eq 'bearer' && $self->{_api_key};
    $req->content( encode_json( { model => $self->{_model}, $config->{build_input}->($text) } ) );

    my $response = $self->{_ua}->request($req);
    die "HTTP " . $response->status_line unless $response->is_success;

    my $data      = decode_json( $response->decoded_content );
    my $embedding = $config->{extract}->($data);
    die "No embedding in response from '$self->{_provider}'"
        unless ref($embedding) eq 'ARRAY';

    return $embedding;
}

1;
