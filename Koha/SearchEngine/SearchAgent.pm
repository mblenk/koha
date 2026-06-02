package Koha::SearchEngine::SearchAgent;

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

Koha::SearchEngine::SearchAgent - conversational search agent combining semantic search with LLM dialogue

=head1 SYNOPSIS

    my $agent = Koha::SearchEngine::SearchAgent->new( search_url => '/cgi-bin/koha/catalogue/search.pl' );

    my $result = $agent->converse(
        query       => "books about Victorian London",
        history     => [],   # prior { role, content } turns
    );
    # $result->{reply}        — LLM response string
    # $result->{results}      — arrayref of { biblio_id, title, author, year }
    # $result->{conversation} — updated history arrayref
    # $result->{search_url}   — URL to see all results

=head1 DESCRIPTION

Runs a vector semantic search for the user's query, formats the top results as
context for an LLM, calls the LLM, and returns a structured response. Conversation
history is managed by the caller — full history is passed in and the updated history
(with the new user and assistant turns appended) is returned.

=cut

use Modern::Perl;

use URI::Escape qw( uri_escape_utf8 );
use Encode      qw(decode_utf8);

use Koha::SearchEngine;
use Koha::SearchEngine::Search;
use Koha::SearchEngine::LLMClient;

use constant TOP_N => 5;
use constant CATALOGUE_PREAMBLE =>
    "You are a library catalogue assistant. Help users discover items in this specific library's collection.\n"
    . "STRICT RULE: You may only mention titles, authors, and works that appear in the catalogue search results "
    . "provided to you in each message. Never name, suggest, or allude to any book, author, or title from your "
    . "training knowledge — even if you know of highly relevant works. Your knowledge of the outside world does "
    . "not exist for the purposes of this conversation.\n"
    . "When results are shown: describe how the found items relate to the user's topic. "
    . "When no results are found or results seem off-target: say so clearly and suggest how the user might "
    . "rephrase or broaden their search. Never answer factual questions directly.";

=head1 METHODS

=head2 new

    my $agent = Koha::SearchAgent->new( search_url => '...', top_n => 5 );

Constructor.

=over 4

=item C<search_url> — base URL for the "see all results" link (required)

=item C<top_n> — number of results to fetch and pass as context (default: 5)

=back

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless {
        _search_url => $args{search_url} // '/cgi-bin/koha/catalogue/search.pl',
        _top_n      => $args{top_n}      // TOP_N,
    }, $class;
}

=head2 converse

    my $result = $agent->converse( query => $text, history => \@history );

Run one conversation turn. Returns a hashref:

    {
        reply        => "...",        # LLM response text
        results      => [...],        # top N biblio summaries
        conversation => [...],        # updated history
        search_url   => "...",        # link for "see all results"
    }

Returns C<undef> if the LLM call fails.

=cut

sub converse {
    my ( $self, %args ) = @_;

    my $query   = $args{query}   // '';
    my $history = $args{history} // [];

    my $client = Koha::SearchEngine::LLMClient->new;
    my $extra  = $client->system_prompt // '';
    my $system = CATALOGUE_PREAMBLE;
    $system .= "\n\n$extra" if length $extra;

    my @messages   = ( @$history, { role => 'user', content => $query } );
    my $results    = [];
    my $search_url = $self->{_search_url} . '?q=' . uri_escape_utf8($query);

    my $iterations = 0;
    my $response   = $client->chat_with_tools( \@messages, $system );

    while ( $response && $response->{type} eq 'tool_call' && $iterations++ < 3 ) {
        for my $call ( @{ $response->{tool_calls} } ) {
            next unless $call->{name} eq 'search_catalogue';
            my $targs     = $call->{arguments};
            my $sem_query = $targs->{semantic_query} // $targs->{query};
            my $kw_query  = $targs->{keyword_query}  // $targs->{query};
            my $strategy  = $targs->{strategy}       // 'semantic';
            $results = $self->_run_search( $strategy, $sem_query, $kw_query );
            my $context   = $self->_format_context( $sem_query, $results, $query );
            my $url_query = ( $strategy eq 'semantic' ) ? $sem_query : $kw_query;
            my $url_suffix =
                  $strategy eq 'semantic' ? '&semantic=1'
                : $strategy eq 'hybrid'   ? '&strategy=hybrid&semantic_q=' . uri_escape_utf8($sem_query)
                :                           '';
            $search_url = $self->{_search_url} . '?q=' . uri_escape_utf8($url_query) . $url_suffix;

            push @messages, $response->{raw_message};
            push @messages, { role => 'tool', content => $context };

        }
        $response = $client->chat_with_tools( \@messages, $system );
    }

    return undef unless $response && $response->{type} eq 'text';

    my $decoded_reply   = decode_utf8( $response->{reply} );
    my @updated_history = (
        @$history,
        { role => 'user',      content => $query },
        { role => 'assistant', content => $decoded_reply },
    );

    return {
        reply        => $decoded_reply,
        results      => $results,
        conversation => \@updated_history,
        search_url   => $search_url,
    };
}

