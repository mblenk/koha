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

Koha::SearchEngine::Embedder - data-driven text embedding client

=head1 SYNOPSIS

    use Koha::SearchEngine::Embedder;

    my $embedder = Koha::SearchEngine::Embedder->new();
    my $vector   = $embedder->embed_query("books about the French Revolution");
    # $vector is an arrayref of floats, or undef on failure

    my $text = Koha::SearchEngine::Embedder->text_for_biblio($biblionumber);

=head1 DESCRIPTION

Sends text to an embedding API and returns a dense vector (arrayref of floats).
All configuration — endpoint URL, model, auth, request/response format — is
read from the active row in the C<embedding_providers> table.

Returns C<undef> silently on any failure so callers can degrade gracefully.

=head1 METHODS

=cut

use Modern::Perl;

use Try::Tiny qw( catch try );
use LWP::UserAgent;
use HTTP::Request;
use JSON     qw( decode_json encode_json );
use YAML::XS qw();
use Encode   qw( encode_utf8 );
use Koha::Biblios;
use Koha::EmbeddingProviders;

use constant MAX_TEXT_LENGTH => 2000;
use constant LWP_TIMEOUT     => 30;

=head2 new

    my $embedder = Koha::SearchEngine::Embedder->new( %args );

Constructor. In production, reads all configuration from the active
C<embedding_providers> row. For tests, all fields may be supplied directly
as named arguments (presence of C<url> triggers the test bypass path):

    url                   — embedding API endpoint
    model                 — model name
    api_key               — bearer token (optional)
    auth_type             — 'none' or 'bearer' (default: 'none')
    request_body_template — JSON template with {{text}} and {{model}} sentinels
    response_key          — dot-notation path to the embedding in the response

Dies if no active provider is configured and no args are supplied.

=cut

