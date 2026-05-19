#!/usr/bin/perl

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

rebuild_embeddings.pl - Generate and index vector embeddings for all biblio records

=head1 SYNOPSIS

rebuild_embeddings.pl [--commit=N] [--bnumber=N] [-v] [-h]

=head1 DESCRIPTION

Iterates all (or specified) bibliographic records, generates a vector embedding
for each via the configured embedding provider, and stores the embedding in the
existing Elasticsearch document using a partial update.

The existing MARC data and index fields are preserved — only the C<embedding>
field is added or updated.

Run this after:

=over 4

=item * Enabling C<VectorSearchEnabled> and recreating the ES index

=item * Changing the active embedding provider (model, dimensions, or fields config)

=back

=head1 OPTIONS

=over

=item B<-c|--commit>=I<N>

Batch size for Elasticsearch bulk update requests. Default: 100.

=item B<-b|--bnumber>=I<N>

Only embed this biblionumber. May be repeated for multiple records.

=item B<-v|--verbose>

Print progress messages.

=item B<-h|--help>

Show this help message.

=back

=cut

use autodie;
use Modern::Perl;
use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );
use Try::Tiny    qw( catch try );

use Koha::Script;
use C4::Context;
use Koha::Biblios;
use Koha::SearchEngine;
use Koha::SearchEngine::Elasticsearch;
use Koha::SearchEngine::Embedder;
use Koha::EmbeddingProviders;

my ( $commit, $verbose, $help );
my @bnumbers;
$commit = 100;

GetOptions(
    'c|commit=i'  => \$commit,
    'b|bnumber=i' => \@bnumbers,
    'v|verbose+'  => \$verbose,
    'h|help'      => \$help,
) or pod2usage(1);
pod2usage(0) if $help;

die "VectorSearchEnabled syspref is off — nothing to do\n"
    unless C4::Context->preference('VectorSearchEnabled');

die "No active embedding provider configured — nothing to do\n"
    unless Koha::EmbeddingProviders->search( { status => 'active' } )->count;

my $embedder = Koha::SearchEngine::Embedder->new;
my $es_obj   = Koha::SearchEngine::Elasticsearch->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
my $es       = $es_obj->get_elasticsearch;

# Build iterator over biblionumbers
my $iterator;
if (@bnumbers) {
    my @ids = @bnumbers;
    $iterator = sub { shift @ids };
} else {
    my $rs = Koha::Biblios->search(
        {},
        {
            columns  => ['biblionumber'],
            order_by => { -asc => 'biblionumber' },
        }
    );
    $iterator = sub {
        my $row = $rs->next or return;
        return $row->biblionumber;
    };
}

my ( $count, $skipped ) = ( 0, 0 );
my @bulk_body;

my $flush = sub {
    return unless @bulk_body;
    try {
        my $response = $es->bulk(
            index => $es_obj->index_name,
            body  => \@bulk_body,
        );
        if ( $response->{errors} ) {
            warn "rebuild_embeddings: some ES bulk update errors occurred\n";
        }
    } catch {
        warn "rebuild_embeddings: ES bulk update failed: $_\n";
    };
    @bulk_body = ();
};

while ( defined( my $biblionumber = $iterator->() ) ) {
    my $text = $embedder->text_for_biblio($biblionumber);
    unless ($text) {
        $skipped++;
        next;
    }

    my $vector = $embedder->embed($text);
    unless ($vector) {
        $skipped++;
        warn "rebuild_embeddings: could not embed biblio $biblionumber\n" if $verbose;
        next;
    }

    # Partial update: each record requires two lines in the ES bulk body
    push @bulk_body, { update => { _id       => "$biblionumber" } };
    push @bulk_body, { doc    => { embedding => $vector } };
    $count++;

    if ( @bulk_body >= $commit * 2 ) {
        $flush->();
        print "[$count records embedded]\n" if $verbose;
    }
}
$flush->();

print "Done. Embedded: $count, Skipped: $skipped\n";
