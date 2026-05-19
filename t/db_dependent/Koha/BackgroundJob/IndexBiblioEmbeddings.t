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

use Modern::Perl;

use Test::More tests => 8;
use Test::NoWarnings;
use Test::MockModule;
use Test::MockObject;

use Koha::Database;
use Koha::BackgroundJobs;
use Koha::BackgroundJob::IndexBiblioEmbeddings;
use Koha::Biblios;

use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'enqueue() — with record_ids' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my @biblios = map { $builder->build_object( { class => 'Koha::Biblios' } ) } 1 .. 3;
    my @ids = map { $_->biblionumber } @biblios;

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;

    ok( defined $job_id,     'enqueue returns a job id' );
    is( $job->size,   3,     'job size matches number of record_ids' );
    is( $job->status, 'new', 'initial status is new' );
    is( $job->queue,  'long_tasks', 'uses long_tasks queue' );

    $schema->storage->txn_rollback;
};

subtest 'enqueue() — with empty record_ids' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => [] } );
    is( $job_id, undef, 'enqueue returns undef for empty record_ids' );

    $schema->storage->txn_rollback;
};

subtest 'process() — all embeddings succeed' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    my @biblios = map { $builder->build_object( { class => 'Koha::Biblios' } ) } 1 .. 3;
    my @ids     = map { $_->biblionumber } @biblios;

    my $mock_embedder_class = Test::MockModule->new('Koha::SearchEngine::Embedder');
    my $mock_embedder       = Test::MockObject->new;
    $mock_embedder->mock( 'embed_batch', sub {
        my ( $self, $texts ) = @_;
        return [ map { [ 0.1, 0.2, 0.3 ] } @$texts ];
    } );
    $mock_embedder_class->mock( 'new',            sub { $mock_embedder } );
    $mock_embedder_class->mock( 'text_for_biblio', sub { 'test text' } );

    my @bulk_calls;
    my $mock_es_client = Test::MockObject->new;
    $mock_es_client->mock( 'bulk', sub { push @bulk_calls, [@_]; return { errors => 0 } } );
    my $mock_es_class = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
    my $mock_es_obj   = Test::MockObject->new;
    $mock_es_obj->mock( 'get_elasticsearch', sub { $mock_es_client } );
    $mock_es_obj->mock( 'index_name',        sub { 'koha_test_biblios' } );
    $mock_es_class->mock( 'new', sub { $mock_es_obj } );

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;
    $job->process( { record_ids => \@ids } );

    my $report = $job->decoded_data->{report};

    is( $job->status,       'finished', 'job status is finished' );
    is( $report->{total},   3,          'total matches number of record_ids' );
    is( $report->{success}, 3,          'all records embedded successfully' );
    is( $report->{skipped}, 0,          'no records skipped' );
    ok( scalar @bulk_calls >= 1,        'bulk called at least once to flush embeddings to ES' );

    $schema->storage->txn_rollback;
};

subtest 'process() — text_for_biblio returns undef for one record' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my @biblios   = map { $builder->build_object( { class => 'Koha::Biblios' } ) } 1 .. 3;
    my @ids       = map { $_->biblionumber } @biblios;
    my $skip_id   = $ids[1];

    my $mock_embedder_class = Test::MockModule->new('Koha::SearchEngine::Embedder');
    my $mock_embedder       = Test::MockObject->new;
    $mock_embedder->mock( 'embed_batch', sub {
        my ( $self, $texts ) = @_;
        return [ map { [ 0.1, 0.2, 0.3 ] } @$texts ];
    } );
    $mock_embedder_class->mock( 'new', sub { $mock_embedder } );
    $mock_embedder_class->mock(
        'text_for_biblio',
        sub {
            my ( $class, $bnum ) = @_;
            return undef if $bnum == $skip_id;
            return 'test text';
        }
    );

    my $mock_es_client = Test::MockObject->new;
    $mock_es_client->mock( 'bulk', sub { return { errors => 0 } } );
    my $mock_es_class = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
    my $mock_es_obj   = Test::MockObject->new;
    $mock_es_obj->mock( 'get_elasticsearch', sub { $mock_es_client } );
    $mock_es_obj->mock( 'index_name',        sub { 'koha_test_biblios' } );
    $mock_es_class->mock( 'new', sub { $mock_es_obj } );

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;
    $job->process( { record_ids => \@ids } );

    my $report = $job->decoded_data->{report};

    is( $job->status,       'finished', 'job status is finished' );
    is( $report->{total},   3,          'total matches number of record_ids' );
    is( $report->{success}, 2,          'two records embedded successfully' );
    is( $report->{skipped}, 1,          'one record skipped due to empty text' );

    $schema->storage->txn_rollback;
};

