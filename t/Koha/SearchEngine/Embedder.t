#!/usr/bin/perl

use Modern::Perl;

use HTTP::Response;
use JSON qw( decode_json encode_json );
use Test::MockModule;
use Test::MockObject;
use Test::More tests => 12;
use Test::NoWarnings;

use_ok('Koha::SearchEngine::Embedder');

sub _make_response {
    my (%opts) = @_;
    my $response = HTTP::Response->new( $opts{code} // 200, $opts{message} // 'OK' );
    $response->content_type('application/json');
    $response->content( $opts{body} // '' );
    return $response;
}

sub _mock_ua_returning {
    my ($response) = @_;
    my $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock( 'request', sub { $response } );
    return $mock;
}

# Construct an embedder with provider-agnostic defaults, overridable via %extra.
sub _embedder {
    my (%extra) = @_;
    return Koha::SearchEngine::Embedder->new(
        {
            url                   => 'http://provider.test/embed',
            model                 => 'test-model',
            auth_type             => 'none',
            request_body_template => '{"model":"{{model}}","prompt":"{{text}}"}',
            response_key          => 'embedding',
            %extra,
        }
    );
}

subtest 'new()' => sub {
    plan tests => 4;

    # Direct args path — values stored on the object
    my $embedder = _embedder();
    is( $embedder->{_url},   'http://provider.test/embed', 'url stored from direct args' );
    is( $embedder->{_model}, 'test-model',                 'model stored from direct args' );

    # DB-lookup path — reads from mocked EmbeddingProviders row
    my $mock_record = Test::MockObject->new;
    $mock_record->mock( 'url',                   sub { 'http://db.provider.test/embed' } );
    $mock_record->mock( 'model',                 sub { 'db-model' } );
    $mock_record->mock( 'plain_text_api_key',    sub { '' } );
    $mock_record->mock( 'auth_type',             sub { 'none' } );
    $mock_record->mock( 'request_body_template', sub { '{"model":"{{model}}","prompt":"{{text}}"}' } );
    $mock_record->mock( 'query_body_template',   sub { undef } );
    $mock_record->mock( 'response_key',          sub { 'embedding' } );
    $mock_record->mock( 'marc_fields_config',    sub { '' } );
    $mock_record->mock( 'batch_size',            sub { 1 } );

    my $mock_rs = Test::MockObject->new;
    $mock_rs->mock( 'next', sub { $mock_record } );

    my $mock_providers = Test::MockModule->new('Koha::EmbeddingProviders');
    $mock_providers->mock( 'search', sub { $mock_rs } );

    my $embedder2 = Koha::SearchEngine::Embedder->new;
    is( $embedder2->{_url}, 'http://db.provider.test/embed', 'url read from active DB provider record' );

    # No active provider and no args — must die
    my $mock_empty_rs = Test::MockObject->new;
    $mock_empty_rs->mock( 'next', sub { undef } );
    $mock_providers->mock( 'search', sub { $mock_empty_rs } );
    eval { Koha::SearchEngine::Embedder->new };
    ok( $@, 'dies when no active embedding provider is configured' );
};

subtest 'embed_query()' => sub {
    plan tests => 17;

    my ( $mock, $vector, $captured, $captured_req, $call_count, $warned, $embedder );

    # Flat response body: {"embedding":[...]}
    $mock   = _mock_ua_returning( _make_response( body => encode_json( { embedding => [ 0.1, 0.2, 0.3 ] } ) ) );
    $vector = _embedder( response_key => 'embedding' )->embed_query('some text');
    is( ref($vector),    'ARRAY', 'flat response key: returns arrayref' );
    is( scalar @$vector, 3,       'flat response key: correct number of dimensions' );

    # Nested response body: {"data":[{"embedding":[...]}]}
    $mock =
        _mock_ua_returning( _make_response( body => encode_json( { data => [ { embedding => [ 1.0, 2.0 ] } ] } ) ) );
    $vector = _embedder(
        request_body_template => '{"model":"{{model}}","input":"{{text}}"}',
        response_key          => 'data.0.embedding',
    )->embed_query('search text');
    is( $vector->[0], 1.0, 'nested response key: first embedding value correct' );

    # Sentinel substitution in request body
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured = decode_json( $req->content );
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder()->embed_query('hello world');
    is( $captured->{model},  'test-model',  '{{model}} sentinel substituted in request body' );
    is( $captured->{prompt}, 'hello world', '{{text}} sentinel substituted in request body' );

    # Bearer auth — Authorization header attached
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured_req = $req;
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder( auth_type => 'bearer', api_key => 'test-key' )->embed_query('text');
    like(
        $captured_req->header('Authorization'),
        qr/^Bearer test-key$/,
        'auth_type=bearer sends Authorization: Bearer header'
    );

    # auth_type=none — no Authorization header
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured_req = $req;
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder( auth_type => 'none' )->embed_query('text');
    ok( !defined $captured_req->header('Authorization'), 'auth_type=none sends no Authorization header' );

    # Empty and undef input — no HTTP call, returns undef
    $call_count = 0;
    $mock       = Test::MockModule->new('LWP::UserAgent');
    $mock->mock( 'request', sub { $call_count++; _make_response( body => encode_json( { embedding => [1] } ) ) } );
    $embedder = _embedder();
    is( $embedder->embed_query(''),    undef, 'empty string returns undef' );
    is( $embedder->embed_query(undef), undef, 'undef returns undef' );
    is( $call_count,                   0,     'no HTTP calls made for empty or undef input' );

    # HTTP error — returns undef with warning
    $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    $mock   = _mock_ua_returning( _make_response( code => 500, message => 'Internal Server Error' ) );
    $vector = _embedder()->embed_query('will fail');
    is( $vector, undef, 'HTTP 5xx returns undef' );
    like( $warned, qr/embedding failed/i, 'HTTP 5xx emits a warning' );

    # Network exception — returns undef with warning
    $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock( 'request', sub { die "Connection refused\n" } );
    $vector = _embedder()->embed_query('some text');
    is( $vector, undef, 'network exception returns undef' );
    like( $warned, qr/embedding failed/i, 'network exception emits a warning' );

    # Long text truncated before sending
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured = decode_json( $req->content );
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder()->embed_query( 'x' x 3000 );
    ok( length( $captured->{prompt} ) <= 2000, 'text longer than MAX_TEXT_LENGTH is truncated in the request' );

    # Uses query_body_template when configured
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured = decode_json( $req->content );
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","prompt":"doc: {{text}}"}',
        query_body_template   => '{"model":"{{model}}","prompt":"query: {{text}}"}',
    )->embed_query('books');
    like( $captured->{prompt}, qr/^query:/, 'embed_query() uses query_body_template when configured' );

    # Falls back to request_body_template when no query_body_template
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured = decode_json( $req->content );
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","prompt":"fallback: {{text}}"}',
    )->embed_query('books');
    like(
        $captured->{prompt}, qr/^fallback:/,
        'embed_query() falls back to request_body_template when no query_body_template'
    );
};

