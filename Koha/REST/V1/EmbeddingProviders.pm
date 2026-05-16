package Koha::REST::V1::EmbeddingProviders;

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

use Koha::EmbeddingProviders;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

=head1 API

=head2 Methods

=head3 list

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        return $c->render(
            status  => 200,
            openapi => $c->objects->search( Koha::EmbeddingProviders->new )
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $provider = $c->objects->find(
            Koha::EmbeddingProviders->new,
            $c->param('embedding_provider_id')
        );
        return $c->render_resource_not_found("Embedding provider")
            unless $provider;

        return $c->render( status => 200, openapi => $provider );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $provider = Koha::EmbeddingProvider->new_from_api( $c->req->json );
        $provider->store;
        $c->res->headers->location( $c->req->url->to_string . '/' . $provider->embedding_provider_id );
        return $c->render(
            status  => 201,
            openapi => $c->objects->to_api($provider)
        );
    } catch {
        if ( blessed $_ and $_->isa('Koha::Exceptions::Object::DuplicateID') ) {
            return $c->render(
                status  => 409,
                openapi => { error => 'Duplicate name.' }
            );
        }
        $c->unhandled_exception($_);
    };
}

=head3 update

=cut

sub update {
    my $c = shift->openapi->valid_input or return;

    my $provider = $c->objects->find_rs(
        Koha::EmbeddingProviders->new,
        $c->param('embedding_provider_id')
    );

    return $c->render_resource_not_found("Embedding provider")
        unless $provider;

    return try {
        $provider->set_from_api( $c->req->json )->store;
        $provider->discard_changes;
        return $c->render( status => 200, openapi => $c->objects->to_api($provider) );
    } catch {
        if ( blessed $_ and $_->isa('Koha::Exceptions::Object::DuplicateID') ) {
            return $c->render(
                status  => 409,
                openapi => { error => 'Duplicate name.' }
            );
        }
        $c->unhandled_exception($_);
    };
}

=head3 delete

=cut

sub delete {
    my $c = shift->openapi->valid_input or return;

    my $provider = $c->objects->find_rs(
        Koha::EmbeddingProviders->new,
        $c->param('embedding_provider_id')
    );

    return $c->render_resource_not_found("Embedding provider")
        unless $provider;

    return try {
        $provider->delete;
        return $c->render_resource_deleted;
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