subtest 'process() — embed_batch returns undef for one record' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my @biblios = map { $builder->build_object( { class => 'Koha::Biblios' } ) } 1 .. 3;
    my @ids     = map { $_->biblionumber } @biblios;

    my $mock_embedder_class = Test::MockModule->new('Koha::SearchEngine::Embedder');
    my $mock_embedder       = Test::MockObject->new;
    my $embed_count = 0;
    $mock_embedder->mock(
        'embed_batch',
        sub {
            my ( $self, $texts ) = @_;
            return [ map { $embed_count++ == 0 ? undef : [ 0.1, 0.2, 0.3 ] } @$texts ];
        }
    );
    $mock_embedder_class->mock( 'new',            sub { $mock_embedder } );
    $mock_embedder_class->mock( 'text_for_biblio', sub { 'test text' } );

    my $mock_es_client = Test::MockObject->new;
    $mock_es_client->mock( 'bulk', sub { return { errors => 0 } } );
    my $mock_es_class = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
    my $mock_es_obj   = Test::MockObject->new;
    $mock_es_obj->mock( 'get_elasticsearch', sub { $mock_es_client } );
    $mock_es_obj->mock( 'index_name',        sub { 'koha_test_biblios' } );
    $mock_es_class->mock( 'new', sub { $mock_es_obj } );

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;
    $job->process( { record_ids => \@ids } );

    my $report = $job->decoded_data->{report};

    is( $job->status,       'finished', 'job status is finished' );
    is( $report->{total},   3,          'total matches number of record_ids' );
    is( $report->{success}, 2,          'two records embedded successfully' );
    is( $report->{skipped}, 1,          'one record skipped due to null embedding' );

    $schema->storage->txn_rollback;
};

subtest 'process() — cancelled before start' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my @ids    = ( $biblio->biblionumber );

    my @bulk_calls;
    my $mock_es_client = Test::MockObject->new;
    $mock_es_client->mock( 'bulk', sub { push @bulk_calls, [@_]; return { errors => 0 } } );
    my $mock_es_class = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
    my $mock_es_obj   = Test::MockObject->new;
    $mock_es_obj->mock( 'get_elasticsearch', sub { $mock_es_client } );
    $mock_es_obj->mock( 'index_name',        sub { 'koha_test_biblios' } );
    $mock_es_class->mock( 'new', sub { $mock_es_obj } );

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;
    $job->set( { status => 'cancelled' } )->store;

    $job->process( { record_ids => \@ids } );

    is( $job->status,       'cancelled', 'status remains cancelled when pre-cancelled' );
    is( scalar @bulk_calls, 0,           'no ES bulk calls made for cancelled job' );

    $schema->storage->txn_rollback;
};

subtest 'process() — ES bulk throws' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my @biblios = map { $builder->build_object( { class => 'Koha::Biblios' } ) } 1 .. 2;
    my @ids     = map { $_->biblionumber } @biblios;

    my $mock_embedder_class = Test::MockModule->new('Koha::SearchEngine::Embedder');
    my $mock_embedder       = Test::MockObject->new;
    $mock_embedder->mock( 'embed_batch', sub {
        my ( $self, $texts ) = @_;
        return [ map { [ 0.1, 0.2, 0.3 ] } @$texts ];
    } );
    $mock_embedder_class->mock( 'new',            sub { $mock_embedder } );
    $mock_embedder_class->mock( 'text_for_biblio', sub { 'test text' } );

    my $mock_es_client = Test::MockObject->new;
    $mock_es_client->mock( 'bulk', sub { die "simulated ES failure\n" } );
    my $mock_es_class = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
    my $mock_es_obj   = Test::MockObject->new;
    $mock_es_obj->mock( 'get_elasticsearch', sub { $mock_es_client } );
    $mock_es_obj->mock( 'index_name',        sub { 'koha_test_biblios' } );
    $mock_es_class->mock( 'new', sub { $mock_es_obj } );

    my $job_id = Koha::BackgroundJob::IndexBiblioEmbeddings->new->enqueue( { record_ids => \@ids } );
    my $job    = Koha::BackgroundJobs->find($job_id)->_derived_class;

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    $job->process( { record_ids => \@ids } );

    is( $job->status, 'finished', 'job completes despite ES bulk failure' );
    like( $warnings[0], qr/ES bulk update failed/, 'warning issued on bulk failure' );

    $schema->storage->txn_rollback;
};