sub new {
    my ( $class, $args ) = @_;
    $args //= {};

    my ( $url, $model, $api_key, $auth_type, $request_body_template, $query_body_template, $response_key );

    my $marc_fields_config;

    if ( $args->{url} ) {
        $url                   = $args->{url};
        $model                 = $args->{model}                 // die "model required";
        $api_key               = $args->{api_key}               // '';
        $auth_type             = $args->{auth_type}             // 'none';
        $request_body_template = $args->{request_body_template} // die "request_body_template required";
        $query_body_template   = $args->{query_body_template};
        $response_key          = $args->{response_key}       // 'data.0.embedding';
        $marc_fields_config    = $args->{marc_fields_config} // {};
    } else {
        my $record = Koha::EmbeddingProviders->search( { status => 'active' } )->next;
        die "Koha::SearchEngine::Embedder: No active embedding provider configured"
            unless $record;
        $url                   = $record->url;
        $model                 = $record->model;
        $api_key               = $record->plain_text_api_key // '';
        $auth_type             = $record->auth_type;
        $request_body_template = $record->request_body_template;
        $query_body_template   = $record->query_body_template;
        $response_key          = $record->response_key;
        $marc_fields_config    = eval { YAML::XS::Load( encode_utf8( $record->marc_fields_config // '' ) ) } // {};
        $args->{batch_size}    = $record->batch_size // 1;
    }

    my $self = {
        _url                   => $url,
        _model                 => $model,
        _api_key               => $api_key,
        _auth_type             => $auth_type,
        _request_body_template => $request_body_template,
        _query_body_template   => $query_body_template,
        _response_key          => $response_key,
        _marc_fields_config    => $marc_fields_config,
        _batch_size            => $args->{batch_size} // 1,
        _ua                    => LWP::UserAgent->new( timeout => LWP_TIMEOUT ),
    };
    return bless $self, $class;
}

=head2 embed_query

    my $vector = $embedder->embed_query( $text );

Embeds a search query. Uses C<query_body_template> (falls back to
C<request_body_template> when no query template is configured). Returns an
arrayref of floats, or C<undef> on empty input or any failure.

Use this method when embedding text that will be used as a search query.
For indexing document text, use C<embed_document> instead — asymmetric models
such as nomic-embed-text require different prefixes for queries vs. documents.

=cut

sub embed_query {
    my ( $self, $text ) = @_;
    return undef unless defined $text && length $text;

    $text = substr( $text, 0, MAX_TEXT_LENGTH ) if length($text) > MAX_TEXT_LENGTH;

    my $vector = try {
        $self->_do_embed( $text, $self->{_query_body_template} );
    } catch {
        warn "Koha::SearchEngine::Embedder: embedding failed: $_";
        undef;
    };

    return $vector;
}

=head2 embed_document

    my $vector = $embedder->embed_document( $text );

Embeds a document for indexing. Always uses C<request_body_template>, ensuring
the correct instruction/prefix is applied for asymmetric embedding models (e.g.
nomic-embed-text uses C<search_document:> for stored documents and
C<search_query:> for queries). Returns an arrayref of floats, or C<undef> on
empty input or any failure.

Use this method when generating vectors to store against a biblio record.
For embedding search queries, use C<embed_query> instead.

=cut

sub embed_document {
    my ( $self, $text ) = @_;
    return undef unless defined $text && length $text;

    $text = substr( $text, 0, MAX_TEXT_LENGTH ) if length($text) > MAX_TEXT_LENGTH;

    my $vector = try {
        $self->_do_embed( $text, undef );    # undef → uses _request_body_template
    } catch {
        warn "Koha::SearchEngine::Embedder: document embedding failed: $_";
        undef;
    };

    return $vector;
}

=head2 embed_batch

    my $vectors = $embedder->embed_batch( \@texts );

Embeds multiple document texts in as few API calls as possible, grouping them
into chunks of C<batch_size>. Returns an arrayref of vectors (arrayrefs of
floats) in the same order as the input. Any text that fails to embed is
returned as C<undef>.

Uses C<request_body_template> (document space) for all embeddings, including
the sequential fallback. When C<batch_size> is 1 (the default) this is
equivalent to calling C<embed_document> on each text in turn. For query
embedding, use C<embed_query> instead.

=cut

sub embed_batch {
    my ( $self, $texts ) = @_;

    my $batch_size = $self->{_batch_size} // 1;

    if ( $batch_size <= 1 ) {
        return [ map { $self->embed_document($_) } @$texts ];
    }

    my @results;
    my @chunk;

    for my $text (@$texts) {
        push @chunk, $text;
        if ( @chunk >= $batch_size ) {
            push @results, @{ $self->_embed_chunk( \@chunk ) };
            @chunk = ();
        }
    }
    # Captures any remaining texts that don't fall into the batch sizing.
    # E.g. batch_size = 10 but there are 12 texts, a batch of 10 will run
    # but leave 2 texts unprocessed as they don't trigger the next batch
    push @results, @{ $self->_embed_chunk( \@chunk ) } if @chunk;

    return \@results;
}

sub _embed_chunk {
    my ( $self, $chunk_ref ) = @_;
    my $vectors = try { $self->_do_embed_batch($chunk_ref) }
    catch {
        [ map { $self->embed_document($_) } @$chunk_ref ]
    };
    return $vectors;
}

=head2 _do_embed_batch

    my $vectors = $self->_do_embed_batch( \@texts );

Sends a single batch HTTP request for an arrayref of texts and returns an
arrayref of embedding vectors. Dies on any failure so the caller can fall back.

=cut

sub _do_embed_batch {
    my ( $self, $texts_ref ) = @_;

    my @texts = map { length($_) > MAX_TEXT_LENGTH ? substr( $_, 0, MAX_TEXT_LENGTH ) : $_ } @$texts_ref;

    my $body = $self->_build_batch_request_body( \@texts );

    my $req = HTTP::Request->new( POST => $self->{_url} );
    $req->content_type('application/json; charset=UTF-8');
    $req->header( 'Authorization' => 'Bearer ' . $self->{_api_key} )
        if $self->{_auth_type} eq 'bearer' && $self->{_api_key};
    $req->content($body);

    my $response = $self->{_ua}->request($req);
    die "HTTP " . $response->status_line unless $response->is_success;

    my $data       = decode_json( $response->decoded_content );
    my $embeddings = $self->_resolve_batch_path( $data, $self->{_response_key} );
    die "No embeddings array in batch response from '$self->{_url}'"
        unless ref($embeddings) eq 'ARRAY' && @$embeddings;

    die sprintf "Batch embedding returned %d vector(s) for %d input(s) — provider may not support batch requests",
        scalar @$embeddings, scalar @texts
        unless @$embeddings == @texts;

    return $embeddings;
}

=head2 _build_batch_request_body

    my $json = $self->_build_batch_request_body( \@texts );

Like C<_build_request_body> but substitutes C<{{text}}> with an arrayref so that
C<encode_json> serialises it as a JSON array — the format expected by batch-capable
providers (C</api/embed>).

=cut

sub _build_batch_request_body {
    my ( $self, $texts_ref ) = @_;

    my $structure = decode_json( $self->{_request_body_template} );
    my %subs      = (
        '{{text}}'  => $texts_ref,
        '{{model}}' => $self->{_model},
    );
    _substitute_sentinels( $structure, \%subs );
    return encode_json($structure);
}

=head2 _resolve_batch_path

    my $vectors = $self->_resolve_batch_path( $data, $path );

Extends C<_resolve_path> for batch responses. Locates the first numeric segment in the
dot-notation C<$path>, treats the container before it as the per-item array, and
navigates the remaining suffix on each element:

    "data.0.embedding"  →  map { $_->{embedding} } @{ $data->{data} }
    "embeddings.0"      →  @{ $data->{embeddings} }

If no array is detected we fall back to _resolve_path

=cut

sub _resolve_batch_path {
    my ( $self, $data, $path ) = @_;

    my @segments = split /\./, $path;

    my $array_position;
    for my $i ( 0 .. $#segments ) {
        if ( $segments[$i] =~ /^\d+$/ ) { $array_position = $i; last; }
    }

    unless ( defined $array_position ) {
        my $vectors = $self->_resolve_path( $data, $path );
        return ref($vectors) eq 'ARRAY' ? $vectors : undef;
    }

    my $prefix    = $array_position > 0          ? join( '.', @segments[ 0 .. $array_position - 1 ] )          : '';
    my $suffix    = $array_position < $#segments ? join( '.', @segments[ $array_position + 1 .. $#segments ] ) : '';
    my $container = $prefix                      ? $self->_resolve_path( $data, $prefix )                      : $data;
    return undef unless ref($container) eq 'ARRAY';

    return $suffix
        ? [ map { $self->_resolve_path( $_, $suffix ) } @$container ]
        : $container;
}

=head2 text_for_biblio

    my $text = Koha::SearchEngine::Embedder->text_for_biblio( $biblionumber );

Builds the plain-text representation of a biblio record for embedding.
Concatenates title, subtitle, author, subject headings (6XX $a), and abstract.
Returns C<undef> if the record is not found or produces no content.

Can be called as either a class or instance method.

=cut

sub text_for_biblio {
    my ( $self, $biblionumber ) = @_;

    my $config = ref($self) ? $self->{_marc_fields_config} : {};

    my $biblio = Koha::Biblios->find($biblionumber);
    return undef unless $biblio;

    my @parts;
    for my $field ( @{ $config->{biblio_fields} // [] } ) {
        my $val = $biblio->can($field) ? $biblio->$field() : undef;
        push @parts, $val if $val;
    }

    if ( @{ $config->{marc_fields} // [] } ) {
        my $record = $biblio->metadata->record;
        if ($record) {
            for my $spec ( @{ $config->{marc_fields} } ) {
                for my $marc_field ( $record->field( $spec->{tag} ) ) {
                    my $val = $marc_field->subfield( $spec->{subfield} );
                    push @parts, $val if $val;
                }
            }
        }
    }

    return undef unless @parts;

    my $text = join( ' ', @parts );
    $text = substr( $text, 0, MAX_TEXT_LENGTH ) if length($text) > MAX_TEXT_LENGTH;
    return $text;
}

=head2 _do_embed

    my $embedding = $self->_do_embed( $text, $template );

Internal dispatcher. Builds the HTTP request body from C<$template> (falls back
to C<_request_body_template> when C<undef>), POSTs to the provider endpoint, and
extracts the embedding vector via the dot-notation C<_response_key>.

Dies on HTTP error, missing embedding, or JSON parse failure; the public callers
(C<embed_query> and C<embed_document>) catch and return C<undef>.

=cut

sub _do_embed {
    my ( $self, $text, $template ) = @_;

    my $body = $self->_build_request_body( $text, $template );

    my $req = HTTP::Request->new( POST => $self->{_url} );
    $req->content_type('application/json; charset=UTF-8');
    $req->header( 'Authorization' => 'Bearer ' . $self->{_api_key} )
        if $self->{_auth_type} eq 'bearer' && $self->{_api_key};
    $req->content($body);

    my $response = $self->{_ua}->request($req);
    die "HTTP " . $response->status_line unless $response->is_success;

    my $data      = decode_json( $response->decoded_content );
    my $embedding = $self->_resolve_path( $data, $self->{_response_key} );
    die "No embedding in response from '$self->{_url}'"
        unless ref($embedding) eq 'ARRAY';

    return $embedding;
}

=head2 _build_request_body

    my $json = $self->_build_request_body( $text );

Decodes the stored request body template as JSON, substitutes C<{{text}}>
and C<{{model}}> sentinel string values with the actual text and model name,
then re-encodes. All JSON escaping is handled by C<encode_json>.

=cut

sub _build_request_body {
    my ( $self, $text, $template ) = @_;
    $template //= $self->{_request_body_template};

    my $structure = decode_json($template);
    my %subs      = (
        '{{text}}'  => $text,
        '{{model}}' => $self->{_model},
    );
    _substitute_sentinels( $structure, \%subs );
    return encode_json($structure);
}

=head2 _substitute_sentinels

    _substitute_sentinels( $node, \%subs );

Recursively walks a decoded JSON structure and substitutes sentinel strings.
Three substitution modes, applied in priority order:

=over 4

=item 1. Exact match: if a string value equals a sentinel key exactly, it is
replaced by the corresponding value (scalar or arrayref).

=item 2. Array expansion: if a sentinel's replacement is an arrayref and the
sentinel appears as a substring of the string value, the field is replaced by
an array of strings — one per element — each with the sentinel substituted by
that element. Used by C<_build_batch_request_body> to fan a single field into a
JSON array of prefixed strings.

=item 3. Scalar substring: remaining sentinel occurrences are replaced
in-place with their scalar values.

=back

=cut

sub _substitute_sentinels {
    my ( $node, $subs ) = @_;

    if ( ref($node) eq 'HASH' ) {
        for my $key ( keys %$node ) {
            if ( !ref( $node->{$key} ) ) {
                my $val = $node->{$key} // '';
                if ( exists $subs->{$val} ) {
                    $node->{$key} = $subs->{$val};
                } else {
                    my $expanded = 0;
                    for my $sentinel ( keys %$subs ) {
                        if ( ref( $subs->{$sentinel} ) eq 'ARRAY' && index( $val, $sentinel ) >= 0 ) {
                            $node->{$key} = [
                                map { ( my $v = $val ) =~ s/\Q$sentinel\E/$_/g; $v }
                                    @{ $subs->{$sentinel} }
                            ];
                            $expanded = 1;
                            last;
                        }
                    }
                    unless ($expanded) {
                        for my $sentinel ( keys %$subs ) {
                            next if ref( $subs->{$sentinel} );
                            $val =~ s/\Q$sentinel\E/$subs->{$sentinel}/g;
                        }
                        $node->{$key} = $val;
                    }
                }
            } else {
                _substitute_sentinels( $node->{$key}, $subs );
            }
        }
    } elsif ( ref($node) eq 'ARRAY' ) {
        for my $i ( 0 .. $#$node ) {
            if ( !ref( $node->[$i] ) ) {
                my $val = $node->[$i] // '';
                if ( exists $subs->{$val} ) {
                    $node->[$i] = $subs->{$val};
                } else {
                    my $expanded = 0;
                    for my $sentinel ( keys %$subs ) {
                        if ( ref( $subs->{$sentinel} ) eq 'ARRAY' && index( $val, $sentinel ) >= 0 ) {
                            $node->[$i] = [
                                map { ( my $v = $val ) =~ s/\Q$sentinel\E/$_/g; $v }
                                    @{ $subs->{$sentinel} }
                            ];
                            $expanded = 1;
                            last;
                        }
                    }
                    unless ($expanded) {
                        for my $sentinel ( keys %$subs ) {
                            next if ref( $subs->{$sentinel} );
                            $val =~ s/\Q$sentinel\E/$subs->{$sentinel}/g;
                        }
                        $node->[$i] = $val;
                    }
                }
            } else {
                _substitute_sentinels( $node->[$i], $subs );
            }
        }
    }
}

=head2 _resolve_path

    my $value = $self->_resolve_path( $data, $path );

Walks a dot-notation path (e.g. C<data.0.embedding>) into a decoded JSON
structure, treating numeric segments as array indices.
Returns C<undef> if any step is missing.

=cut

sub _resolve_path {
    my ( $self, $data, $path ) = @_;

    my $node = $data;
    for my $key ( split /\./, $path ) {
        return undef unless defined $node;
        $node = ref($node) eq 'ARRAY' ? $node->[$key] : $node->{$key};
    }
    return $node;
}

1;
