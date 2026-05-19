package Koha::BackgroundJob::RebuildAllEmbeddings;

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

use Try::Tiny qw( catch try );

use Koha::Biblios;
use Koha::SearchEngine;
use Koha::SearchEngine::Elasticsearch;
use Koha::SearchEngine::Embedder;

use base 'Koha::BackgroundJob';

=head1 NAME

Koha::BackgroundJob::RebuildAllEmbeddings - Regenerate vector embeddings for
every bibliographic record

This is a subclass of Koha::BackgroundJob.

Triggered automatically when an embedding provider is activated or its
configuration changes. Iterates all biblios, generates a fresh
embedding via L<Koha::SearchEngine::Embedder>, and updates the Elasticsearch
document with a partial C<doc> update so MARC data is never overwritten.

Unlike L<Koha::BackgroundJob::IndexBiblioEmbeddings>, this job handles all 
records. The search layer uses this type to detect an in-progress full reindex
and temporarily fall back to keyword search.

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type { return 'rebuild_all_embeddings' }

=head3 enqueue

Enqueue a full-catalogue embedding rebuild.

    Koha::BackgroundJob::RebuildAllEmbeddings->new->enqueue({});

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    my $job_size = Koha::Biblios->search->count;
    return unless $job_size;

    $self->SUPER::enqueue(
        {
            job_size  => $job_size,
            job_args  => {},
            job_queue => 'long_tasks',
        }
    );
}

=head3 process

Process the job: iterate all biblios, generate embeddings, and store them via
partial ES update. Flushes to ES every 100 records.

=cut

sub process {
    my ( $self, $args ) = @_;

    return if $self->status eq 'cancelled';

    $self->start;

    my $embedder = Koha::SearchEngine::Embedder->new;
    my $elastic_search   = Koha::SearchEngine::Elasticsearch->new(
        { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
    my $es = $elastic_search->get_elasticsearch;

    my $report = {
        total   => 0,
        success => 0,
        skipped => 0,
    };

    my @bulk_body;

    my $flush_to_es = sub {
        return unless @bulk_body;
        try {
            my $response = $es->bulk(
                index => $elastic_search->index_name,
                body  => \@bulk_body,
            );
            if ( $response->{errors} ) {
                warn "RebuildAllEmbeddings: some ES bulk update errors occurred\n";
            }
        } catch {
            warn "RebuildAllEmbeddings: ES bulk update failed: $_\n";
        };
        @bulk_body = ();
    };

    my $batch_size = $embedder->{_batch_size} // 1;
    my @pending;    # [ { biblionumber => N, text => "..." }, ... ]

    my $process_pending = sub {
        return unless @pending;
        my $vectors = $embedder->embed_batch( [ map { $_->{text} } @pending ] );
        for my $i ( 0 .. $#pending ) {
            my $vector = $vectors->[$i];
            unless ($vector) {
                $report->{skipped}++;
                next;
            }
            push @bulk_body, { update => { _id => $pending[$i]{biblionumber} . q{} } };
            push @bulk_body, { doc    => { embedding => $vector } };
            $report->{success}++;
        }
        @pending = ();
        $flush_to_es->() if @bulk_body >= 200;
    };

    my $rs = Koha::Biblios->search(
        {},
        { order_by => { -asc => 'biblionumber' } }
    );

    while ( my $biblio = $rs->next ) {
        last if $self->get_from_storage->status eq 'cancelled';

        $report->{total}++;

        my $text = $embedder->text_for_biblio( $biblio->biblionumber );
        unless ($text) {
            $report->{skipped}++;
            $self->step;
            next;
        }

        push @pending, { biblionumber => $biblio->biblionumber, text => $text };
        $process_pending->() if @pending >= $batch_size;
        $self->step;
    }

    $process_pending->();
    $flush_to_es->();

    my $data = $self->decoded_data;
    $data->{report} = $report;
    $self->finish($data);
}

1;
