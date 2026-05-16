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

use base qw(Koha::Object);

use Koha::EmbeddingProviders;

=head1 NAME

Koha::EmbeddingProvider - Koha EmbeddingProvider Object class

=head1 API

=head2 Class methods

=head3 store

Overridden store method. When saving a provider with status 'active',
deactivates all other providers first so only one can be active at a time.

=cut

sub store {
    my ($self) = @_;

    if ( $self->status eq 'active' ) {
        my $active_provider = Koha::EmbeddingProviders->search( { status => 'active' } )->next;
        if ($active_provider) {
            $active_provider->update( { status => 'inactive' } )
                if $active_provider->embedding_provider_id != $self->embedding_provider_id;
        }
    }

    return $self->SUPER::store;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'EmbeddingProvider';
}

1;
