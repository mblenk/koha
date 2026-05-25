package Koha::REST::V1::Search::Agent;

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

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use C4::Context;
use Koha::EmbeddingProviders;
use Koha::LLMProviders;
use Koha::SearchEngine::SearchAgent;

use Try::Tiny qw( catch try );

=head1 API

=head2 Methods

=head3 converse

POST /api/v1/search/agent

Run one conversation turn: semantic search + LLM response.

=cut

sub converse {
    my $c = shift->openapi->valid_input or return;

    return $c->render(
        status  => 401,
        openapi => { error => 'Authentication required' }
    ) unless $c->stash('koha.user');

    unless ( C4::Context->preference('VectorSearchEnabled') ) {
        return $c->render(
            status  => 503,
            openapi => { error => 'VectorSearchEnabled is off' }
        );
    }

    unless ( Koha::EmbeddingProviders->search( { status => 'active' } )->count ) {
        return $c->render(
            status  => 503,
            openapi => { error => 'No active embedding provider configured' }
        );
    }

    unless ( Koha::LLMProviders->search( { status => 'active' } )->count ) {
        return $c->render(
            status  => 503,
            openapi => { error => 'No active LLM provider configured' }
        );
    }

    my $body      = $c->req->json;
    my $query     = $body->{query}        // '';
    my $history   = $body->{conversation} // [];
    my $interface = $body->{interface}    // 'opac';

    return $c->render(
        status  => 400,
        openapi => { error => 'query is required' }
    ) unless length $query;

    my $search_base =
        $interface eq 'opac'
        ? '/cgi-bin/koha/opac-search.pl'
        : '/cgi-bin/koha/catalogue/search.pl';

    return try {
        my $agent = Koha::SearchEngine::SearchAgent->new( search_url => $search_base );

        my $result = $agent->converse(
            query   => $query,
            history => $history,
        );

        return $c->render(
            status  => 503,
            openapi => { error => 'LLM call failed' }
        ) unless $result;

        return $c->render(
            status  => 200,
            openapi => {
                reply        => $result->{reply},
                results      => $result->{results},
                conversation => $result->{conversation},
                search_url   => $result->{search_url},
            }
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
