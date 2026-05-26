package Koha::EmbeddingProvider;

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
use Encode qw(decode_utf8);

use base qw(Koha::Object);

use Koha::BackgroundJob::IndexBiblioEmbeddings;
use Koha::Encryption;
use Koha::EmbeddingProviders;

=head1 NAME

Koha::EmbeddingProvider - Koha EmbeddingProvider Object class

=head1 API

=head2 Class methods

=head3 store

Overridden store method. Encrypts api_key if present. If status is C<active>,
deactivates any other currently-active provider and enqueues a full
C<IndexBiblioEmbeddings> reindex when:

=over 4

=item * The provider is new and being created as active.

=item * An existing provider is transitioning from C<inactive> to C<active>.

=item * An already-active provider has a change to C<model>, C<marc_fields_config>,
or C<request_body_template> — fields that invalidate stored embedding vectors.

=back

Note: changing C<dimensions> requires a full Elasticsearch index rebuild and is
not handled automatically here.

=cut

sub store {
    my ($self) = @_;

    if ( $self->api_key ) {
        $self->api_key( Koha::Encryption->new->encrypt_hex( $self->api_key ) );
    }

    my $should_enqueue = 0;

    if ( $self->status eq 'active' ) {
        my $active_provider = Koha::EmbeddingProviders->search( { status => 'active' } )->next;

        if ( !$self->_result->in_storage ) {

            # New provider being created as active
            $should_enqueue = 1;
        } elsif ( !$active_provider || $active_provider->embedding_provider_id != $self->embedding_provider_id ) {

            # Existing provider transitioning from inactive -> active
            $should_enqueue = 1;
        } else {

            # Already-active provider: enqueue only if a vector-affecting field changed
            $should_enqueue =
                   $active_provider->model ne $self->model
                || ( $active_provider->marc_fields_config // '' ) ne ( $self->marc_fields_config // '' )
                || $active_provider->request_body_template ne $self->request_body_template;
        }

        if ($active_provider) {
            $active_provider->update( { status => 'inactive' } )
                if $active_provider->embedding_provider_id != $self->embedding_provider_id;
        }
    }

    my $result = $self->SUPER::store;

    if ( $should_enqueue && $result ) {
        Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { rebuild_all => 1 } );
    }

    return $result;
}

=head3 plain_text_api_key

    my $key = $provider->plain_text_api_key;

Decrypt and return the api_key in plain text.

=cut

sub plain_text_api_key {
    my ($self) = @_;
    return decode_utf8( Koha::Encryption->new->decrypt_hex( $self->api_key ) )
        if $self->api_key;
}

=head3 to_api

Overridden to_api — strips api_key from all API responses so the encrypted
value is never exposed over the wire.

=cut

sub to_api {
    my ( $self, $params ) = @_;
    my $json = $self->SUPER::to_api($params);
    delete $json->{api_key};
    return $json;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'EmbeddingProvider';
}

1;
