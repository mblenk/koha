package Koha::BackgroundJob::IndexBiblioEmbeddings;

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

use Koha::SearchEngine;
use Koha::SearchEngine::Elasticsearch;
use Koha::SearchEngine::Embedder;

use base 'Koha::BackgroundJob';

=head1 NAME

Koha::BackgroundJob::IndexBiblioEmbeddings - Generate and index vector
embeddings for bibliographic records

This is a subclass of Koha::BackgroundJob.

Each job takes a list of biblionumbers, generates an embedding for each record
via L<Koha::SearchEngine::Embedder>, and updates the Elasticsearch document
using a partial C<doc> update so the MARC data is never overwritten.

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type { return 'index_biblio_embeddings' }

=head3 enqueue

Enqueue a new embedding job.

    Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue({
        record_ids => \@biblionumbers,
    });

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    return unless exists $args->{record_ids};
    return unless ref( $args->{record_ids} ) eq 'ARRAY';
    return unless @{ $args->{record_ids} };

    $self->SUPER::enqueue(
        {
            job_size  => scalar @{ $args->{record_ids} },
            job_args  => { record_ids => $args->{record_ids} },
            job_queue => 'long_tasks',
        }
    );
}

=head3 process

Process the job: generate and store embeddings for each biblionumber.

=cut

sub process {
    my ( $self, $args ) = @_;

    return if $self->status eq 'cancelled';

    $self->start;

    my @record_ids = @{ $args->{record_ids} };
    my $embedder   = Koha::SearchEngine::Embedder->new;
    my $es_obj     = Koha::SearchEngine::Elasticsearch->new(
        { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
    my $es = $es_obj->get_elasticsearch;

    my $report = {
        total   => scalar @record_ids,
        success => 0,
        skipped => 0,
    };

    my @bulk_body;

    my $flush_to_es = sub {
        return unless @bulk_body;
        try {
            my $response = $es->bulk(
                index => $es_obj->index_name,
                body  => \@bulk_body,
            );
            warn "IndexBiblioEmbeddings: some ES bulk update errors occurred\n"
                if $response->{errors};
        } catch {
            warn "IndexBiblioEmbeddings: ES bulk update failed: $_\n";
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

    for my $biblionumber ( sort { $a <=> $b } @record_ids ) {
        last if $self->get_from_storage->status eq 'cancelled';

        my $text = Koha::SearchEngine::Embedder->text_for_biblio($biblionumber);
        unless ($text) {
            $report->{skipped}++;
            $self->step;
            next;
        }

        push @pending, { biblionumber => $biblionumber, text => $text };
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
