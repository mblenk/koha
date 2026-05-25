package Koha::LLMProvider;

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
use Encode qw( decode_utf8 );

use base qw( Koha::Object );

use Koha::Encryption;
use Koha::LLMProviders;

=head1 NAME

Koha::LLMProvider - Koha LLMProvider Object class

=head1 API

=head2 Class methods

=head3 store

Overridden store method. Encrypts api_key if present, then deactivates all
other providers before saving if status is 'active'.

=cut

sub store {
    my ($self) = @_;

    if ( $self->status eq 'active' ) {
        my $active_provider = Koha::LLMProviders->search( { status => 'active' } )->next;
        if ($active_provider) {
            $active_provider->update( { status => 'inactive' } )
                if $active_provider->llm_provider_id != $self->llm_provider_id;
        }
    }

    return $self->SUPER::store;
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
    return 'LlmProvider';
}

1;