=head2 _run_search

    my $results = $self->_run_search( $strategy, $sem_query, $kw_query );

Searches the bibliographic index using the given strategy (C<semantic>,
C<keyword>, or C<hybrid>) and returns an arrayref of record summary hashrefs
(see L</_record_summary>). Returns an empty arrayref on error or when no
results are found. Defaults to C<semantic> if strategy is omitted.

C<$sem_query> is used for the vector/semantic search leg; C<$kw_query> is
used for the keyword search leg. Each defaults to the other if omitted,
allowing a single query to serve both when no split is provided.

=cut

sub _run_search {
    my ( $self, $strategy, $sem_query, $kw_query ) = @_;
    $strategy  //= 'semantic';
    $sem_query //= $kw_query;
    $kw_query  //= $sem_query;

    my $searcher = Koha::SearchEngine::Search->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );

    if ( $strategy eq 'semantic' ) {
        my ( $error, $results_hashref ) =
            $searcher->semantic_search( $sem_query, $self->{_top_n}, 0 );
        return [] if $error || !$results_hashref;
        my $records = $results_hashref->{biblioserver}{RECORDS} // [];
        return [ map { _record_summary($_) } grep { $_ } @$records ];
    }

    if ( $strategy eq 'keyword' ) {
        my ( $error, $records ) =
            $searcher->simple_search_compat( $kw_query, 0, $self->{_top_n} );
        return [] if $error || !$records;
        return [ map { _record_summary($_) } grep { $_ } @$records ];
    }

    # Hybrid: delegate to hybrid_search which runs both legs and applies RRF
    my $fetch_n = $self->{_top_n} * 2;
    my ( $error, $results_hashref ) = $searcher->hybrid_search( $sem_query, $kw_query, $fetch_n, 0 );
    return [] if $error || !$results_hashref;
    my $records = $results_hashref->{biblioserver}{RECORDS} // [];
    my @results = map { _record_summary($_) } grep { $_ } @$records;
    splice @results, $self->{_top_n} if @results > $self->{_top_n};
    return \@results;
}

=head2 _record_summary

    my $summary = _record_summary($record);

Extracts key bibliographic fields from a MARC::Record object and returns a
hashref with the following keys:

=over 4

=item C<biblio_id> — local record identifier (MARC 999$c)

=item C<title> — title statement (MARC 245$a), trailing punctuation stripped

=item C<author> — main entry (MARC 100, 110, or 111 $a), trailing comma stripped

=item C<publication_year> — four-digit year (MARC 264$c or 260$c)

=back

=cut

sub _record_summary {
    my ($record) = @_;

    my $f;

    $f = $record->field('999');
    my $biblio_id = $f ? ( $f->subfield('c') // '' ) : '';

    $f = $record->field('245');
    my $title = $f ? ( $f->subfield('a') // '' ) : '';
    $title =~ s/\s*[\/:]?\s*$//;    # strip trailing punctuation

    $f = $record->field('100') // $record->field('110') // $record->field('111');
    my $author = $f ? ( $f->subfield('a') // '' ) : '';
    $author =~ s/,?\s*$//;

    $f = $record->field('264') // $record->field('260');
    my $year = $f ? ( $f->subfield('c') // '' ) : '';
    $year =~ s/[^0-9]//g;
    $year = substr( $year, 0, 4 ) if length($year) > 4;

    return {
        biblio_id        => $biblio_id,
        title            => $title,
        author           => $author,
        publication_year => $year,
    };
}

=head2 _format_context

    my $context = $self->_format_context($search_query, \@results, $original_query);

Formats the search query, result summaries, and original user query into a
human-readable context string suitable for inclusion in an LLM prompt.
C<$original_query> is the raw user message; C<$search_query> is the
(possibly normalised) term actually sent to the search engine.
Returns a plain text string.

=cut

sub _format_context {
    my ( $self, $query, $results, $original_query ) = @_;

    my $context =
        "The user originally asked: \"$original_query\"\n" . "You searched the library catalogue for: \"$query\"\n\n";

    if ( !@$results ) {
        $context .= "No results were found for this query. Do not suggest titles from your own knowledge.";
        return $context;
    }

    $context .= "Catalogue items found:\n";
    my $i = 1;
    for my $r (@$results) {
        $context .= "$i. ";
        $context .= $r->{title} ? "\"$r->{title}\"" : "(no title)";
        $context .= " by $r->{author}"          if $r->{author};
        $context .= " ($r->{publication_year})" if $r->{publication_year};
        $context .= "\n";
        $i++;
    }

    $context .= "\nOnly refer to the titles listed above. Do not mention any other titles or authors.";

    return $context;
}

1;