subtest 'embed_document()' => sub {
    plan tests => 3;

    my ( $mock, $vector, $captured );

    # Successful embed — returns arrayref
    $mock   = _mock_ua_returning( _make_response( body => encode_json( { embedding => [ 0.5, 0.6 ] } ) ) );
    $vector = _embedder()->embed_document('a document about history');
    is( ref($vector), 'ARRAY', 'embed_document() returns an arrayref on success' );

    # When both templates configured, uses request_body_template (not query template)
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            $captured = decode_json( $req->content );
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","prompt":"doc: {{text}}"}',
        query_body_template   => '{"model":"{{model}}","prompt":"query: {{text}}"}',
    )->embed_document('a document');
    like(
        $captured->{prompt}, qr/^doc:/,
        'embed_document() uses request_body_template even when query_body_template is configured'
    );

    # Works when only request_body_template is configured
    $mock   = _mock_ua_returning( _make_response( body => encode_json( { embedding => [0.9] } ) ) );
    $vector = _embedder()->embed_document('another document');
    ok( defined $vector, 'embed_document() works when only request_body_template is configured' );
};

subtest 'embed_batch()' => sub {
    plan tests => 12;

    my ( $mock, $vectors, $call_count, @captured, $warned, $single_calls );

    # batch_size=1 — sequential embed_document calls, one per text
    $call_count = 0;
    $mock       = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            $call_count++;
            return _make_response( body => encode_json( { embedding => [ 0.1, 0.2 ] } ) );
        }
    );
    $vectors = _embedder( batch_size => 1 )->embed_batch( [ 'text one', 'text two', 'text three' ] );
    is( $call_count,      3, 'batch_size=1: one HTTP call per text' );
    is( scalar @$vectors, 3, 'batch_size=1: one vector per input' );

    # batch_size>1 — texts sent as JSON array, single HTTP call for a full chunk
    @captured = ();
    $mock     = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            push @captured, decode_json( $req->content );
            return _make_response(
                body => encode_json( { data => [ { embedding => [ 0.1, 0.2 ] }, { embedding => [ 0.3, 0.4 ] } ] } ) );
        }
    );
    $vectors = _embedder(
        request_body_template => '{"model":"{{model}}","input":"{{text}}"}',
        response_key          => 'data.0.embedding',
        batch_size            => 2,
    )->embed_batch( [ 'text one', 'text two' ] );
    is( scalar @captured,           1,       'batch_size>1: single HTTP call for a full chunk' );
    is( ref( $captured[0]{input} ), 'ARRAY', 'batch_size>1: texts sent as JSON array' );
    is( scalar @$vectors,           2,       'batch_size>1: one vector per input text' );

    # Chunking — 4 texts with batch_size=2 produces exactly 2 HTTP calls
    $call_count = 0;
    $mock       = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            $call_count++;
            return _make_response(
                body => encode_json( { data => [ { embedding => [0.1] }, { embedding => [0.2] } ] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","input":"{{text}}"}',
        response_key          => 'data.0.embedding',
        batch_size            => 2,
    )->embed_batch( [ 'a', 'b', 'c', 'd' ] );
    is( $call_count, 2, 'chunking: two HTTP calls for 4 texts with batch_size=2' );

    # Batch HTTP failure — sequential fallback with warning
    $warned       = '';
    $single_calls = 0;
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            my $body = decode_json( $req->content );
            if ( ref( $body->{input} ) eq 'ARRAY' ) {
                return _make_response( code => 503, message => 'Service Unavailable' );
            }
            $single_calls++;
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","input":"{{text}}"}',
        response_key          => 'embedding',
        batch_size            => 3,
    )->embed_batch( [ 'a', 'b', 'c' ] );
    is( $single_calls, 3, 'batch HTTP failure: falls back to 3 sequential calls' );
    like( $warned, qr/batch embedding failed/i, 'batch HTTP failure: warning emitted' );

    # Count mismatch — batch returns fewer vectors than inputs, falls back with warning
    $warned       = '';
    $single_calls = 0;
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            my ( undef, $req ) = @_;
            my $body = decode_json( $req->content );
            if ( ref( $body->{input} ) eq 'ARRAY' ) {

                # Returns only 1 vector for 3 inputs
                return _make_response( body => encode_json( { data => [ { embedding => [0.1] } ] } ) );
            }
            $single_calls++;
            return _make_response( body => encode_json( { data => [ { embedding => [0.1] } ] } ) );
        }
    );
    _embedder(
        request_body_template => '{"model":"{{model}}","input":"{{text}}"}',
        response_key          => 'data.0.embedding',
        batch_size            => 3,
    )->embed_batch( [ 'a', 'b', 'c' ] );
    is( $single_calls, 3, 'count mismatch: falls back to 3 sequential calls' );
    like( $warned, qr/batch embedding failed/i, 'count mismatch: warning emitted' );

    # undef in input — _do_embed_batch dies, falls back; undef preserved in result
    $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    $mock = Test::MockModule->new('LWP::UserAgent');
    $mock->mock(
        'request',
        sub {
            return _make_response( body => encode_json( { embedding => [0.1] } ) );
        }
    );
    $vectors = _embedder( batch_size => 3 )->embed_batch( [ 'a', undef, 'c' ] );
    like( $warned, qr/batch embedding failed/i, 'undef in batch: fallback warning emitted' );
    is( $vectors->[1], undef, 'undef in batch: result preserves undef at the correct position' );
};

