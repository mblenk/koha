package Koha::SearchEngine::ProviderClient;

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

Koha::SearchEngine::ProviderClient - shared HTTP helpers for provider-backed clients

=head1 DESCRIPTION

Base class providing the low-level HTTP and template-substitution helpers shared
by L<Koha::SearchEngine::LLMClient> and L<Koha::SearchEngine::Embedder>.

Not intended to be instantiated directly. Subclasses define their own
constructors and use C<use parent 'Koha::SearchEngine::ProviderClient'> to
inherit these methods. The subclass constructor is expected to populate at
minimum: C<_url>, C<_api_key>, C<_auth_type>, and C<_ua>.

=cut

use Modern::Perl;

use HTTP::Request;
use LWP::UserAgent;

=head1 METHODS

=head2 _make_request

    my $response = $self->_make_request($json_body);

Sends a POST request to the configured provider URL with the given JSON body.
Adds a C<Bearer> Authorization header when C<auth_type> is C<bearer> and an
API key is set. Returns the L<HTTP::Response> object.

=cut

sub _make_request {
    my ( $self, $body ) = @_;
    my $req = HTTP::Request->new( POST => $self->{_url} );
    $req->content_type('application/json; charset=UTF-8');
    $req->header( 'Authorization' => 'Bearer ' . $self->{_api_key} )
        if $self->{_auth_type} eq 'bearer' && $self->{_api_key};
    $req->content($body);
    return $self->{_ua}->request($req);
}

=head2 _resolve_path

    my $value = $self->_resolve_path($data, 'choices.0.message.content');

Traverses a decoded JSON structure using a dot-notation path. Numeric path
components are treated as array indices; non-numeric as hash keys. Returns
C<undef> if any step along the path is missing.

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

=head2 _substitute_sentinels

    $self->_substitute_sentinels( $structure, \%subs );

Recursively walks a decoded JSON structure (hashrefs and arrayrefs) and applies
L</_apply_subs> to every leaf string value. Modifies the structure in place.

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
    my ( $self, $node, $subs ) = @_;

    if ( ref($node) eq 'HASH' ) {
        for my $key ( keys %$node ) {
            if ( ref( $node->{$key} ) ) {
                $self->_substitute_sentinels( $node->{$key}, $subs );
            } else {
                $node->{$key} = _apply_subs( $node->{$key}, $subs );
            }
        }
    } elsif ( ref($node) eq 'ARRAY' ) {
        for my $i ( 0 .. $#$node ) {
            if ( ref( $node->[$i] ) ) {
                $self->_substitute_sentinels( $node->[$i], $subs );
            } else {
                $node->[$i] = _apply_subs( $node->[$i], $subs );
            }
        }
    }
}

=head2 _apply_subs

    my $result = _apply_subs( $val, \%subs );

Applies sentinel substitutions to a single string value. See
L</_substitute_sentinels> for the three-mode priority order (exact match,
array expansion, scalar substring).

=cut

sub _apply_subs {
    my ( $val, $subs ) = @_;
    $val //= '';

    return $subs->{$val} if exists $subs->{$val};

    for my $sentinel ( keys %$subs ) {
        if ( ref( $subs->{$sentinel} ) eq 'ARRAY' && index( $val, $sentinel ) >= 0 ) {
            return [
                map {
                    my $v = $val;
                    $v =~ s/\Q$sentinel\E/$_/g;
                    for my $s ( keys %$subs ) {
                        next if ref( $subs->{$s} );
                        $v =~ s/\Q$s\E/$subs->{$s}/g;
                    }
                    $v
                } @{ $subs->{$sentinel} }
            ];
        }
    }

    for my $sentinel ( keys %$subs ) {
        next if ref( $subs->{$sentinel} );
        $val =~ s/\Q$sentinel\E/$subs->{$sentinel}/g;
    }
    return $val;
}

1;
