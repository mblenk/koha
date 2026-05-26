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

use Koha::SearchEngine;
use Koha::SearchEngine::Search;
use Koha::SearchEngine::LLMClient;

use constant TOP_N => 5;
use constant CATALOGUE_PREAMBLE =>
    "You are a library catalogue assistant. Your role is to help users discover books and materials in the library collection — not to answer their questions directly. When shown catalogue search results, briefly describe the items found and how they relate to the user's topic. If results look relevant, say so. If they seem off-target, suggest how the user might refine their search. Never provide factual answers to questions; instead, point to library resources the user can explore.";
use constant NORMALISATION_PROMPT =>
    "You are a multilingual library search query normaliser. Given a search query in any language, extract and return only the core subject matter as a concise natural search phrase in the same language as the input. Strip conversational preamble and filler (phrases meaning \"I want to find\", \"Can you show me\", \"I'm looking for\", and their equivalents in any language). Remove generic library terms such as \"books\", \"articles\", \"resources\" and their equivalents. Return only the phrase — no explanation, no trailing punctuation.";

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

    my $search_query = $self->_normalise_query( $query, $client );
    my $results      = $self->_run_search($search_query);
    my $context      = $self->_format_context( $query, $results );

    my $extra         = $client->system_prompt // '';
    my $system_prompt = CATALOGUE_PREAMBLE;
    $system_prompt .= "\n\n$extra" if length $extra;

    my @messages = (
        @$history,
        { role => 'user', content => $context },
    );

    my $reply = $client->chat( \@messages, $system_prompt );
    return undef unless defined $reply;

    my @updated_history = (
        @$history,
        { role => 'user',      content => $query },
        { role => 'assistant', content => $reply },
    );

    return {
        reply        => $reply,
        results      => $results,
        conversation => \@updated_history,
        search_url   => $self->{_search_url} . '?q=' . uri_escape_utf8($query) . '&semantic=1',
    };
}

=head2 _run_search

    my $results = $self->_run_search($query);

Runs a semantic search against the bibliographic index and returns an arrayref
of record summary hashrefs (see L</_record_summary>). Returns an empty arrayref
on error or when no results are found.

=cut

sub _run_search {
    my ( $self, $query ) = @_;

    my $searcher = Koha::SearchEngine::Search->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );

    my ( $error, $results_hashref ) = $searcher->semantic_search( $query, $self->{_top_n}, 0 );
    return [] if $error || !$results_hashref;

    my $server_results = $results_hashref->{biblioserver} or return [];
    my $records        = $server_results->{RECORDS}       or return [];

    my @search_results;
    for my $record ( @{$records} ) {
        next unless $record;
        push @search_results, _record_summary($record);
    }
    return \@search_results;
}

=head2 _normalise_query

    my $search_query = $self->_normalise_query( $query, $client );

Extracts the core subject-matter keywords from a conversational query by
calling the LLM with a focused extraction prompt. Returns the original C<$query>
unchanged if the query is already concise (four words or fewer) or if the LLM
call fails.

=cut

sub _normalise_query {
    my ( $self, $query, $client ) = @_;

    my @words = split /\s+/, $query;
    return $query if @words <= 4;

    my $normalised = $client->chat(
        [ { role => 'user', content => $query } ],
        NORMALISATION_PROMPT,
    );
    $normalised =~ s/\n.*//s;
    $normalised =~ s/^\s+|\s+$//g;
    $normalised =~ s/[.!?,;:]+$//;
    return ( defined $normalised && length $normalised ) ? $normalised : $query;
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

    my $context = $self->_format_context($query, \@results);

Formats the search query and result summaries into a human-readable context
string suitable for inclusion in an LLM prompt. Returns a plain text string.

=cut

sub _format_context {
    my ( $self, $query, $results ) = @_;

    my $context = "You searched the library catalogue for: \"$query\"\n\n";

    if ( !@$results ) {
        $context .= "No results were found for this query.";
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

    return $context;
}

1;