subtest '_build_request_body()' => sub {
    plan tests => 5;

    my $embedder = _embedder(
        request_body_template => '{"model":"{{model}}","prompt":"{{text}}"}',
    );

    # undef template arg falls back to _request_body_template
    my $body1 = decode_json( $embedder->_build_request_body( 'hello', undef ) );
    is( $body1->{model}, 'test-model', 'undef template falls back to request_body_template' );

    # Provided template used instead of default
    my $alt   = '{"model":"{{model}}","input":"{{text}}"}';
    my $body2 = decode_json( $embedder->_build_request_body( 'hello', $alt ) );
    ok( exists $body2->{input} && !exists $body2->{prompt}, 'provided template used instead of default' );

    # {{text}} substituted
    my $body3 = decode_json( $embedder->_build_request_body( 'test phrase', undef ) );
    is( $body3->{prompt}, 'test phrase', '{{text}} substituted correctly' );

    # {{model}} substituted
    is( $body3->{model}, 'test-model', '{{model}} substituted correctly' );

    # Text in nested array-of-objects position
    my $nested_tmpl = '{"model":"{{model}}","messages":[{"role":"user","content":"{{text}}"}]}';
    my $body4       = decode_json( $embedder->_build_request_body( 'nested text', $nested_tmpl ) );
    is( $body4->{messages}[0]{content}, 'nested text', '{{text}} substituted in nested array-of-objects position' );
};

