package Koha::Template::Plugin::BackgroundJob;

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

use Template::Plugin;
use base qw( Template::Plugin );

use Koha::BackgroundJob::IndexBiblioEmbeddings;
use Koha::LLMProviders;

=head1 NAME

Koha::Template::Plugin::BackgroundJob - TT plugin for background job state queries

=head1 SYNOPSIS

    [% USE BackgroundJob %]
    [% IF BackgroundJob.EmbeddingReindexInProgress %]
    [% IF BackgroundJob.LLMProviderActive %]

=head1 API

=head2 Class Methods

=head3 EmbeddingReindexInProgress

Returns true when an C<index_biblio_embeddings> full-rebuild job is active
(status C<new> or C<started>).

=cut

sub EmbeddingReindexInProgress {
    return Koha::BackgroundJob::IndexBiblioEmbeddings->rebuild_in_progress;
}

=head3 LLMProviderActive

Returns true when at least one LLM provider has C<status = active>.

=cut

sub LLMProviderActive {
    return Koha::LLMProviders->search( { status => 'active' } )->count ? 1 : 0;
}

1;
