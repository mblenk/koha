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

use Koha::BackgroundJobs;
use Koha::Biblios;
use Koha::SearchEngine;
use Koha::SearchEngine::Elasticsearch;
use Koha::SearchEngine::Embedder;

use base 'Koha::BackgroundJob';

=head1 NAME

Koha::BackgroundJob::IndexBiblioEmbeddings - Generate and index vector
embeddings for bibliographic records

This is a subclass of Koha::BackgroundJob.

Can operate in two modes:

=over 4

=item * B<Incremental> — takes a list of biblionumbers via C<record_ids> and
embeds only those records. Used by the ES indexer daemon when individual
records are saved.

=item * B<Full rebuild> — iterates every biblio in the catalogue. Triggered
when an embedding provider is activated or its configuration changes. Pass
C<rebuild_all => 1> to C<enqueue> to use this mode. The search layer uses
active full-rebuild jobs to detect when semantic search should be temporarily
disabled.

=back

Embeddings are stored via a partial Elasticsearch C<doc> update so existing
MARC data is never overwritten.

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type { return 'index_biblio_embeddings' }

=head3 rebuild_in_progress

Returns true when a full-rebuild job (C<rebuild_all => 1>) is currently
active (status C<new> or C<started>).

=cut

sub rebuild_in_progress {
    for my $job (
        Koha::BackgroundJobs->search( { type => 'index_biblio_embeddings', status => { -in => [qw(new started)] } } )
        ->as_list )
    {
        my $data = $job->decoded_data;
        return 1 if $data && $data->{rebuild_all};
    }
    return 0;
}

=head3 enqueue

Enqueue an embedding job.

Incremental (specific records):

    Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue({
        record_ids => \@biblionumbers,
    });

Full rebuild (all records):

    Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue({
        rebuild_all => 1,
    });

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    if ( $args->{rebuild_all} ) {
        my $job_size = Koha::Biblios->search->count;
        return unless $job_size;

        $self->SUPER::enqueue(
            {
                job_size  => $job_size,
                job_args  => { rebuild_all => 1 },
                job_queue => 'long_tasks',
            }
        );
    } else {
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
}

=head3 process

Process the job: generate and store embeddings.

=cut

sub process {
    my ( $self, $args ) = @_;

    return if $self->status eq 'cancelled';

    $self->start;

    my $embedder = Koha::SearchEngine::Embedder->new;
    my $es_obj   = Koha::SearchEngine::Elasticsearch->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
    my $es       = $es_obj->get_elasticsearch;

    my $report = {
        total     => $args->{rebuild_all} ? 0 : scalar @{ $args->{record_ids} // [] },
        success   => 0,
        skipped   => 0,
        es_errors => 0,
    };

    my @bulk_body;

    my $flush_to_es = sub {
        return unless @bulk_body;
        try {
            my $response = $es->bulk(
                index => $es_obj->index_name,
                body  => \@bulk_body,
            );
            if ( $response->{errors} ) {
                my @failed     = grep { ( values %$_ )[0]{error} } @{ $response->{items} };
                my $n_failed   = scalar @failed;
                my $n_total    = scalar @{ $response->{items} };
                my @failed_ids = map { ( values %$_ )[0]{_id} } @failed;
                my $reason     = ( values %{ $failed[0] } )[0]{error}{reason} // 'unknown';
                warn sprintf(
                    "IndexBiblioEmbeddings: %d/%d ES bulk update(s) failed" . " (reason: %s; biblionumbers: %s)\n",
                    $n_failed, $n_total, $reason, join( ', ', @failed_ids )
                );
                $report->{es_errors} += $n_failed;
            }
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
            push @bulk_body, { update => { _id       => $pending[$i]{biblionumber} . q{} } };
            push @bulk_body, { doc    => { embedding => $vector } };
            $report->{success}++;
        }
        @pending = ();
        $flush_to_es->() if @bulk_body >= 200;
    };

    if ( $args->{rebuild_all} ) {
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
    } else {
        for my $biblionumber ( sort { $a <=> $b } @{ $args->{record_ids} } ) {
            last if $self->get_from_storage->status eq 'cancelled';

            my $text = $embedder->text_for_biblio($biblionumber);
            unless ($text) {
                $report->{skipped}++;
                $self->step;
                next;
            }

            push @pending, { biblionumber => $biblionumber, text => $text };
            $process_pending->() if @pending >= $batch_size;
            $self->step;
        }
    }

    $process_pending->();
    $flush_to_es->();

    my $data = $self->decoded_data;
    $data->{report} = $report;
    $self->finish($data);
}

1;