subtest '_build_batch_request_body()' => sub {
    plan tests => 5;

    my ( $embedder, $body );

    # {{text}} exact match — replaced with arrayref
    $embedder = _embedder( request_body_template => '{"model":"{{model}}","input":"{{text}}"}' );
    $body     = decode_json( $embedder->_build_batch_request_body( [ 'text one', 'text two' ] ) );
    is( ref( $body->{input} ),      'ARRAY', '{{text}} exact match replaced with arrayref' );
    is( scalar @{ $body->{input} }, 2,       'arrayref has the correct number of elements' );

    # {{text}} as substring with prefix — expanded into array of prefixed strings
    $embedder = _embedder( request_body_template => '{"model":"{{model}}","prompt":"prefix: {{text}}"}' );
    $body     = decode_json( $embedder->_build_batch_request_body( [ 'alpha', 'beta' ] ) );
    is( ref( $body->{prompt} ), 'ARRAY',         'sentinel in prefixed string produces arrayref' );
    is( $body->{prompt}[0],     'prefix: alpha', 'first element has prefix applied correctly' );

    # {{model}} substituted inside each expanded element
    $embedder = _embedder( request_body_template => '{"model":"{{model}}","input":"{{model}}: {{text}}"}' );
    $body     = decode_json( $embedder->_build_batch_request_body( [ 'doc one', 'doc two' ] ) );
    is( $body->{input}[0], 'test-model: doc one', '{{model}} substituted inside each expanded element' );
};

subtest '_resolve_path()' => sub {
    plan tests => 4;

    my $embedder = _embedder();

    my $data = {
        embedding => [ 0.1,                     0.2 ],
        items     => [ { emb => [ 1.0, 2.0 ] }, { emb => [ 3.0, 4.0 ] } ],
    };

    # Flat key
    my $flat = $embedder->_resolve_path( $data, 'embedding' );
    is( ref($flat), 'ARRAY', 'flat key: returns the value at that key' );

    # Nested key with array index
    my $nested = $embedder->_resolve_path( $data, 'items.1.emb' );
    is( $nested->[0], 3.0, 'nested key with array index: correct value extracted' );

    # Non-existent key returns undef
    my $missing = $embedder->_resolve_path( $data, 'nonexistent' );
    is( $missing, undef, 'non-existent key returns undef' );

    # Path through undef intermediate returns undef
    my $deep = $embedder->_resolve_path( $data, 'items.99.emb' );
    is( $deep, undef, 'path through undef intermediate (out-of-range index) returns undef' );
};

subtest '_resolve_batch_path()' => sub {
    plan tests => 7;

    my $embedder = _embedder();
    my ( $data, $result );

    # data.0.embedding — maps sub-key lookup over the container array
    $data = {
        data => [
            { embedding => [ 1.0, 2.0 ] },
            { embedding => [ 3.0, 4.0 ] },
            { embedding => [ 5.0, 6.0 ] },
        ]
    };
    $result = $embedder->_resolve_batch_path( $data, 'data.0.embedding' );
    is( ref($result),    'ARRAY', 'data.0.embedding: returns arrayref' );
    is( scalar @$result, 3,       'data.0.embedding: one entry per item in container' );
    is( $result->[1][0], 3.0,     'data.0.embedding: second embedding extracted correctly' );

    # embeddings.0 — numeric is the last segment; returns the container array directly
    $data   = { embeddings => [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ] };
    $result = $embedder->_resolve_batch_path( $data, 'embeddings.0' );
    is( ref($result),    'ARRAY', 'embeddings.0: returns arrayref' );
    is( $result->[1][0], 3.0,     'embeddings.0: second embedding extracted correctly' );

    # No numeric segment — falls back to _resolve_path result
    $data   = { vectors => [ [1.0], [2.0] ] };
    $result = $embedder->_resolve_batch_path( $data, 'vectors' );
    is( ref($result), 'ARRAY', 'no numeric segment: falls back to _resolve_path and returns the array' );

    # Container before numeric index is not an array — returns undef
    $data   = { data => 'not an array' };
    $result = $embedder->_resolve_batch_path( $data, 'data.0.embedding' );
    is( $result, undef, 'non-array container returns undef' );
};

subtest '_apply_subs()' => sub {
    plan tests => 7;

    my %subs = (
        '{{text}}'  => 'hello',
        '{{model}}' => 'test-model',
    );

    # Exact match — scalar replacement
    is(
        Koha::SearchEngine::Embedder::_apply_subs( '{{text}}', \%subs ),
        'hello',
        'exact match returns scalar replacement'
    );

    # Exact match — arrayref replacement
    my %arr_subs = ( '{{text}}' => [ 'a', 'b' ] );
    is(
        ref( Koha::SearchEngine::Embedder::_apply_subs( '{{text}}', \%arr_subs ) ),
        'ARRAY',
        'exact match with arrayref replacement returns arrayref'
    );

    # Sentinel as substring + arrayref — array expansion
    my %expand_subs = ( '{{text}}' => [ 'one', 'two' ] );
    my $expanded    = Koha::SearchEngine::Embedder::_apply_subs( 'prefix: {{text}}', \%expand_subs );
    is( ref($expanded), 'ARRAY',       'sentinel in substring + arrayref triggers array expansion' );
    is( $expanded->[0], 'prefix: one', 'first expanded element has sentinel replaced correctly' );

    # Sentinel as substring + scalar — in-place substitution
    is(
        Koha::SearchEngine::Embedder::_apply_subs( 'model is {{model}}', \%subs ),
        'model is test-model',
        'scalar sentinel as substring replaced in-place'
    );

    # Multiple scalar sentinels in one string — both substituted
    is(
        Koha::SearchEngine::Embedder::_apply_subs( '{{model}}: {{text}}', \%subs ),
        'test-model: hello',
        'multiple scalar sentinels in one string are both substituted'
    );

    # undef input — treated as empty string, no crash
    ok(
        defined( Koha::SearchEngine::Embedder::_apply_subs( undef, \%subs ) ),
        'undef input does not crash'
    );
};

subtest '_truncate()' => sub {
    plan tests => 3;

    my $short = 'hello world';
    is(
        Koha::SearchEngine::Embedder::_truncate($short),
        $short,
        'string shorter than MAX_TEXT_LENGTH returned unchanged'
    );

    my $exact = 'x' x 2000;
    is(
        length( Koha::SearchEngine::Embedder::_truncate($exact) ),
        2000,
        'string of exactly MAX_TEXT_LENGTH characters returned unchanged'
    );

    my $long = 'y' x 2001;
    is(
        length( Koha::SearchEngine::Embedder::_truncate($long) ),
        2000,
        'string over MAX_TEXT_LENGTH truncated to exactly 2000 characters'
    );
};
